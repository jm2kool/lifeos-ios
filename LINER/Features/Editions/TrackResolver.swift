import Foundation
import SwiftData

/// Where imported audio lives: Application Support/LINER/Mixtapes (kept in backups).
enum MixtapeFiles {
    static var folder: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "LINER/Mixtapes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var covers: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "LINER/Covers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func url(_ fileName: String) -> URL { folder.appending(path: fileName) }

    /// The mixtape's cover written to disk (the lock screen and player read files, not SwiftData).
    static func coverURL(for mixtape: Mixtape) -> URL? {
        guard let data = mixtape.coverImage else { return nil }
        // The size in the name means a new cover gets a new file (and a new lock screen artwork ID).
        let url = covers.appending(path: "\(mixtape.id.uuidString)-\(data.count).jpg")
        if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url, options: .atomic) }
        return url
    }
}

/// Turns stored references (MediaKeys, mixtape track IDs) back into playable queue items.
@MainActor
enum TrackResolver {
    static func item(_ track: EditionTrack, snapshot: LibrarySnapshot) -> QueueItem? {
        switch track {
        case .library(let key): song(for: key, in: snapshot).map(QueueItem.library)
        case .mixtape(let id): mixtapeTrack(id).map { .local(local($0)) }
        }
    }

    static func items(_ tracks: [EditionTrack], snapshot: LibrarySnapshot) -> [QueueItem] {
        tracks.compactMap { item($0, snapshot: snapshot) }
    }

    /// persistentID → storeID → title + artist + album with duration ±2 s (SPEC §4).
    static func song(for key: MediaKey, in snapshot: LibrarySnapshot) -> Song? {
        if let s = snapshot.songs([key.persistentID]).first { return s }
        if let store = key.storeID, let s = snapshot.songs.first(where: { $0.storeID == store }) { return s }
        return snapshot.songs.first { $0.key.looselyMatches(key) }
    }

    static func mixtapeTrack(_ id: UUID) -> MixtapeTrack? {
        var d = FetchDescriptor<MixtapeTrack>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? Store.shared.context.fetch(d).first
    }

    static func local(_ t: MixtapeTrack) -> LocalTrack {
        LocalTrack(id: t.id, title: t.title, artist: t.artist, album: t.mixtape?.title ?? "Mixtape", duration: t.duration,
                   fileURL: MixtapeFiles.url(t.fileName), mixtapeID: t.mixtape?.id,
                   coverURL: t.mixtape.flatMap(MixtapeFiles.coverURL), lyricsLRC: t.lyricsLRC)
    }

    /// Stored reference for a queue item.
    static func reference(_ item: QueueItem) -> EditionTrack {
        switch item {
        case .library(let s): .library(s.key)
        case .local(let t): .mixtape(t.id)
        }
    }

    /// Resolves an item ID ("lib-…" / "loc-…") from mood playlists and rankings.
    static func item(id: String, snapshot: LibrarySnapshot) -> QueueItem? {
        if id.hasPrefix("lib-"), let pid = UInt64(id.dropFirst(4)) { return snapshot.songs([pid]).first.map(QueueItem.library) }
        if id.hasPrefix("loc-"), let uuid = UUID(uuidString: String(id.dropFirst(4))) { return mixtapeTrack(uuid).map { .local(local($0)) } }
        return nil
    }
}
