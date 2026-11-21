import SwiftUI

/// Automix: how one song hands over to the next (Settings → Listening, or the queue).
enum Automix {
    enum Mode: String, CaseIterable, Identifiable {
        case off, crossfade
        var id: String { rawValue }
    }

    static var mode: Mode { Mode(rawValue: UserDefaults.standard.string(forKey: "automix.mode") ?? "") ?? .off }
    /// How long the handover takes, in seconds.
    static var seconds: Double {
        let v = UserDefaults.standard.double(forKey: "automix.seconds")
        return v > 0 ? v : 6
    }
}

/// A DJ mix's settings for one song in one playlist: where it starts and ends, how loud it is, a section to loop,
/// and how long it takes to hand over to the next song.
struct SongMix: Codable, Hashable, Sendable {
    var start: Double?
    var end: Double?
    /// −12 … +6 dB.
    var gainDB = 0.0
    /// Seconds of fade into the next song (nil follows Automix).
    var transition: Double?
    var loop: Loop?

    struct Loop: Codable, Hashable, Sendable {
        var start: Double
        var end: Double
        /// Extra times round (1 plays the section twice).
        var repeats = 1
    }

    var isEmpty: Bool { self == SongMix() }
    var gain: Float { Float(pow(10, gainDB / 20)) }

    /// The loop, if it makes sense for a song this long.
    func validLoop(duration: Double) -> Loop? {
        guard let loop, loop.repeats > 0, loop.end - loop.start >= 0.25, loop.start >= (start ?? 0),
              loop.end <= (end ?? duration) else { return nil }
        return loop
    }
}

/// DJ mixes, by playlist (or album, mixtape) and song, saved as one small JSON file.
@MainActor @Observable
final class MixStore {
    static let shared = MixStore()
    private(set) var mixes: [String: [String: SongMix]] = [:]
    private var file: URL { URL.applicationSupportDirectory.appending(path: "LINER/mixes.json") }

    private init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: [String: SongMix]].self, from: data) {
            mixes = saved
        }
    }

    func mix(_ context: String?, _ itemID: String) -> SongMix? {
        guard let context else { return nil }
        return mixes[context]?[itemID]
    }

    func update(_ context: String, _ itemID: String, _ change: (inout SongMix) -> Void) {
        var m = mixes[context]?[itemID] ?? SongMix()
        change(&m)
        var all = mixes[context] ?? [:]
        all[itemID] = m.isEmpty ? nil : m
        mixes[context] = all.isEmpty ? nil : all
        save()
    }

    func clear(_ context: String) { mixes[context] = nil; save() }

    func hasMix(_ context: String) -> Bool { !(mixes[context]?.isEmpty ?? true) }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(mixes) { try? data.write(to: file, options: .atomic) }
    }
}

extension EnvironmentValues {
    /// The DJ mix a page's songs play with ("playlist-…", "album-…", "mixtape-…").
    @Entry var mixContext: String? = nil
}
