import SwiftUI

/// Album page pieces that later phases fill in (motion covers, editions, passports, pins).
@MainActor
enum AlbumExtras {
    /// The tracks to show and play: the original album for now.
    static func tracks(for album: Album, library: LibraryService) -> [Song] { library.snapshot.songs(album.songIDs) }

    @ViewBuilder static func header(album: Album) -> some View {
        ArtworkView(albumID: album.id, cornerRadius: 0)
    }

    @ViewBuilder static func editionSwitcher(album: Album) -> some View { EmptyView() }

    @ViewBuilder static func passportButton(album: Album) -> some View { EmptyView() }

    @ViewBuilder static func moreMenu(album: Album) -> some View { EmptyView() }
}
