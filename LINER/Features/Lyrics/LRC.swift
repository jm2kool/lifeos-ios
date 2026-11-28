import Foundation

/// Lyrics for one song: timed lines (synced), or plain text. Synced lines carry a time for every word, either
/// from the source (enhanced LRC) or estimated by `WordTiming`, for the sing-along fill.
struct Lyrics: Sendable, Equatable {
    /// One sung word (or a few syllables joined into one word), with when it starts and ends.
    struct Word: Sendable, Equatable {
        var text: String
        var start: Double
        var end: Double
        /// A space follows it (false inside a word, and between CJK characters).
        var space = true
        /// Sung as a background vocal: it was in (brackets).
        var isBackground = false
    }

    struct Line: Sendable, Equatable, Identifiable {
        let id: Int
        let time: Double
        let text: String
        /// When the singing of this line is over (worked out by `WordTiming`).
        var end: Double = 0
        var words: [Word] = []
        /// The whole line is a background vocal, like "(don't let go)".
        var isBackground = false
        /// Duet part: 0 for the lead, 1 for the second voice (set out on the right).
        var voice = 0
    }

    /// Where the word timings came from, shown as a small badge in the lyrics.
    enum Timing: String, Sendable { case word, estimated }

    var lines: [Line]
    var plain: String?
    var timing: Timing = .estimated
    var isSynced: Bool { !lines.isEmpty }

    /// The lead line being sung at `time` (background lines belong to the line before them).
    func activeIndex(at time: Double) -> Int? {
        guard isSynced else { return nil }
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        while let f = found, f > 0, lines[f].isBackground { found = f - 1 }
        return found
    }
}

/// Parses LRC: `[mm:ss.xx] text`, several stamps per line, an optional `[offset:+/-ms]`, and enhanced LRC's word
/// stamps (`[00:05.50]<00:05.50>Hello <00:06.00>world`). Duet tags (`v1:`, `v2:`, `M:`, `F:`, `D:`) and lines
/// that are all in brackets are noted too.
enum LRCParser {
    static func parse(_ lrc: String) -> [Lyrics.Line] {
        var offset = 0.0
        var entries: [(Double, String)] = []
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
            let text = line.trimmingCharacters(in: .whitespaces)
            for t in stamps { entries.append((t, text)) }
        }
        return entries.sorted { $0.0 < $1.0 }.enumerated().map { i, e in
            line(id: i, time: max(0, e.0 - offset), raw: e.1, offset: offset)
        }
    }

    /// Whether any line has word stamps of its own.
    static func hasWordStamps(_ lrc: String) -> Bool {
        lrc.range(of: #"<\d+:\d+(\.\d+)?>"#, options: .regularExpression) != nil
    }

    private static func line(id: Int, time: Double, raw: String, offset: Double) -> Lyrics.Line {
        var body = Substring(raw)
        var voice = 0
        if let tag = body.range(of: #"^(v\d|[MFD]):\s*"#, options: .regularExpression) {
            let name = body[tag].lowercased()
            voice = name.hasPrefix("v2") || name.hasPrefix("f") ? 1 : 0
            body = body[tag.upperBound...]
        }
        let words = stampedWords(body, offset: offset)
        let text = words.isEmpty ? String(body).trimmingCharacters(in: .whitespaces)
                                 : words.map { $0.text + ($0.space ? " " : "") }.joined().trimmingCharacters(in: .whitespaces)
        let isBackground = text.count > 2 && text.hasPrefix("(") && text.hasSuffix(")")
        return Lyrics.Line(id: id, time: time, text: text, words: words, isBackground: isBackground, voice: voice)
    }

    /// Words from `<mm:ss.xx>` stamps. Pieces without a space between them (syllables) join into one word.
    private static func stampedWords(_ body: Substring, offset: Double) -> [Lyrics.Word] {
        guard body.contains("<") else { return [] }
        var pieces: [(Double, String)] = []
        var rest = body
        var lastTime: Double?
        var pending = ""
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            pending += rest[rest.startIndex..<open]
            if let t = time(rest[rest.index(after: open)..<close]) {
                if let lt = lastTime, !pending.isEmpty { pieces.append((lt, pending)) }
                pending = ""
                lastTime = max(0, t - offset)
            } else {
                pending += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        pending += rest
        // The time after the last piece is its end; without one, the word gets a short default length.
        var closingTime: Double?
        if let lt = lastTime {
            if pending.trimmingCharacters(in: .whitespaces).isEmpty { closingTime = lt } else { pieces.append((lt, pending)) }
        }
        var words: [Lyrics.Word] = []
        var inBrackets = false
        for (k, piece) in pieces.enumerated() {
            let end = k + 1 < pieces.count ? pieces[k + 1].0 : (closingTime ?? piece.0 + 0.6)
            let trimmed = piece.1.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("(") { inBrackets = true }
            let joinsPrevious = !(piece.1.first?.isWhitespace ?? true) && !(words.last?.space ?? true)
            if joinsPrevious, var last = words.popLast() {
                last.text += trimmed
                last.end = max(last.end, end)
                last.space = piece.1.last?.isWhitespace ?? false
                words.append(last)
            } else {
                words.append(Lyrics.Word(text: trimmed, start: piece.0, end: max(end, piece.0 + 0.05),
                                         space: piece.1.last?.isWhitespace ?? false, isBackground: inBrackets))
            }
            if trimmed.hasSuffix(")") { inBrackets = false }
        }
        if !words.isEmpty { words[words.count - 1].space = false }
        return words
    }

    /// "mm:ss.xx" or "mm:ss" → seconds.
    private static func time(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        return m * 60 + s
    }
}

/// LRCLIB (free, no key): `/api/get` first, then `/api/search` picking the closest duration. When several
/// results are close, one with word stamps is preferred, so the sing-along can follow the real timing.
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
        let direct: Record? = await request(get.url)
        if let direct, let synced = direct.syncedLyrics, LRCParser.hasWordStamps(synced) {
            return Result(synced: synced, plain: direct.plainLyrics)
        }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        let list: [Record] = await request(search.url) ?? []
        let close = list.filter { $0.syncedLyrics != nil && abs(($0.duration ?? 0) - duration) <= 2 }
        if let worded = close.first(where: { LRCParser.hasWordStamps($0.syncedLyrics ?? "") }) {
            return Result(synced: worded.syncedLyrics, plain: worded.plainLyrics ?? direct?.plainLyrics)
        }
        if let direct, direct.syncedLyrics != nil || direct.plainLyrics != nil {
            return Result(synced: direct.syncedLyrics, plain: direct.plainLyrics)
        }
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
