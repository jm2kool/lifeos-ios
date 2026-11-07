import SwiftUI

/// A section title with a See All link.
struct SectionHeader<Destination: View>: View {
    let title: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.sectionTitle)
            Spacer()
            NavigationLink { destination() } label: { Text("See All").linerLabel(size: 10) }
        }
        .padding(.horizontal, 16)
    }
}

/// A full list of songs, optionally numbered by rank.
struct SongListPage: View {
    let title: String
    let songs: [Song]
    var ranked = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                PlayShuffleRow(songs: songs).padding(.bottom, 12)
                ForEach(Array(songs.enumerated()), id: \.element.id) { i, s in
                    PlayableSongRow(song: s, list: songs, number: ranked ? i + 1 : nil).padding(.vertical, 6)
                }
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationTitle(title)
    }
}

/// A grid of albums, optionally with rank badges.
struct AlbumGridPage: View {
    let title: String
    let albums: [Album]
    let namespace: Namespace.ID
    var ranked = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
                ForEach(Array(albums.enumerated()), id: \.element.id) { i, album in
                    NavigationLink(value: album) {
                        AlbumTile(album: album, namespace: namespace, showPlays: ranked).overlay(alignment: .topLeading) {
                            if ranked { RankBadge(rank: i + 1).padding(8) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationTitle(title)
    }
}

/// Ranked artists with plays.
struct ArtistListPage: View {
    let title: String
    let artists: [Artist]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(artists.enumerated()), id: \.element.id) { i, a in
                    NavigationLink(value: a) {
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.serif(17)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 34, alignment: .leading)
                            ArtistRow(artist: a)
                        }
                    }
                    .buttonStyle(.plain).padding(.vertical, 6)
                }
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationTitle(title)
    }
}

/// A small numbered glass badge for rankings.
struct RankBadge: View {
    let rank: Int
    var body: some View {
        Text("\(rank)").font(.serif(15, weight: .semibold)).monospacedDigit()
            .frame(minWidth: 30, minHeight: 30)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel("Rank \(rank)")
    }
}
