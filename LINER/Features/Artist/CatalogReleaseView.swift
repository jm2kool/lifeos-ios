import SwiftUI

/// An Apple Music album, single or EP from an artist's Page: cover, title, Play and Shuffle, and the tracklist.
/// Songs you own play from your library; the rest stream from Apple Music.
struct CatalogReleaseView: View {
    let release: AppleCatalog.Release
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @State private var tracks: [AppleCatalog.Track] = []
    @State private var loading = true

    private var songs: [Song] {
        let mine = library.snapshot.songsByStoreID
        return tracks.map { $0.song(in: library.snapshot, byStoreID: mine) }
    }

    var body: some View {
        let list = songs
        ScrollView {
            VStack(spacing: 14) {
                CatalogArtwork(url: release.artwork, cornerRadius: 14)
                    .frame(width: 270, height: 270)
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
                    .padding(.top, 12)
                VStack(spacing: 4) {
                    Text(release.title).font(.serif(26)).lineLimit(1).minimumScaleFactor(0.45)
                    Text(release.artist).linerLabel(size: 12)
                    Text([release.isSingleOrEP ? (release.trackCount <= 3 ? "SINGLE" : "EP") : "ALBUM",
                          release.genre.uppercased(), release.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .linerLabel(size: 10)
                }
                .padding(.horizontal, 24)
                PlayShuffleIcons(play: { player.play(songs: list) }, shuffle: { player.play(songs: list, shuffled: true) })
                    .disabled(list.isEmpty)
                    .padding(.vertical, 6)
                if loading && tracks.isEmpty { ProgressView().padding(30) }
                if !loading && tracks.isEmpty {
                    Text("Apple Music isn't listing the songs on this release yet. Try again later, or search for it.")
                        .font(.footnote).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).padding(24)
                }
                VStack(spacing: 0) {
                    ForEach(RecordSide.split(list.count)) { side in
                        if list.count > 3 {
                            SideHeader(side: side, duration: list[side.range].reduce(0) { $0 + $1.duration })
                                .padding(.top, side.name == "A" ? 6 : 22).padding(.bottom, 2)
                        }
                        ForEach(Array(side.range), id: \.self) { i in
                            row(list[i], number: tracks[i].trackNumber > 0 ? tracks[i].trackNumber : i + 1) { player.play(songs: list, startAt: i) }
                            Divider().overlay(Palette.stroke)
                        }
                    }
                }
                .padding(.horizontal, 16)
                if let date = release.releaseDate {
                    let length = list.reduce(0) { $0 + $1.duration }
                    Text("Released \(date.formatted(date: .long, time: .omitted))" + (length > 0 ? " · \(length.minutesLabel)" : ""))
                        .font(.footnote).foregroundStyle(Palette.label).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add to Library", systemImage: "plus") {
                    AppleCatalog.addToLibrary(String(release.id)) { ok in
                        player.notice = ok ? "Added “\(release.title)” to your library." : "Couldn't add “\(release.title)” to your library."
                    }
                }
            }
        }
        .task(id: release.id) {
            tracks = await AppleCatalog.tracks(of: release)
            loading = false
        }
    }

    private func row(_ song: Song, number: Int, play: @escaping () -> Void) -> some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Text("\(number)").font(.serif(17)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 26)
                Text(song.title).font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                if player.current?.song?.storeID == song.storeID {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: player.isPlaying).font(.caption)
                } else if !song.isCatalog {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.faint).accessibilityLabel("In your library")
                }
                Text(song.duration.trackTime).font(.system(size: 13)).monospacedDigit().foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { CatalogSongMenu(song: song) }
    }
}

#Preview {
    NavigationStack {
        CatalogReleaseView(release: .init(id: 1, name: "Melodrama", artist: "Lorde", artwork: nil, releaseDate: .now, trackCount: 11, genre: "Pop"))
    }
    .environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark)
}
