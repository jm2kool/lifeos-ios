import Foundation
import SwiftData

/// The app's SwiftData container and small fetch-or-create helpers for notes.
@MainActor
final class Store {
    static let shared = Store()
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private init() {
        let schema = Schema(UserModels.all)
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            // A broken store must never stop the app opening; fall back to memory and say so in Settings.
            Store.openError = error.localizedDescription
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
    }

    static var openError: String?

    func save() { try? context.save() }

    // MARK: Songs

    func songNote(_ itemID: String) -> SongNote? {
        var d = FetchDescriptor<SongNote>(predicate: #Predicate { $0.itemID == itemID })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func songNoteOrNew(for item: QueueItem) -> SongNote {
        if let n = songNote(item.id) { return n }
        let n = SongNote(itemID: item.id, key: item.song?.key)
        context.insert(n)
        return n
    }

    /// Removes a note nobody wrote anything in (opened and closed).
    func dropIfEmpty(_ note: SongNote) {
        if note.isEmpty { context.delete(note) }
        save()
    }

    func allAlbumNotes() -> [AlbumNote] { (try? context.fetch(FetchDescriptor<AlbumNote>())) ?? [] }

    func allSongNotes() -> [SongNote] { (try? context.fetch(FetchDescriptor<SongNote>())) ?? [] }

    // MARK: Albums

    func albumNote(_ albumID: String) -> AlbumNote? {
        var d = FetchDescriptor<AlbumNote>(predicate: #Predicate { $0.albumID == albumID })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func albumNoteOrNew(_ albumID: String, key: AlbumKey?) -> AlbumNote {
        if let n = albumNote(albumID) { return n }
        let n = AlbumNote(albumID: albumID, key: key)
        context.insert(n)
        return n
    }

    // MARK: Re-matching after an iCloud re-sync

    /// Notes whose persistent ID vanished are matched again by store ID, then by title + artist + album + duration.
    func rematch(with snapshot: LibrarySnapshot) {
        let notes = allSongNotes().filter { $0.itemID.hasPrefix("lib-") }
        guard !notes.isEmpty, !snapshot.songs.isEmpty else { return }
        let byStore = Dictionary(snapshot.songs.filter { !$0.storeID.isEmpty }.map { ($0.storeID, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for note in notes {
            guard let key = note.key, snapshot.songs([key.persistentID]).isEmpty else { continue }
            let match = key.storeID.flatMap { byStore[$0] } ?? snapshot.songs.first { $0.key.looselyMatches(key) }
            if let match, songNote("lib-\(match.id)") == nil {
                note.itemID = "lib-\(match.id)"
                note.keyData = Coding.encode(match.key)
                changed = true
            }
        }
        if changed { save() }
    }
}
