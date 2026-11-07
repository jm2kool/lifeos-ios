import SwiftUI

/// An artist: black-and-white portrait, large serif name, your top songs and their albums.
/// (Phase 1 basics — the "My LINER." card, ranks and playback arrive in Phases 2–3.)
struct ArtistDetailView: View {
    let artist: Artist
    let namespace: Namespace.ID
    @Environment(LibraryService.self) private var library

    var body: some View {
        let albums = library.snapshot.albums(of: artist)
        let all = library.snapshot.songs(of: artist)
        let top = all.sorted { $0.playCount > $1.playCount }.prefix(10)
        let minutes = Int(all.reduce(0) { $0 + Double($1.playCount) * $1.duration } / 60)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack(alignment: .bottomLeading) {
                    ArtistPortraitView(name: artist.name, fallbackAlbumID: artist.albumIDs.first)
                        .frame(height: 460).frame(maxWidth: .infinity).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.6), .black], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(artist.name).font(.artistTitle).lineLimit(2).minimumScaleFactor(0.6)
                        Text("Artist · \(albums.count) release\(albums.count == 1 ? "" : "s")").linerLabel()
                    }
                    .padding(16)
                }
                .frame(height: 460)

                HStack(spacing: 12) {
                    StatTile("Total plays", value: artist.playCount)
                    StatTile("Minutes", value: minutes, footnote: "Estimated")
                }
                .padding(.horizontal, 16)

                if !top.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("My Top Songs").font(.sectionTitle)
                        ForEach(Array(top.enumerated()), id: \.element.id) { i, song in
                            SongRow(song: song, number: i + 1)
                                .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Albums").font(.sectionTitle).padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(albums) { album in
                                NavigationLink(value: album) { AlbumTile(album: album, namespace: namespace).frame(width: 150) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Palette.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    @Previewable @Namespace var ns
    NavigationStack { ArtistDetailView(artist: PreviewData.snapshot.artists[0], namespace: ns) }
        .environment(PreviewData.library).preferredColorScheme(.dark)
}
