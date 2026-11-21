import SwiftData
import SwiftUI

extension Store {
    func isPinned(albumID: String) -> Bool { albumNote(albumID)?.pinned ?? false }

    func togglePin(albumID: String, key: AlbumKey?) {
        let note = albumNoteOrNew(albumID, key: key)
        note.pinned.toggle()
        note.pinnedAt = note.pinned ? .now : nil
        // Albums pin as their cover with their logo; the artist portrait is a choice in the menu.
        if note.pinned { note.pinnedAppearance = .albumArtwork }
        save()
    }

    func setAppearance(_ a: PinAppearance, albumID: String, key: AlbumKey?) {
        albumNoteOrNew(albumID, key: key).pinnedAppearance = a
        save()
    }

    func pinnedPlaylist(_ id: UInt64) -> PinnedPlaylist? {
        let raw = Int64(bitPattern: id)
        var d = FetchDescriptor<PinnedPlaylist>(predicate: #Predicate { $0.playlistID == raw })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func togglePin(playlist id: UInt64) {
        if let p = pinnedPlaylist(id) { context.delete(p) } else { context.insert(PinnedPlaylist(playlistID: id)) }
        save()
    }
}

/// Long-press / ••• actions for an album: pin, pinned appearance, passport, editions.
struct AlbumActionsMenu: View {
    let album: Album
    @Environment(PassportPresenter.self) private var passports
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player

    private var id: String { "album-\(album.id)" }

    var body: some View {
        let pinned = Store.shared.isPinned(albumID: id)
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            player.playNext(library.snapshot.songs(album.songIDs).map(QueueItem.library))
        }
        Button(pinned ? "Unpin" : "Pin to Home", systemImage: pinned ? "pin.slash" : "pin") {
            Store.shared.togglePin(albumID: id, key: album.key)
        }
        Button("Album Passport", systemImage: "text.book.closed") { passports.album = .library(album, snapshot: library.snapshot) }
        // Logo, font, cover layout, cover, editions, text size, title and the Home pin's look all live in Customise Album.
        Button("Customise Album", systemImage: "slider.horizontal.3") { passports.customise = album }
    }
}

/// Long-press actions for a playlist.
struct PlaylistActionsMenu: View {
    let playlist: Playlist
    var body: some View {
        let pinned = Store.shared.pinnedPlaylist(playlist.id) != nil
        Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") { Store.shared.togglePin(playlist: playlist.id) }
        if pinned, let p = Store.shared.pinnedPlaylist(playlist.id) {
            Menu("Pinned Appearance", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                ForEach(PinAppearance.allCases, id: \.self) { a in
                    Button(a == .artistPortrait ? "Top Artist Portrait" : "Playlist Artwork") { p.appearanceRaw = a.rawValue; Store.shared.save() }
                }
            }
        }
    }
}
