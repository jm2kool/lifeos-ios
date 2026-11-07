import SwiftUI

/// "My LINER." (SPEC §6.11): all-time totals, top artists, albums and songs with See All, and extras —
/// with Recaps one tap away at the top.
struct MyStatsView: View {
    enum Page: String, CaseIterable, Identifiable { case overview = "Overview", recaps = "Recaps"; var id: String { rawValue } }

    @Environment(LibraryService.self) private var library
    @Namespace private var zoom
    @AppStorage("stats.page") private var page: Page = .overview

    var body: some View {
        let stats = library.stats
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My \(AppBrand.name)").font(.serif(44))
                        Text(page == .recaps ? "Your listening, period by period" : AppBrand.tagline).linerLabel()
                    }
                    .padding(.horizontal, 16)

                    Picker("Page", selection: $page.animation(.liner)) {
                        ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 16)

                    if page == .recaps { RecapsView() } else { overview(stats) }
                }
                .padding(.bottom, 32)
            }
            .background(Palette.background)
            .refreshable { await library.refresh() }
            .libraryDestinations(zoom)
        }
    }

    @ViewBuilder private func overview(_ stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StatRow {
                StatTile("Total plays", value: stats.totalPlays)
                StatTile("Minutes", value: stats.totalMinutes, footnote: "Estimated")
            }
            Text("Minutes estimated from track durations × play counts").font(.caption2).foregroundStyle(Palette.label)
        }
        .padding(.horizontal, 16)

        if stats.totalPlays == 0 {
            EmptyStateView(symbol: "chart.bar", title: "No plays yet", message: "Play some music and your history builds up here.")
        } else {
            topArtists(stats.artists)
            topAlbums(stats.albums)
            topSongs(stats.songs)
        }
        PersonalStatsSections()
        libraryCard
    }

    private func topArtists(_ artists: [Artist]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Top Artists") { ArtistListPage(title: "Top Artists", artists: Array(artists.prefix(200))) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(artists.prefix(10).enumerated()), id: \.element.id) { i, a in
                        NavigationLink(value: a) {
                            VStack(spacing: 8) {
                                ArtistPortraitView(name: a.name, fallbackAlbumID: a.albumIDs.first)
                                    .frame(width: 120, height: 120).clipShape(Circle())
                                    .overlay(alignment: .topLeading) { RankBadge(rank: i + 1) }
                                Text(a.name).font(.serif(15)).lineLimit(1)
                                Text(a.playCount.playsLabel).font(.caption2).foregroundStyle(Palette.secondary)
                            }
                            .frame(width: 124)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func topAlbums(_ albums: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Top Albums") { AlbumGridPage(title: "Top Albums", albums: Array(albums.prefix(200)), namespace: zoom, ranked: true) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(albums.prefix(10).enumerated()), id: \.element.id) { i, album in
                        NavigationLink(value: album) {
                            AlbumTile(album: album, namespace: zoom, showPlays: true).frame(width: 150)
                                .overlay(alignment: .topLeading) { RankBadge(rank: i + 1).padding(8) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func topSongs(_ songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Top Songs") { SongListPage(title: "Top Songs", songs: Array(songs.prefix(200)), ranked: true) }
            ForEach(Array(songs.prefix(10).enumerated()), id: \.element.id) { i, s in
                PlayableSongRow(song: s, list: Array(songs.prefix(200)), number: i + 1).padding(.vertical, 5).padding(.horizontal, 16)
            }
        }
    }

    private var libraryCard: some View {
        let snap = library.snapshot
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your Library").font(.sectionTitle)
            StatRow {
                StatTile("Songs", value: snap.songs.count)
                StatTile("Albums", value: snap.albums.count)
                StatTile("Artists", value: snap.artists.count)
            }
            let hours = Int(snap.songs.reduce(0) { $0 + $1.duration } / 3600)
            Text("\(hours.grouped) hours of music · \(snap.playlists.count) playlists").font(.footnote).foregroundStyle(Palette.label)
        }
        .padding(.horizontal, 16)
    }
}


#Preview { MyStatsView().environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark) }
