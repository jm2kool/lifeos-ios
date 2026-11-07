import Foundation
import SwiftData

/// One recap (SPEC §6.12): minutes, top 5s, top genre and moods, discoveries, most-replayed day, song of the period.
struct Recap: Sendable {
    struct Ranked: Sendable, Identifiable { let id: String; let name: String; let detail: String; let plays: Double; let albumID: UInt64? }

    let period: RecapPeriod
    var minutes = 0
    var previousMinutes = 0
    var plays = 0
    var topSongs: [Ranked] = []
    var topArtists: [Ranked] = []
    var topAlbums: [Ranked] = []
    var topGenre: String?
    var topMoods: [String] = []
    var discoveries: [Ranked] = []
    var busiestDay: (date: Date, plays: Int)?

    var song: Ranked? { topSongs.first }
    var isEmpty: Bool { plays == 0 }

    /// Change in minutes against the previous period, as a whole percentage.
    var change: Int? {
        guard previousMinutes > 0 else { return nil }
        return Int(((Double(minutes) - Double(previousMinutes)) / Double(previousMinutes) * 100).rounded())
    }

    static func make(_ period: RecapPeriod, history h: PlayHistory, moods: [String: [String]]) -> Recap {
        var r = Recap(period: period)
        let plays = h.plays(in: period.range)
        func minutes(_ p: [String: Double]) -> Int { Int(p.reduce(0) { $0 + $1.value * (h.info[$1.key]?.duration ?? 0) } / 60) }
        r.minutes = minutes(plays)
        r.previousMinutes = minutes(h.plays(in: period.previous.range))
        r.plays = Int(plays.values.reduce(0, +).rounded())

        r.topSongs = plays.sorted { $0.value > $1.value }.prefix(5).compactMap { id, n in
            h.info[id].map { Ranked(id: id, name: $0.title, detail: $0.artist, plays: n, albumID: $0.albumID) }
        }
        var artists: [String: Double] = [:], albums: [String: (Double, PlayHistory.Info)] = [:], genres: [String: Double] = [:], moodCount: [String: Double] = [:]
        for (id, n) in plays {
            guard let i = h.info[id] else { continue }
            artists[i.artist, default: 0] += n
            albums[i.albumKey] = ((albums[i.albumKey]?.0 ?? 0) + n, i)
            if !i.genre.isEmpty { genres[i.genre, default: 0] += n }
            for m in moods[id] ?? [] { moodCount[m, default: 0] += n }
        }
        r.topArtists = artists.sorted { $0.value > $1.value }.prefix(5).map { Ranked(id: $0.key, name: $0.key, detail: "", plays: $0.value, albumID: nil) }
        r.topAlbums = albums.sorted { $0.value.0 > $1.value.0 }.prefix(5).map {
            Ranked(id: $0.key, name: $0.value.1.album, detail: $0.value.1.artist, plays: $0.value.0, albumID: $0.value.1.albumID)
        }
        r.topGenre = genres.max { $0.value < $1.value }?.key
        r.topMoods = moodCount.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        // Discoveries: first played this period (not counting the first day of recording, which is the baseline).
        let start = h.baseline.map { Calendar.current.startOfDay(for: $0).addingTimeInterval(86_400) } ?? .distantPast
        r.discoveries = h.firstPlayed.filter { period.range.contains($0.value) && $0.value >= start }
            .compactMap { id, _ in h.info[id].map { Ranked(id: id, name: $0.title, detail: $0.artist, plays: plays[id] ?? 0, albumID: $0.albumID) } }
            .sorted { $0.plays > $1.plays }
        if let best = h.days.filter({ period.range.contains($0.key) }).max(by: { $0.value.values.reduce(0, +) < $1.value.values.reduce(0, +) }) {
            r.busiestDay = (best.key, Int(best.value.values.reduce(0, +).rounded()))
        }
        return r
    }
}

/// Loads snapshots and play events from SwiftData and builds the history off the main thread.
@MainActor
enum RecapLoader {
    static func history(library: LibraryService) async -> PlayHistory {
        let context = Store.shared.context
        let snaps = ((try? context.fetch(FetchDescriptor<PlaySnapshot>())) ?? []).map {
            PlayHistory.Snap(pid: UInt64(bitPattern: $0.persistentID), date: $0.date, count: $0.playCount)
        }
        let events = ((try? context.fetch(FetchDescriptor<PlayEvent>())) ?? []).map {
            PlayHistory.Event(itemID: $0.itemID, pid: $0.persistentID.map { UInt64(bitPattern: $0) }, date: $0.startedAt, completed: $0.completed,
                              info: .init(title: $0.title, artist: $0.artist, album: $0.album, albumKey: $0.albumKey, genre: $0.genre,
                                          duration: $0.duration, albumID: $0.albumKey.hasPrefix("album-") ? UInt64($0.albumKey.dropFirst(6)) : nil))
        }
        let songs = library.snapshot
        let baseline = SnapshotService.shared.baselineDate
        return await build(snaps, events, songs, baseline)
    }

    @concurrent
    private static func build(_ s: [PlayHistory.Snap], _ e: [PlayHistory.Event], _ songs: LibrarySnapshot, _ b: Date?) async -> PlayHistory {
        PlayHistory.build(snaps: s, events: e, songs: songs, baseline: b)
    }

    static func moods() -> [String: [String]] {
        Dictionary(Store.shared.allSongNotes().filter { !$0.moods.isEmpty }.map { ($0.itemID, $0.moods) }, uniquingKeysWith: { a, _ in a })
    }
}
