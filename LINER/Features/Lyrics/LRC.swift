import Foundation

/// Lyrics for one song: timed lines (synced), or plain text.
struct Lyrics: Sendable, Equatable {
    struct Line: Sendable, Equatable, Identifiable {
        let id: Int
        let time: Double
        let text: String
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

/// Parses LRC: `[mm:ss.xx] text`, several stamps per line, and an optional `[offset:+/-ms]`.
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
            Lyrics.Line(id: i, time: max(0, e.0 - offset), text: e.1)
        }
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
