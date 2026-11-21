import SwiftUI

/// An artist (SPEC §6.3): their photo in full colour down most of the screen, melting into a page painted in the
/// photo's own colour (gently moving, like the Apple Card), stylised name, wide Play and Shuffle, Play/Shuffle, then a switch between their Page
/// (Apple Music's catalogue: top songs, albums, singles) and LINER. stats (your history with them, My Top
/// Songs, totals, your albums and songs). The title style is picked in Settings → Artist titles.
struct ArtistDetailView: View {
    enum Tab: String, CaseIterable, Identifiable { case page = "Page", stats = "Stats"; var id: String { rawValue } }

    let artist: Artist
    let namespace: Namespace.ID
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(PassportPresenter.self) private var passports
    /// How far the photo has scrolled away (0…1): the name moves into the top bar.
    @State private var scrolled = 0.0
    @State private var heroHeight: CGFloat = 600
    @State private var titleStyle: ArtistTitleStyle = .auto
    /// How bright the photo is where the title sits (0 dark … 1 bright).
    @State private var titleBackdrop = 0.0
    @AppStorage("artist.tab") private var tab: Tab = .page
    @State private var page: AppleCatalog.ArtistPage?
    @State private var loadingPage = true
    /// The page's colour: shades of the photo's main colour (or their covers' colours when there's no photo).
    @State private var colours: [ArtPalette.RGB] = []
    @State private var hasPhoto = true

    var body: some View {
        let albums = library.snapshot.albums(of: artist).sorted { $0.playCount > $1.playCount }
        let songs = library.snapshot.songs(of: artist).sorted { ($0.playCount, $0.lastPlayed ?? .distantPast) > ($1.playCount, $1.lastPlayed ?? .distantPast) }
        let genre = albums.first?.genre ?? songs.first?.genre ?? ""
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero(releases: albums.count, genre: genre)
                let playable = tab == .page && !(page?.topSongs.isEmpty ?? true) ? catalogSongs : songs
                transport(playable)
                Picker("Show", selection: $tab.animation(.liner)) {
                    ForEach(Tab.allCases) { t in Text(t == .stats ? "\(AppBrand.name) stats" : t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .sensoryFeedback(.selection, trigger: tab)
                if tab == .page {
                    ArtistCatalogPage(artist: artist, page: page, loading: loadingPage).transition(.opacity)
                } else {
                    Group {
                        ArtistHistoryCard(artist: artist, topSong: songs.first, topAlbum: albums.first).padding(.horizontal, 16)
                        if !songs.isEmpty { ArtistTopSongs(songs: Array(songs.prefix(10))).padding(.horizontal, 16) }
                        totals
                        albumsRow(albums)
                        songsList(songs)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 32)
        }
        .headerScrollProgress(headerHeight: heroHeight, progress: $scrolled)
        .artCanvas(colours)
        // The artist's colour is the accent on their page: buttons, the selected tab, tinted logos.
        .tint(accent ?? .white)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { titleStyle = ArtistTitleStyle.saved(for: artist.id) }
        .task(id: artist.id) {
            page = await AppleCatalog.artistPage(name: artist.name)
            loadingPage = false
            // No photo and none of their covers in your library: Apple Music's covers will do.
            if !hasPhoto && colours.isEmpty { await coverColours() }
        }
        // One back button of our own: the system one could show twice over the full-bleed photo after a zoom
        // transition. Swipe-back still works. Title styles live in Settings → Artist titles.
        .navigationBarBackButtonHidden(true)
        .keepsSwipeBack()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") { dismiss() }
            }
            ToolbarItem(placement: .principal) {
                ArtistTitleView(name: artist.name, artistID: artist.id, genre: "", size: 17, style: titleStyle, coverColor: accent ?? .white)
                    .frame(maxHeight: 30).opacity(scrolled).allowsHitTesting(false)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(LookStore.shared.logo(LookKey.artist(artist.name)) == nil ? "Add Logo" : "Edit Logo", systemImage: "signature") {
                    passports.look = .artist(artist)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareCardButton(make: {
                    .artist(artist, rank: library.stats.rank(of: artist), minutes: library.stats.minutes(of: artist), topSong: songsForShare.first)
                }, label: "Share")
            }
        }
    }

    private var songsForShare: [Song] {
        library.snapshot.songs(of: artist).sorted { $0.playCount > $1.playCount }
    }

    /// The Page's top songs, ready to queue (your copies where you have them).
    private var catalogSongs: [Song] {
        let mine = library.snapshot.songsByStoreID
        return (page?.topSongs ?? []).map { $0.song(in: library.snapshot, byStoreID: mine) }
    }

    /// The artist's photo in full colour, nearly the height of the screen, melting into the page painted in its
    /// own colour, with the name and release count over its foot.
    private func hero(releases: Int, genre: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            ArtistPortraitView(name: artist.name, fallbackAlbumID: artist.albumIDs.first, colour: true) { img in
                Task { await photoLoaded(img) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.68),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            // A little shade behind the title when the photo is bright there, so the name always reads.
            LinearGradient(stops: [.init(color: .clear, location: 0.55),
                                   .init(color: .black.opacity(0.25 * titleBackdrop), location: 0.8),
                                   .init(color: .black.opacity(0.15 * titleBackdrop), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                ArtistTitleView(name: artist.name, artistID: artist.id, genre: genre, style: titleStyle, skipPlaced: true,
                                coverColor: accent ?? .white).id(titleStyle)
                Text("Artist · \(releases) release\(releases == 1 ? "" : "s")").linerLabel(size: 12)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .containerRelativeFrame(.vertical) { h, _ in h * 0.78 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
        // Your own logo, where you placed it on the photo.
        .overlay {
            let key = LookKey.artist(artist.name), look = LookStore.shared.look(key)
            if let logo = LookStore.shared.logo(key), let placement = look.placement {
                PlacedLogo(image: logo, look: look, placement: placement, coverColor: accent ?? .white).opacity(1 - scrolled)
            }
        }
    }

    /// Paints the page in the photo's colour; with no photo, in the colours of their covers instead.
    private func photoLoaded(_ img: UIImage?) async {
        guard let img else { hasPhoto = false; await coverColours(); return }
        let look = await ArtworkAnalysis.look(for: img, key: "artist-\(artist.id)")
        withAnimation(.easeOut(duration: 0.3)) { titleBackdrop = look.secondaryBrightness }
        let tint = await ArtPalette.tint(of: img, key: "artist-photo-\(artist.id)")
        if !tint.isEmpty { colours = tint }
    }

    private func coverColours() async {
        let ids = library.snapshot.albums(of: artist).sorted { $0.playCount > $1.playCount }.prefix(4).map(\.id)
        var found = await ArtPalette.albums(Array(ids))
        if found.isEmpty, let page {
            let urls = ([page.latest].compactMap { $0 } + page.albums.prefix(3)).compactMap(\.artwork)
            found = await ArtPalette.web(urls, key: "artist-web-\(artist.id)")
        }
        if !found.isEmpty { colours = found }
    }

    /// The artist's colour, bright enough to draw with (nil until the photo or covers have loaded).
    private var accent: Color? { ArtPalette.accent(colours) }

    /// Play and Shuffle side by side as wide glass pills, tinted with the artist's colour.
    private func transport(_ playable: [Song]) -> some View {
        let tint = accent ?? .clear
        return GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                pill("Play", symbol: "play.fill", tint: tint) { player.play(songs: playable) }
                pill("Shuffle", symbol: "shuffle", tint: tint) { player.play(songs: playable, shuffled: true) }
            }
        }
        .padding(.horizontal, 20)
        .disabled(playable.isEmpty)
    }

    private func pill(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint.opacity(0.35)).interactive(), in: .capsule)
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatRow {
                StatTile("Total plays", value: artist.playCount)
                StatTile("Minutes", value: library.stats.minutes(of: artist), footnote: "Estimated")
            }
            Text("Minutes estimated from track durations × play counts").font(.caption2).foregroundStyle(Palette.label)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func albumsRow(_ albums: [Album]) -> some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Albums") { AlbumGridPage(title: artist.name, albums: albums, namespace: namespace) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) { AlbumTile(album: album, namespace: namespace).frame(width: 150) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder private func songsList(_ songs: [Song]) -> some View {
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Songs") { SongListPage(title: artist.name, songs: songs, ranked: true) }
                ForEach(songs.prefix(5)) { s in PlayableSongRow(song: s, list: songs).padding(.vertical, 5).padding(.horizontal, 16) }
            }
        }
    }
}

/// "My LINER." card: your rank for this artist and their most-played song and album.
struct ArtistHistoryCard: View {
    let artist: Artist
    let topSong: Song?
    let topAlbum: Album?
    @Environment(LibraryService.self) private var library

