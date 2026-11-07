import SwiftUI

/// The Search tab: artists, albums and songs from your library as you type.
struct SearchView: View {
    @Environment(LibraryService.self) private var library
    @Namespace private var zoom
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let results = library.search(query)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if query.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "Search your library", message: "Artists, albums and songs.")
                    } else if results.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No matches", message: "Nothing in your library matches “\(query)”.")
                    }
                    if !results.artists.isEmpty {
                        SectionLabel("Artists")
                        ForEach(results.artists) { a in NavigationLink(value: a) { ArtistRow(artist: a) }.buttonStyle(.plain) }
                    }
                    if !results.albums.isEmpty {
                        SectionLabel("Albums")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(results.albums) { album in
                                    NavigationLink(value: album) { AlbumTile(album: album, namespace: zoom).frame(width: 140) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if !results.songs.isEmpty {
                        SectionLabel("Songs")
                        ForEach(results.songs) { song in PlayableSongRow(song: song, list: results.songs) }
                    }
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Artists, albums, songs")
            .libraryDestinations(zoom)
        }
    }
}

#Preview { SearchView().environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark) }
