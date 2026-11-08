import SwiftData
import SwiftUI

/// PINNED PLAYLISTS on the Playlists tab: a paged row of pinned playlist covers.
struct PinnedPlaylistsShelf: View {
    @Query(sort: \PinnedPlaylist.pinnedAt) private var pins: [PinnedPlaylist]
    @Environment(LibraryService.self) private var library

    var body: some View {
        let pinned = pins.compactMap { p in library.snapshot.playlists.first { $0.id == UInt64(bitPattern: p.playlistID) } }
        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Pinned Playlists").padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(pinned) { p in
                            NavigationLink(value: p) {
                                VStack(alignment: .leading, spacing: 6) {
                                    PlaylistCover(playlist: p).frame(width: 220)
                                    Text(p.name).font(.serif(18)).lineLimit(1)
                                    Text("\(p.songIDs.count) songs").linerLabel(size: 10)
                                }
                                .frame(width: 220)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { PlaylistActionsMenu(playlist: p) }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

/// Home shelves that later features fill (mixtapes). Mood playlists sit behind the sparkles button instead.
struct HomeShelves: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MixtapesShelf()
        }
    }
}
