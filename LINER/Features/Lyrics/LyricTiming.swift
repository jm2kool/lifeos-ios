import Foundation
import Observation

/// Your corrections to one song's lyric timings: the whole song moved earlier or later, and the lines you tapped
/// in yourself. Lines you didn't tap are carried along between the ones you did, so two taps far apart also fix
/// lyrics that drift (run too fast or too slow).
struct LyricTiming: Codable, Equatable, Sendable {
    /// A line that was at `from` in the lyrics file and is sung at `to`.
    struct Anchor: Codable, Equatable, Sendable { var from: Double; var to: Double }

    /// Seconds added to every line (minus: earlier).
    var shift = 0.0
    var anchors: [Anchor] = []

    var isEmpty: Bool { shift == 0 && anchors.isEmpty }

    /// When something at `time` in the lyrics file is really sung.
    func map(_ time: Double) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return max(0, time + shift) }
        var out: Double
        if time <= first.from { out = time + (first.to - first.from) }
        else if time >= last.from { out = time + (last.to - last.from) }
        else {
            out = time
            for (a, b) in zip(anchors, anchors.dropFirst()) where time >= a.from && time <= b.from {
                out = a.to + (b.to - a.to) * (time - a.from) / max(0.001, b.from - a.from)
                break
            }
        }
        return max(0, out + shift)
    }

    func isAnchored(_ from: Double) -> Bool { anchors.contains { abs($0.from - from) < 0.005 } }

    /// The line at `from` is sung at `to` (a time in the song, as you hear it). Taps that would put lines out of
    /// order replace the ones they disagree with.
    mutating func anchor(from: Double, to: Double) {
        let to = max(0, to - shift)
        anchors.removeAll { abs($0.from - from) < 0.005 || ($0.from < from && $0.to >= to) || ($0.from > from && $0.to <= to) }
        anchors.append(Anchor(from: from, to: to))
        anchors.sort { $0.from < $1.from }
    }
}

extension Lyrics {
    /// The same lyrics with your corrections applied to every line and word.
    func retimed(_ timing: LyricTiming) -> Lyrics {
        guard !timing.isEmpty else { return self }
        var out = self
        out.lines = lines.map { line in
            var l = Line(id: line.id, time: timing.map(line.time), text: line.text)
            l.end = max(l.time, timing.map(line.end))
            l.words = line.words.map { Word(text: $0.text, start: timing.map($0.start), end: timing.map($0.end)) }
            return l
        }
        return out
    }
}

/// Everyone's corrections, by song, kept in a small file. `version` changes with every correction, so anything
/// showing lyrics can load them again.
@MainActor @Observable
final class LyricTimings {
    static let shared = LyricTimings()
    private(set) var version = 0
    @ObservationIgnored private var all: [String: LyricTiming] = [:]

    private static var file: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "LINER", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "lyricTimings.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode([String: LyricTiming].self, from: data) {
            all = saved
        }
    }

    func timing(for itemID: String) -> LyricTiming { all[itemID] ?? LyricTiming() }

    func set(_ timing: LyricTiming, for itemID: String) {
        all[itemID] = timing.isEmpty ? nil : timing
        version += 1
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: Self.file, options: .atomic) }
    }
}