    var body: some View {
        Card {
            Text("My \(AppBrand.name)").font(.sectionTitle)
            if let rank = library.stats.rank(of: artist) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("#\(rank)").font(.serif(44))
                    Text("Most played artist in your library").linerLabel(size: 10)
                }
            } else {
                Text("You haven't played them yet").linerLabel(size: 10)
            }
            HStack(alignment: .top, spacing: 12) {
                if let s = topSong { tile("Most played song", albumID: s.albumID, title: s.title, plays: s.playCount) }
                if let a = topAlbum {
                    NavigationLink(value: a) { tile("Most played album", albumID: a.id, title: a.title, plays: a.playCount) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func tile(_ label: String, albumID: UInt64, title: String, plays: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).linerLabel(size: 9)
            ArtworkView(albumID: albumID, cornerRadius: 10).aspectRatio(1, contentMode: .fit)
            Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Text(plays.playsLabel).font(.caption).foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// My Top Songs: numbered, two columns.
struct ArtistTopSongs: View {
    let songs: [Song]
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Top Songs").font(.sectionTitle)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                    Button { player.play(songs: Array(songs[i...])) } label: {
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.serif(20)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 22)
                            ArtworkView(albumID: song.albumID, cornerRadius: 5).frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(song.playCount.playsLabel).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .modifier(SongContextMenu(song: song))
                }
            }
        }
    }
}

#Preview {
    @Previewable @Namespace var ns
    NavigationStack { ArtistDetailView(artist: PreviewData.snapshot.artists[0], namespace: ns) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
