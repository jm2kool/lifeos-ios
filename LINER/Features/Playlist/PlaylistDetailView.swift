import SwiftUI

/// A Music app playlist: cover mosaic, name and its songs.
struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(LibraryService.self) private var library

    var body: some View {
        let songs = library.snapshot.songs(playlist.songIDs)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlaylistCover(playlist: playlist).frame(maxWidth: 280).frame(maxWidth: .infinity)
                Text(playlist.name).font(.itemTitle)
                Text("Playlist · \(songs.count) songs · \(songs.reduce(0) { $0 + $1.duration }.minutesLabel)").linerLabel(size: 10)
                PlayShuffleRow(songs: songs)
                LazyVStack(spacing: 0) {
                    ForEach(songs) { song in
                        PlayableSongRow(song: song, list: songs).padding(.vertical, 6)
                    }
                }
                if songs.isEmpty {
                    EmptyStateView(symbol: "music.note.list", title: "Empty playlist", message: "Add songs to it in the Music app.")
                }
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { PlaylistActionsMenu(playlist: playlist) } label: { Label("More", systemImage: "ellipsis") }
            }
        }
    }
}

#Preview {
    NavigationStack { PlaylistDetailView(playlist: PreviewData.snapshot.playlists[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
