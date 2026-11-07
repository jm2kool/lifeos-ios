import SwiftUI

/// An album: full-bleed cover, serif title, facts line and tracklist with your plays.
/// (Phase 1 basics — passports, editions and listening history are added in later phases.)
struct AlbumDetailView: View {
    let album: Album
    @Environment(LibraryService.self) private var library

    private var songs: [Song] { library.snapshot.songs(album.songIDs) }

    private var facts: String {
        var parts = ["ALBUM", "\(album.songCount) SONG\(album.songCount == 1 ? "" : "S")", album.duration.minutesLabel]
        if !album.genre.isEmpty { parts.append(album.genre.uppercased()) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    ArtworkView(albumID: album.id, cornerRadius: 0).aspectRatio(1, contentMode: .fit)
                    LinearGradient(colors: [.clear, .black], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(album.title).font(.itemTitle).lineLimit(3)
                    if let artist = library.snapshot.artist(named: album.artist) {
                        NavigationLink(value: artist) { Text(album.artist).linerLabel(size: 12) }.buttonStyle(.plain)
                    } else {
                        Text(album.artist).linerLabel(size: 12)
                    }
                    Text(facts).linerLabel(size: 10).padding(.top, 6)
                }
                .padding(.horizontal, 16).padding(.top, -24)

                VStack(spacing: 0) {
                    ForEach(songs) { song in
                        SongRow(song: song, number: song.trackNumber > 0 ? song.trackNumber : nil, showArtwork: false)
                            .padding(.vertical, 10)
                        Divider().overlay(Palette.stroke)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 22)

                VStack(alignment: .leading, spacing: 4) {
                    if let year = album.year { Text("Released \(String(year))") }
                    Text("\(album.playCount.playsLabel) in your library")
                }
                .font(.footnote).foregroundStyle(Palette.label)
                .padding(16)
            }
        }
        .background(Palette.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AlbumDetailView(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.library).preferredColorScheme(.dark)
}
