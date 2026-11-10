import SwiftUI

/// The Library tab: Artists · Albums · Songs · Playlists, each searchable and sortable (SPEC §6.2). Mixtapes have their own tab.
/// Albums can show as a moving crate (always in Vinyl Mode); songs are always a plain list.
struct LibraryView: View {
    enum Section: String, CaseIterable, Identifiable {
        case artists = "Artists", albums = "Albums", songs = "Songs", playlists = "Playlists"
        var id: String { rawValue }
    }

    @Environment(LibraryService.self) private var library
    @Namespace private var zoom
    @AppStorage("library.section") private var section: Section = .albums
    @AppStorage("library.sort") private var sort: LibrarySort = .alphabetical
    @State private var query = ""
    @AppStorage("library.crate") private var crateLayout = false
    @AppStorage("vinylMode") private var vinylMode = false
    private var asCrate: Bool { crateLayout || vinylMode }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.top, 6)
                .id(section)   // a fresh list for each section, so switching is instant
            }
            .scrollDismissesKeyboard(.immediately)
            .demoScroll("library", to: 900, after: 2)
            // Outside the scroll view, so it's always there and always takes the tap.
            .safeAreaInset(edge: .top, spacing: 0) { sectionPicker }
            .background(Palette.background)
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Search \(section.rawValue.lowercased())")
            .toolbar { sortMenu }
            .refreshable { await library.refresh() }
            .libraryDestinations(zoom)
        }
    }

    private var sectionPicker: some View {
        Picker("Section", selection: Binding(get: { section }, set: { new in withAnimation(.liner) { section = new } })) {
            ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Palette.background.opacity(0.92))
        .sensoryFeedback(.selection, trigger: section)
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if section == .albums && !vinylMode {
                Button { withAnimation(.liner) { crateLayout.toggle() } } label: {
                    Label(asCrate ? "Grid" : "Crate", systemImage: asCrate ? "square.grid.2x2" : "record.circle")
                }
                .accessibilityLabel(asCrate ? "Show as a grid" : "Show as a crate")
            }
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
            if asCrate { CrateShelf(albums: list, namespace: zoom) } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
                ForEach(list) { album in
                    NavigationLink(value: album) { AlbumTile(album: album, namespace: zoom) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            }
        case .songs:
            let list = library.songs(sort).filter { matches($0.title, $0.artist, $0.albumTitle) }
            if list.isEmpty { empty("music.note", "No songs") }
            ForEach(list) { song in
                PlayableSongRow(song: song, list: list).padding(.horizontal, 16).padding(.vertical, 5)
            }
        case .playlists:
            let list = library.playlists(sort).filter { matches($0.name) }
            if query.isEmpty { PinnedPlaylistsShelf().padding(.bottom, 12) }
            SectionLabel("All Playlists").padding(.horizontal, 16).padding(.bottom, 4)
            if list.isEmpty { empty("music.note.list", "No playlists") }
            ForEach(list) { playlist in
                NavigationLink(value: playlist) { PlaylistRow(playlist: playlist) }.buttonStyle(.plain)
                    .contextMenu { PlaylistActionsMenu(playlist: playlist) }
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
    }

    private func empty(_ symbol: String, _ title: String) -> some View {
        EmptyStateView(symbol: symbol, title: query.isEmpty ? title : "No matches",
                       message: query.isEmpty ? "Add music in the Music app and pull down to refresh." : "Nothing matches “\(query)”.")
    }
}

#Preview { LibraryView().environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
