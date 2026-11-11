import Foundation

/// Lyrics for one song: timed lines (synced), or plain text.
struct Lyrics: Sendable, Equatable {
    struct Line: Sendable, Equatable, Identifiable {
        let id: Int
        let time: Double
        let text: String
        /// When the line is over: the next line's start (a little after the last word for the last line).
        var end: Double = 0
        /// Each word and when it's sung: from the file's word stamps when it has them, otherwise spread over the
        /// line by length, the way a singer would.
        var words: [Word] = []

        /// The words as printed for the sing-along (single spaces), so lit characters line up with them.
        var sungText: String { words.isEmpty ? text : words.map(\.text).joined(separator: " ") }

        /// How many characters of `sungText` have been sung by `time` (fractional, for a smooth fill).
        func litCharacters(at time: Double) -> Double {
            var lit = 0.0
            for (i, w) in words.enumerated() {
                let gap = i < words.count - 1 ? 1.0 : 0
                if time >= w.end { lit += Double(w.text.count) + gap; continue }
                if time > w.start { lit += Double(w.text.count) * (time - w.start) / max(0.01, w.end - w.start) }
                break
            }
            return lit
        }
    }

    /// One sung word (or a run of syllables with no space between them).
    struct Word: Sendable, Equatable {
        let text: String
        let start: Double
        let end: Double

        /// How much of the word has been sung, 0…1.
        func fill(at time: Double) -> Double { min(1, max(0, (time - start) / max(0.01, end - start))) }
    }
    var lines: [Line]
    var plain: String?
    var isSynced: Bool { !lines.isEmpty }

    /// The line being sung at `time`.
    func activeIndex(at time: Double) -> Int? {
        guard isSynced else { return nil }
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}

/// Parses LRC: `[mm:ss.xx] text`, several stamps per line, an optional `[offset:+/-ms]`, and the word stamps of
/// enhanced LRC (`<mm:ss.xx>word`) when a file has them.
enum LRCParser {
    private struct Entry { let time: Double; let text: String; let stamped: [(Double, String)] }

    static func parse(_ lrc: String) -> [Lyrics.Line] {
        var offset = 0.0
        var entries: [Entry] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var line = Substring(raw)
            var stamps: [Double] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                if tag.lowercased().hasPrefix("offset:"), let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                } else if let t = time(tag) {
                    stamps.append(t)
                }
                line = line[line.index(after: close)...]
            }
            let (text, stamped) = wordStamps(String(line))
            // A repeated chorus ([00:10][01:30]) reuses its word stamps, moved along to each place it's sung.
            for t in stamps {
                let shift = t - (stamps.first ?? t)
                entries.append(Entry(time: t, text: text, stamped: stamped.map { ($0.0 + shift, $0.1) }))
            }
        }
        let sorted = entries.sorted { $0.time < $1.time }
        return sorted.enumerated().map { i, e in
            let start = max(0, e.time - offset)
            let next = i + 1 < sorted.count ? max(0, sorted[i + 1].time - offset) : nil
            let words = e.stamped.isEmpty ? estimate(e.text, start: start, end: next ?? start + 30)
                                           : stampedWords(e.stamped, offset: offset, end: next)
            let end = next ?? (words.last.map { $0.end + 1.5 } ?? start + 4)
            return Lyrics.Line(id: i, time: start, text: e.text, end: end, words: words)
        }
    }

    /// Takes the `<mm:ss.xx>` word stamps out of a line: the plain text, and each stamped piece with its time.
    private static func wordStamps(_ line: String) -> (String, [(Double, String)]) {
        guard line.contains("<") else { return (line.trimmingCharacters(in: .whitespaces), []) }
        var pieces: [(Double, String)] = []
        var plain = ""
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            let before = rest[..<open]
            plain += before
            if !pieces.isEmpty { pieces[pieces.count - 1].1 += before }
            if let t = time(rest[rest.index(after: open)..<close]) { pieces.append((t, "")) }
            rest = rest[rest.index(after: close)...]
        }
        plain += rest
        if !pieces.isEmpty { pieces[pieces.count - 1].1 += rest }
        return (plain.trimmingCharacters(in: .whitespaces), pieces)
    }

    /// Word stamps → words. Pieces with no space between them (syllables) join into one word.
    private static func stampedWords(_ pieces: [(Double, String)], offset: Double, end: Double?) -> [Lyrics.Word] {
        var words: [(text: String, start: Double, end: Double)] = []
        var afterSpace = true
        for (k, piece) in pieces.enumerated() {
            let start = max(0, piece.0 - offset)
            let stop = k + 1 < pieces.count ? max(start, pieces[k + 1].0 - offset) : max(start + 0.4, min(end ?? start + 1, start + 1.2))
            let raw = piece.1, text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { if !raw.isEmpty { afterSpace = true }; continue }
            if !afterSpace, raw.first?.isWhitespace != true, !words.isEmpty {
                words[words.count - 1].text += text
                words[words.count - 1].end = stop
            } else {
                words.append((text, start, stop))
            }
            afterSpace = raw.last?.isWhitespace ?? true
        }
        return words.map { Lyrics.Word(text: $0.text, start: $0.start, end: $0.end) }
    }

    /// No word stamps: spreads the words over the line by their length, at about the pace people sing (so a
    /// line followed by a long pause still fills at a natural speed).
    static func estimate(_ text: String, start: Double, end: Double) -> [Lyrics.Word] {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return [] }
        let weights = parts.map { Double($0.count) + 1.5 }
        let total = weights.reduce(0, +)
        let available = max(0.3, end - start)
        let sung = min(available * 0.9, max(0.8, total * 0.075))
        var t = start
        var words: [Lyrics.Word] = []
        for (part, weight) in zip(parts, weights) {
            let d = sung * weight / total
            words.append(Lyrics.Word(text: part, start: t, end: t + d))
            t += d
        }
        return words
    }

    /// "mm:ss.xx" or "mm:ss" → seconds.
    private static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        return m * 60 + s
    }
}

/// LRCLIB (free, no key): `/api/get` first, then `/api/search` picking the closest duration.
enum LRCLIB {
    private struct Record: Decodable {
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
        let instrumental: Bool?
    }

    struct Result: Sendable { let synced: String?; let plain: String? }

    static func fetch(title: String, artist: String, album: String, duration: Double) async -> Result? {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist),
                          URLQueryItem(name: "album_name", value: album), URLQueryItem(name: "duration", value: String(Int(duration.rounded())))]
        if let r: Record = await request(get.url), r.syncedLyrics != nil || r.plainLyrics != nil {
            return Result(synced: r.syncedLyrics, plain: r.plainLyrics)
        }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        guard let list: [Record] = await request(search.url), !list.isEmpty else { return nil }
        let best = list.filter { $0.syncedLyrics != nil || $0.plainLyrics != nil }
            .min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
        return best.map { Result(synced: $0.syncedLyrics, plain: $0.plainLyrics) }
    }

    private static func request<T: Decodable>(_ url: URL?) async -> T? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("LINER/1.0 (personal app)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        guard let result = try? await URLSession.shared.data(for: req),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: result.0)
    }
}
