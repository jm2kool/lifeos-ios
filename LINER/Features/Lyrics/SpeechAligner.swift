@preconcurrency import AVFoundation
import Foundation
import NaturalLanguage
import Speech

/// Word timings for your own audio files, heard on the iPhone: iOS 26's speech transcriber listens to the
/// mixtape track, gives a time for every word it hears, and those are matched against the known lyrics
/// (keeping each word near its own line). Words it didn't catch are filled in between the ones it did. The
/// result is saved as enhanced LRC and used from then on. Apple Music songs can't be heard this way (they're
/// protected), so they keep the estimate.
enum SpeechAligner {
    private static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "LINER/AlignedLyrics", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func file(_ itemID: String) -> URL { folder.appending(path: "\(itemID).lrc") }

    /// The saved word-timed LRC for this track, if it has been aligned.
    static func aligned(_ itemID: String) -> String? { try? String(contentsOf: file(itemID), encoding: .utf8) }

    static func forget(_ itemID: String) { try? FileManager.default.removeItem(at: file(itemID)) }

    enum Outcome: Sendable { case done(matched: Int, of: Int), notEnough, unavailable }

    /// Listens to `audio` and aligns `lyrics` to it. Saves and returns `.done` when enough words matched.
    static func align(itemID: String, audio: URL, lyrics: Lyrics) async -> Outcome {
        guard lyrics.isSynced else { return .unavailable }
        guard let heard = await transcribe(audio, language: language(of: lyrics)) else { return .unavailable }
        let result = match(lyrics: lyrics, heard: heard)
        guard result.total > 0, Double(result.matched) / Double(result.total) >= 0.35 else { return .notEnough }
        try? result.lrc.write(to: file(itemID), atomically: true, encoding: .utf8)
        return .done(matched: result.matched, of: result.total)
    }

    // MARK: Listening

    struct Heard: Sendable { let word: String; let start: Double; let end: Double }

    private static func language(of lyrics: Lyrics) -> Locale {
        let sample = lyrics.lines.prefix(20).map(\.text).joined(separator: " ")
        if let code = NLLanguageRecognizer.dominantLanguage(for: sample) { return Locale(identifier: code.rawValue) }
        return Locale(identifier: "en-US")
    }

    @concurrent
    private static func transcribe(_ url: URL, language: Locale) async -> [Heard]? {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        do {
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await install.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let audio = try AVAudioFile(forReading: url)
            let collector = Task { () -> [Heard] in
                var out: [Heard] = []
                for try await result in transcriber.results where result.isFinal {
                    for run in result.text.runs {
                        guard let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else { continue }
                        let text = String(result.text[run.range].characters)
                        for w in text.split(whereSeparator: \.isWhitespace) {
                            out.append(Heard(word: String(w), start: range.start.seconds, end: range.end.seconds))
                        }
                    }
                }
                return out
            }
            if let last = try await analyzer.analyzeSequence(from: audio) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let heard = try await collector.value
            return heard.isEmpty ? nil : heard
        } catch {
            return nil
        }
    }

    // MARK: Matching

    private static func normal(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    /// Longest common run of words, allowing only matches close to the line's own time.
    static func match(lyrics: Lyrics, heard: [Heard]) -> (lrc: String, matched: Int, total: Int) {
        struct Slot { let line: Int; let word: Int; let text: String; let from: Double; let to: Double }
        var slots: [Slot] = []
        for (li, line) in lyrics.lines.enumerated() {
            let next = lyrics.lines.indices.contains(li + 1) ? lyrics.lines[li + 1].time : line.time + 10
            for (wi, w) in WordTiming.words(in: line.text).enumerated() {
                slots.append(Slot(line: li, word: wi, text: normal(w.text), from: line.time - 2.5, to: next + 2.5))
            }
        }
        let h = heard.map { (normal($0.word), $0.start, $0.end) }
        let n = slots.count, m = h.count
        guard n > 0, m > 0 else { return ("", 0, n) }
        // Classic LCS table, flattened.
        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        func at(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }
        func same(_ i: Int, _ j: Int) -> Bool {
            let s = slots[i]
            return !s.text.isEmpty && s.text == h[j].0 && h[j].1 >= s.from && h[j].1 <= s.to
        }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[at(i, j)] = same(i, j) ? table[at(i + 1, j + 1)] + 1 : max(table[at(i + 1, j)], table[at(i, j + 1)])
            }
        }
        var found: [Int: (Double, Double)] = [:]
        var i = 0, j = 0
        while i < n && j < m {
            if same(i, j) { found[i] = (h[j].1, h[j].2); i += 1; j += 1 }
            else if table[at(i + 1, j)] >= table[at(i, j + 1)] { i += 1 } else { j += 1 }
        }
        // Rebuild each line: heard words keep their times, the rest are spread between their neighbours.
        var lrc: [String] = []
        var k = 0
        for line in lyrics.lines {
            var words = WordTiming.words(in: line.text)
            let base = k
            k += words.count
            guard !words.isEmpty else { lrc.append("[\(stamp(line.time))]\(line.text)"); continue }
            var estimate = line
            estimate.end = (0..<words.count).compactMap { found[base + $0]?.1 }.max().map { max($0 + 0.4, line.time + 0.5) } ?? line.time + 3
            let guess = WordTiming.estimate(estimate)
            for w in words.indices {
                if let hit = found[base + w] { words[w].start = hit.0; words[w].end = hit.1 }
                else { words[w].start = guess[w].start; words[w].end = guess[w].end }
            }
            for w in words.indices.dropFirst() where words[w].start < words[w - 1].start { words[w].start = words[w - 1].end }
            let body = words.map { "<\(stamp($0.start))>\($0.text)\($0.space ? " " : "")" }.joined()
            lrc.append("[\(stamp(line.time))]\(body) <\(stamp(words.last!.end))>")
        }
        return (lrc.joined(separator: "\n"), found.count, n)
    }

    private static func stamp(_ t: Double) -> String {
        let t = max(0, t)
        return String(format: "%02d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
}
