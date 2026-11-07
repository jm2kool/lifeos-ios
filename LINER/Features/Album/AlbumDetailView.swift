import SwiftUI

/// An album (SPEC §6.4): full-bleed cover, serif title, glass actions, facts, tracklist,
/// your listening history and your top 3 songs.
struct AlbumDetailView: View {
    let album: Album
    @Environment(LibraryService.self) private var library
    @Environment(\.openURL) private var openURL

    private var songs: [Song] { AlbumExtras.tracks(for: album, library: library) }

    private var facts: String {
        var parts = ["ALBUM", "\(album.songCount) SONG\(album.songCount == 1 ? "" : "S")", album.duration.minutesLabel]
        if !album.genre.isEmpty { parts.append(album.genre.uppercased()) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let tracks = songs
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    AlbumExtras.header(album: album).aspectRatio(1, contentMode: .fit).clipped()
                    LinearGradient(colors: [.clear, .black], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(album.title).font(.itemTitle).lineLimit(3)
                    if let artist = library.snapshot.artist(named: album.artist) {
                        NavigationLink(value: artist) { Text(album.artist).linerLabel(size: 12) }.buttonStyle(.plain)
                    } else {
                        Text(album.artist).linerLabel(size: 12)
                    }
                    actions(tracks).padding(.top, 10)
                    Text(facts).linerLabel(size: 10).padding(.top, 8)
                    AlbumExtras.editionSwitcher(album: album)
                }
                .padding(.horizontal, 16).padding(.top, -24)

                VStack(spacing: 0) {
                    ForEach(tracks) { song in
                        PlayableSongRow(song: song, list: tracks, number: song.trackNumber > 0 ? song.trackNumber : nil, showArtwork: false)
                            .padding(.vertical, 10)
                        Divider().overlay(Palette.stroke)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 18)

                if let date = library.snapshot.songs(album.songIDs).compactMap(\.releaseDate).first {
                    Text("Released \(date.formatted(date: .long, time: .omitted))")
                        .font(.footnote).foregroundStyle(Palette.label).padding(16)
                }
                AlbumHistory(album: album, songs: library.snapshot.songs(album.songIDs)).padding(.horizontal, 16).padding(.top, 8)
            }
            .padding(.bottom, 32)
        }
        .background(Palette.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AlbumExtras.moreMenu(album: album) } }
    }

    private func actions(_ tracks: [Song]) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                PlayShuffleRow(songs: tracks)
                GlassCircleButton(systemImage: "arrow.down.circle", label: "Download in Music") { openInMusic(tracks) }
                AlbumExtras.passportButton(album: album)
            }
        }
    }

    /// A third-party app can't download, so this opens the album in the Music app to download there.
    private func openInMusic(_ tracks: [Song]) {
        if let id = tracks.first(where: { !$0.storeID.isEmpty && $0.storeID != "0" })?.storeID,
           let url = URL(string: "https://music.apple.com/song/\(id)") {
            openURL(url)
        } else if let url = URL(string: "music://") {
            openURL(url)
        }
    }
}

/// My Listening History and Your Top 3 Songs.
struct AlbumHistory: View {
    let album: Album
    let songs: [Song]
    @Environment(LibraryService.self) private var library

    var body: some View {
        let top = songs.sorted { $0.playCount > $1.playCount }.prefix(3).filter { $0.playCount > 0 }
        VStack(alignment: .leading, spacing: 14) {
            Text("My Listening History").font(.sectionTitle)
            HStack(spacing: 12) {
                StatTile("Avg plays", text: LibraryStats.averagePlays(album).formatted(.number.precision(.fractionLength(0...1))))
                StatTile("Minutes", value: library.stats.minutes(of: album), footnote: "Estimated")
                StatTile("Rank", text: library.stats.rank(of: album).map { "#\($0)" } ?? "—", footnote: "Top albums")
            }
            if !top.isEmpty {
                Text("Your Top 3 Songs").font(.sectionTitle).padding(.top, 8)
                ForEach(Array(top.enumerated()), id: \.element.id) { i, s in
                    PlayableSongRow(song: s, list: Array(top), number: i + 1).padding(.vertical, 4)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { AlbumDetailView(album: PreviewData.snapshot.albums[0]) }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
