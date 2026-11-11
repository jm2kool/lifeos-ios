import SwiftData
import SwiftUI

extension Store {
    func isPinned(albumID: String) -> Bool { albumNote(albumID)?.pinned ?? false }

    func togglePin(albumID: String, key: AlbumKey?) {
        let note = albumNoteOrNew(albumID, key: key)
        note.pinned.toggle()
        note.pinnedAt = note.pinned ? .now : nil
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
        if pinned {
            Menu("Pinned Album Appearance", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                ForEach(PinAppearance.allCases, id: \.self) { a in
                    Button(a.label) { Store.shared.setAppearance(a, albumID: id, key: album.key) }
                }
            }
        }
        Button("Album Passport", systemImage: "text.book.closed") { passports.album = .library(album, snapshot: library.snapshot) }
        Menu("Cover", systemImage: "photo.on.rectangle") {
            Button("Choose Cover Photo", systemImage: "photo") { passports.cover = CoverRequest(album: album, motion: false) }
            Button("Choose Motion Cover", systemImage: "play.rectangle") { passports.cover = CoverRequest(album: album, motion: true) }
            if CoverOverrides.shared.image(album.id) != nil || Store.shared.albumNote(id)?.motionCoverFile != nil {
                Button("Use Original Artwork", systemImage: "arrow.uturn.backward", role: .destructive) { CoverSaver.reset(album) }
            }
        }
        AlbumLogoMenu(album: album)
        Button("Manage Editions", systemImage: "square.stack.3d.up") { passports.editions = .library(album, snapshot: library.snapshot) }
        Button(album.editionIDs.count > 1 ? "Group or Separate Versions" : "Group Versions", systemImage: "square.on.square") {
            passports.grouping = album
        }
        Button("Arrange Vinyl Sides", systemImage: "square.split.2x1") { passports.sides = .album(album, library.snapshot) }
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
