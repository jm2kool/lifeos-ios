import Foundation
import SwiftData

/// Finds lyrics for a queue item: a mixtape's own LRC, the cache, or LRCLIB (then cached).
@MainActor
enum LyricsStore {
    /// `raw`: as the file has them, without your own timing corrections (for recalibrating).
    static func lyrics(for item: QueueItem, refresh: Bool = false, raw: Bool = false) async -> Lyrics? {
        let found = await fileLyrics(for: item, refresh: refresh)
        return raw ? found : found?.retimed(LyricTimings.shared.timing(for: item.id))
    }

    private static func fileLyrics(for item: QueueItem, refresh: Bool) async -> Lyrics? {
        if case .local(let t) = item {
            let lrc = TrackResolver.mixtapeTrack(t.id)?.lyricsLRC ?? t.lyricsLRC
            guard let lrc, !lrc.isEmpty else { return nil }
            let lines = LRCParser.parse(lrc)
            return Lyrics(lines: lines, plain: lines.isEmpty ? lrc : nil)
        }
        let id = item.id
        if !refresh, let cached = cache(id) {
            return make(cached.lrc, cached.plain)
        }
        guard UserDefaults.standard.string(forKey: "lyricsSource") != "off" else { return nil }
        let result = await LRCLIB.fetch(title: item.title, artist: item.artist, album: item.albumTitle, duration: item.duration)
        let context = Store.shared.context
        if let old = cache(id) { context.delete(old) }
        context.insert(LyricsCache(itemID: id, lrc: result?.synced, plain: result?.plain))
        Store.shared.save()
        return make(result?.synced, result?.plain)
    }

    private static func cache(_ id: String) -> LyricsCache? {
        var d = FetchDescriptor<LyricsCache>(predicate: #Predicate { $0.itemID == id })
        d.fetchLimit = 1
        return try? Store.shared.context.fetch(d).first
    }

    private static func make(_ lrc: String?, _ plain: String?) -> Lyrics? {
        let lines = lrc.map(LRCParser.parse) ?? []
        if lines.isEmpty && (plain ?? "").isEmpty { return nil }
        return Lyrics(lines: lines, plain: plain)
    }
}
