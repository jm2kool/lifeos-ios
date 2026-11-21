import SwiftUI

/// An Apple Music album, single or EP from an artist's Page: cover, title, Play and Shuffle, and the tracklist.
/// Songs you own play from your library; the rest stream from Apple Music.
struct CatalogReleaseView: View {
    let release: AppleCatalog.Release
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player
    @State private var tracks: [AppleCatalog.Track] = []
    @State private var loading = true
    @State private var headerHeight: CGFloat = 400
    @State private var scrolled = 0.0
    @State private var coverColor = Color.white
    @State private var colours: [ArtPalette.RGB] = []
    @AppStorage(AlbumText.tracklistKey) private var scale = 1.0
    @AppStorage(AlbumText.titleKey) private var titleScale = 1.0

    private var songs: [Song] {
        let mine = library.snapshot.songsByStoreID
        return tracks.map { $0.song(in: library.snapshot, byStoreID: mine) }
    }

    private var lookKey: String { LookKey.release(release.id) }

    var body: some View {
        let list = songs
        let look = LookStore.shared.look(lookKey)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CoverHeader(lookKey: lookKey, backdrop: .remote(release.artwork), coverColor: coverColor, scrolled: scrolled,
                            height: $headerHeight) {
                    RemoteFill(url: release.artwork)
                }
                VStack(alignment: .leading, spacing: 6) {
                    AlbumLogoTitle(lookKey: lookKey, albumID: nil, title: release.title, maxWidth: 300 * titleScale, maxHeight: 110 * titleScale,
                                   font: .serif(30 * titleScale), fontSize: 30 * titleScale, coverColor: coverColor, skipPlaced: true)
                    Text(release.artist).linerLabel(size: 12 * titleScale)
                    Text([release.isSingleOrEP ? (release.trackCount <= 3 ? "SINGLE" : "EP") : "ALBUM",
                          release.genre.uppercased(), release.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .linerLabel(size: 10 * titleScale)
                    PlayShuffleIcons(play: { player.play(songs: list) }, shuffle: { player.play(songs: list, shuffled: true) })
                        .disabled(list.isEmpty)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, look.layout == .square ? 0 : -24)
                if loading && tracks.isEmpty { ProgressView().padding(30).frame(maxWidth: .infinity) }
                if !loading && tracks.isEmpty {
                    Text("Apple Music isn't listing the songs on this release yet. Try again later, or search for it.")
                        .font(.footnote).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).padding(24)
                }
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, song in
                        row(song, number: tracks[i].trackNumber > 0 ? tracks[i].trackNumber : i + 1) { player.play(songs: list, startAt: i) }
                        Divider().overlay(Palette.stroke)
                    }
                }
                .padding(.horizontal, 16)
                if let date = release.releaseDate {
                    let length = list.reduce(0) { $0 + $1.duration }
                    Text("Released \(date.formatted(date: .long, time: .omitted))" + (length > 0 ? " · \(length.minutesLabel)" : ""))
                        .font(.footnote).foregroundStyle(Palette.label).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                OtherEditionsShelf(title: release.title, artist: release.artist, excludingID: release.id).padding(.top, 12)
            }
            .padding(.bottom, 32)
        }
        .headerScrollProgress(headerHeight: headerHeight, progress: $scrolled)
        .environment(\.albumFace, look.face)
        .artCanvas(colours)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavBarLogo(lookKey: lookKey, albumID: nil, title: release.title, visible: scrolled).environment(\.albumFace, look.face)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add to Library", systemImage: "plus") {
                        AppleCatalog.addToLibrary(String(release.id)) { ok in
                            player.notice = ok ? "Added “\(release.title)” to your library." : "Couldn't add “\(release.title)” to your library."
                        }
                    }
                    LookMenuItems(key: lookKey) { .release($0, release, songs: tracks.map(\.name)) }
                } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        .task(id: release.id) { coverColor = await CoverColor.dominant(.remote(release.artwork)) }
        .task(id: release.id) {
            guard let url = release.artwork else { return }
            colours = await ArtPalette.web([url], key: "release-\(release.id)")
        }
        .task(id: release.id) {
            tracks = await AppleCatalog.tracks(of: release)
            loading = false
        }
    }

    private func row(_ song: Song, number: Int, play: @escaping () -> Void) -> some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Text("\(number)").albumFace(17 * scale, fallback: .serif(17 * scale)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 26 * scale)
                Text(song.title).albumFace(16 * scale, fallback: .system(size: 16 * scale)).lineLimit(1)
                Spacer(minLength: 8)
                if player.current?.song?.storeID == song.storeID {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: player.isPlaying).font(.caption)
                } else if !song.isCatalog {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.faint).accessibilityLabel("In your library")
                }
                Text(song.duration.trackTime).font(.system(size: 13 * scale)).monospacedDigit().foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 11 * scale)
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
    .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports).preferredColorScheme(.dark)
}
