import SwiftData
import SwiftUI

/// The Search tab: the whole of Apple Music, or (with the switch) only your library, as you type.
struct SearchView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case appleMusic = "Apple Music", library = "Your Library"
        var id: String { rawValue }
    }

    @Environment(LibraryService.self) private var library
    @Namespace private var zoom
    @State private var query = ""
    @AppStorage("search.scope") private var scope: Scope = .appleMusic
    @State private var catalog = AppleCatalog.SearchResults()
    @State private var searching = false
    @Query(sort: \Mixtape.title) private var mixtapes: [Mixtape]

    var body: some View {
        NavigationStack {
            let results = library.search(query)
            ScrollView {
                Picker("Search in", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8)
                if scope == .appleMusic {
                    if query.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "Search Apple Music", message: "Any artist, album or song — play it, queue it or add it to your library.")
                            .padding(16)
                    } else {
                        CatalogSearchResults(results: catalog, query: query, loading: searching).padding(16)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if query.isEmpty {
                            EmptyStateView(symbol: "magnifyingglass", title: "Search your library", message: "Artists, albums and songs.")
                        } else if results.isEmpty && !mixtapes.contains(where: { $0.title.localizedStandardContains(query) }) {
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
                        let tapes = query.isEmpty ? [] : mixtapes.filter { $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query) }
                        if !tapes.isEmpty {
                            SectionLabel("Mixtapes")
                            ForEach(tapes) { m in
                                NavigationLink(value: m) {
                                    HStack(spacing: 12) {
                                        MixtapeCover(mixtape: m, cornerRadius: 6).frame(width: 46)
                                        VStack(alignment: .leading) { Text(m.title); Text(m.artist).font(.caption).foregroundStyle(Palette.secondary) }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !results.songs.isEmpty {
                            SectionLabel("Songs")
                            ForEach(results.songs) { song in PlayableSongRow(song: song, list: results.songs) }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Palette.background)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: scope == .appleMusic ? "Apple Music" : "Your library")
            .task(id: "\(scope.rawValue)|\(query)") {
                guard scope == .appleMusic else { return }
                let text = query
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { catalog = .init(); searching = false; return }
                searching = true
                // Wait for a pause in typing before asking Apple.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let found = await AppleCatalog.search(text)
                guard !Task.isCancelled else { return }
                catalog = found
                searching = false
            }
            .libraryDestinations(zoom)
        }
    }
}

#Preview { SearchView().environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
