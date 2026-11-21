import SwiftUI

/// A Music app playlist: cover mosaic, name and its songs, on a page painted with the colours of its covers.
struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(LibraryService.self) private var library
    @State private var colours: [ArtPalette.RGB] = []
    @State private var djMix = false

    private var mixKey: String { "playlist-\(playlist.id)" }
    @AppStorage(AlbumText.titleKey) private var titleScale = 1.0

    var body: some View {
        let songs = library.snapshot.songs(playlist.songIDs)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlaylistCover(playlist: playlist).frame(maxWidth: 280).frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                Text(playlist.name).font(.serif(30 * titleScale))
                Text("Playlist · \(songs.count) songs · \(songs.reduce(0) { $0 + $1.duration }.minutesLabel)").linerLabel(size: 10)
                PlayShuffleRow(songs: songs)
                LazyVStack(spacing: 0) {
                    ForEach(songs) { song in
                        PlayableSongRow(song: song, list: songs).padding(.vertical, 6)
                    }
                }
                .albumTextSizes()
                if songs.isEmpty {
                    EmptyStateView(symbol: "music.note.list", title: "Empty playlist", message: "Add songs to it in the Music app.")
                }
            }
            .padding(16)
        }
        .environment(\.mixContext, mixKey)
        .artCanvas(colours)
        .task(id: playlist.coverAlbumIDs) {
            colours = await ArtPalette.albums(Array(playlist.coverAlbumIDs.prefix(4)))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    PlaylistActionsMenu(playlist: playlist)
                    Button(MixStore.shared.hasMix(mixKey) ? "Edit DJ Mix" : "DJ Mix", systemImage: "dial.medium") { djMix = true }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        .sheet(isPresented: $djMix) {
            MixEditorView(context: mixKey, title: playlist.name, items: songs.map(QueueItem.library))
        }
    }
}

#Preview {
    NavigationStack { PlaylistDetailView(playlist: PreviewData.snapshot.playlists[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
