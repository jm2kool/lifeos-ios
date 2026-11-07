import SwiftUI

/// An artist (SPEC §6.3): black-and-white portrait, serif name, Play/Shuffle, your history with them,
/// My Top Songs, totals, albums and songs.
struct ArtistDetailView: View {
    let artist: Artist
    let namespace: Namespace.ID
    @Environment(LibraryService.self) private var library

    var body: some View {
        let albums = library.snapshot.albums(of: artist).sorted { $0.playCount > $1.playCount }
        let songs = library.snapshot.songs(of: artist).sorted { ($0.playCount, $0.lastPlayed ?? .distantPast) > ($1.playCount, $1.lastPlayed ?? .distantPast) }
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero(releases: albums.count)
                PlayShuffleRow(songs: songs).padding(.horizontal, 16)
                ArtistHistoryCard(artist: artist, topSong: songs.first, topAlbum: albums.first).padding(.horizontal, 16)
                if !songs.isEmpty { ArtistTopSongs(songs: Array(songs.prefix(10))).padding(.horizontal, 16) }
                totals
                albumsRow(albums)
                songsList(songs)
            }
            .padding(.bottom, 32)
        }
        .background(Palette.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(releases: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            ArtistPortraitView(name: artist.name, fallbackAlbumID: artist.albumIDs.first)
                .frame(height: 480).frame(maxWidth: .infinity).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.55), .black], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(artist.name).font(.artistTitle).lineLimit(2).minimumScaleFactor(0.55)
                Text("Artist · \(releases) release\(releases == 1 ? "" : "s")").linerLabel()
            }
            .padding(16)
        }
        .frame(height: 480)
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
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
        .environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark)
}
