import Foundation

/// Gives every synced line an end and every word a time, for the sing-along fill. Lines that came with word
/// stamps keep them. The rest are estimated: a line's time is shared out by syllables (little words like "the"
/// are sung quicker), with a short lead-in and extra time on the last word, which singers tend to hold.
enum WordTiming {
    /// Little words that are usually sung quickly.
    private static let quick: Set<String> = ["a", "an", "the", "and", "to", "of", "in", "on", "at", "it", "i", "i'm",
                                             "you", "me", "my", "is", "be", "we", "so", "but", "or", "for", "this", "that", "your"]

    static func apply(_ lyrics: Lyrics, duration: Double) -> Lyrics {
        guard lyrics.isSynced else { return lyrics }
        var out = lyrics
        let stamped = lyrics.lines.contains { !$0.words.isEmpty }
        out.timing = stamped ? .word : .estimated
        let lines = lyrics.lines
        for i in lines.indices {
            var line = lines[i]
            // The next line that isn't a background vocal sung over this one.
            let next = lines[(i + 1)...].first { !$0.isBackground || line.isBackground }?.time
                ?? (duration > line.time ? duration : line.time + 8)
            if let last = line.words.last {
                line.end = max(last.end, line.time + 0.2)
            } else {
                let syllables = max(1, words(in: line.text).reduce(0) { $0 + syllableCount($1.text) })
                // About four syllables a second plus room for the held end, never into the next line.
                let sung = Double(syllables) * 0.3 + 1.1
                line.end = max(line.time + 0.4, min(next - 0.08, line.time + sung))
                line.words = estimate(line)
            }
            out.lines[i] = line
        }
        return out
    }

    /// Shares a line's time out among its words.
    static func estimate(_ line: Lyrics.Line) -> [Lyrics.Word] {
        var list = words(in: line.text)
        guard !list.isEmpty else { return [] }
        let lead = 0.06
        let span = max(0.3, line.end - line.time - lead)
        let weights = list.enumerated().map { k, w -> Double in
            var weight = Double(syllableCount(w.text)) + 0.35
            if quick.contains(w.text.lowercased().trimmingCharacters(in: .punctuationCharacters)) { weight *= 0.6 }
            if k == list.count - 1 { weight += 1.0 }
            if w.text.last.map({ ",;:".contains($0) }) == true { weight += 0.3 }   // a breath after a comma
            return weight
        }
        let total = weights.reduce(0, +)
        var cursor = line.time + lead
        for k in list.indices {
            let d = span * weights[k] / total
            list[k].start = cursor
            list[k].end = cursor + d
            cursor += d
        }
        return list
    }

    /// Splits a line into words; CJK characters count as words of their own (with no space between them).
    static func words(in text: String) -> [Lyrics.Word] {
        var result: [Lyrics.Word] = []
        var inBrackets = false
        for token in text.split(separator: " ", omittingEmptySubsequences: true) {
            if token.hasPrefix("(") { inBrackets = true }
            if token.unicodeScalars.contains(where: isCJK) {
                var run = ""
                for ch in token {
                    if ch.unicodeScalars.contains(where: isCJK) {
                        if !run.isEmpty { result.append(Lyrics.Word(text: run, start: 0, end: 0, space: false, isBackground: inBrackets)); run = "" }
                        result.append(Lyrics.Word(text: String(ch), start: 0, end: 0, space: false, isBackground: inBrackets))
                    } else {
                        run.append(ch)
                    }
                }
                if !run.isEmpty { result.append(Lyrics.Word(text: run, start: 0, end: 0, space: false, isBackground: inBrackets)) }
                if !result.isEmpty { result[result.count - 1].space = true }
            } else {
                result.append(Lyrics.Word(text: String(token), start: 0, end: 0, space: true, isBackground: inBrackets))
            }
            if token.hasSuffix(")") { inBrackets = false }
        }
        if !result.isEmpty { result[result.count - 1].space = false }
        return result
    }

    /// Rough syllable count: groups of vowels, less a silent final "e". Non-Latin words count by length.
    static func syllableCount(_ word: String) -> Int {
        let letters = word.lowercased().filter(\.isLetter)
        guard !letters.isEmpty else { return 1 }
        if letters.unicodeScalars.contains(where: { $0.value > 0x024F }) {
            return letters.unicodeScalars.contains(where: isCJK) ? 1 : max(1, letters.count / 3)
        }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y", "à", "á", "â", "è", "é", "ê", "ì", "í", "ò", "ó", "ô", "ù", "ú", "ü"]
        var count = 0, previousVowel = false
        for ch in letters {
            let v = vowels.contains(ch)
            if v && !previousVowel { count += 1 }
            previousVowel = v
        }
        if letters.hasSuffix("e") && !letters.hasSuffix("le") && count > 1 { count -= 1 }
        return max(1, count)
    }

    private static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: true
        default: false
        }
    }
}

/// Your nudge for a song whose lyrics run early or late, in seconds (saved per song).
enum LyricsNudge {
    static func offset(_ itemID: String) -> Double { UserDefaults.standard.double(forKey: "lyricsNudge.\(itemID)") }
    static func set(_ value: Double, for itemID: String) {
        UserDefaults.standard.set((value * 10).rounded() / 10, forKey: "lyricsNudge.\(itemID)")
    }
}
