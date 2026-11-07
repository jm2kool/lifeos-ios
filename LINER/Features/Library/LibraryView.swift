import SwiftUI

/// The Library tab: Artists · Albums · Songs · Playlists · Mixtapes, each searchable and sortable (SPEC §6.2).
struct LibraryView: View {
    enum Section: String, CaseIterable, Identifiable {
        case artists = "Artists", albums = "Albums", songs = "Songs", playlists = "Playlists", mixtapes = "Mixtapes"
        var id: String { rawValue }
    }

    @Environment(LibraryService.self) private var library
    @Namespace private var zoom
    @AppStorage("library.section") private var section: Section = .albums
    @AppStorage("library.sort") private var sort: LibrarySort = .alphabetical
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16).padding(.bottom, 14)

                    content
                }
            }
            .background(Palette.background)
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Search \(section.rawValue.lowercased())")
            .toolbar { sortMenu }
            .refreshable { await library.refresh() }
            .libraryDestinations(zoom)
        }
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(LibrarySort.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort by \(sort.rawValue)")
        }
    }

    private func matches(_ fields: String...) -> Bool {
        query.isEmpty || fields.contains { $0.localizedStandardContains(query) }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .artists:
            let list = library.artists(sort).filter { matches($0.name) }
            if list.isEmpty { empty("person.2", "No artists") }
            ForEach(list) { artist in
                NavigationLink(value: artist) { ArtistRow(artist: artist) }.buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
        case .albums:
            let list = library.albums(sort).filter { matches($0.title, $0.artist) }
            if list.isEmpty { empty("square.stack", "No albums") }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
                ForEach(list) { album in
                    NavigationLink(value: album) { AlbumTile(album: album, namespace: zoom) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        case .songs:
            let list = library.songs(sort).filter { matches($0.title, $0.artist, $0.albumTitle) }
            if list.isEmpty { empty("music.note", "No songs") }
            ForEach(list) { song in
                PlayableSongRow(song: song, list: list).padding(.horizontal, 16).padding(.vertical, 5)
            }
        case .playlists:
            let list = library.playlists(sort).filter { matches($0.name) }
            if list.isEmpty { empty("music.note.list", "No playlists") }
            ForEach(list) { playlist in
                NavigationLink(value: playlist) { PlaylistRow(playlist: playlist) }.buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
        case .mixtapes:
            EmptyStateView(symbol: "recordingtape", title: "No mixtapes yet",
                           message: "Soon you'll be able to import your own audio files, like SoundCloud downloads, and keep them here as albums.")
        }
    }

    private func empty(_ symbol: String, _ title: String) -> some View {
        EmptyStateView(symbol: symbol, title: query.isEmpty ? title : "No matches",
                       message: query.isEmpty ? "Add music in the Music app and pull down to refresh." : "Nothing matches “\(query)”.")
    }
}

#Preview { LibraryView().environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark) }
