import SwiftUI

/// The artist's Page, laid out like Apple Music: latest release, Top Songs in swipeable columns of four,
/// Albums, and Singles & EPs — the whole catalogue, not just your library. Versions of one release show once,
/// like grouped albums in the library. Songs you own play from your library; the rest stream from Apple Music.
struct ArtistCatalogPage: View {
    let artist: Artist
    let page: AppleCatalog.ArtistPage?
    let loading: Bool
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let page {
                let albums = grouped(page.albums), singles = grouped(page.singles)
                if let latest = (albums + singles).max(by: { ($0.releaseDate ?? .distantPast) < ($1.releaseDate ?? .distantPast) }) {
                    latestRelease(latest)
                }
                if !page.topSongs.isEmpty { topSongs(page.topSongs) }
                if !albums.isEmpty { releases("Albums", albums) }
                if !singles.isEmpty { releases("Singles & EPs", singles) }
            } else if loading {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            } else {
                EmptyStateView(symbol: "wifi.slash", title: "Page unavailable",
                               message: "Apple Music doesn't list \(artist.name), or you're offline. Your own stats are in \(AppBrand.name) stats.")
            }
        }
    }

    /// Versions of one release shown once, as in your library: editions grouped by name ("WILD", "WILD (Deluxe)")
    /// and the albums you grouped yourself; editions you separated stay apart.
    private func grouped(_ releases: [AppleCatalog.Release]) -> [AppleCatalog.Release] {
        let mine = library.snapshot.albums(of: artist)
        let split = AlbumGroups.split
        func names(_ album: Album) -> Set<String> {
            let titles = library.snapshot.songs(album.songIDs).map(\.albumTitle) + [album.title]
            return Set(titles.flatMap { [MediaKey.normalise($0), MediaKey.normalise(AlbumEditions.baseTitle($0))] })
        }
        let together = mine.filter { $0.editionIDs.count > 1 }.map(names)
        let apart = mine.filter { split.contains($0.id) }.reduce(into: Set<String>()) { $0.insert(MediaKey.normalise($1.title)) }
        return AppleCatalog.grouped(releases, together: together, apart: apart, byName: AlbumEditions.isOn)
    }

    /// Songs to queue for these tracks: your copies where you have them.
    private func songs(_ tracks: [AppleCatalog.Track]) -> [Song] {
        let mine = library.snapshot.songsByStoreID
        return tracks.map { $0.song(in: library.snapshot, byStoreID: mine) }
    }

    private func latestRelease(_ r: AppleCatalog.Release) -> some View {
        NavigationLink(value: r) {
            HStack(spacing: 14) {
                CatalogArtwork(url: r.artwork, cornerRadius: 10).frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.releaseDate?.formatted(.dateTime.day().month(.abbreviated).year()).uppercased() ?? "LATEST RELEASE")
                        .linerLabel(size: 10)
                    Text(r.title).font(.serif(20)).lineLimit(2)
                    Text(r.isSingleOrEP ? (r.trackCount <= 1 ? "Single" : "EP · \(r.trackCount) songs") : "\(r.trackCount) songs")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func topSongs(_ tracks: [AppleCatalog.Track]) -> some View {
        let mine = library.snapshot.songsByStoreID
        let columns = stride(from: 0, to: tracks.count, by: 4).map { Array(tracks[$0..<min(tracks.count, $0 + 4)]) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Top Songs").font(.sectionTitle).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { c, column in
                        VStack(spacing: 0) {
                            ForEach(Array(column.enumerated()), id: \.element.id) { r, t in
                                topSongRow(t, start: c * 4 + r, all: tracks, owned: mine[String(t.id)] != nil)
                                if r < column.count - 1 { Divider().overlay(Palette.stroke).padding(.leading, 62) }
                            }
                        }
                        .containerRelativeFrame(.horizontal) { w, _ in w * 0.86 }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func topSongRow(_ t: AppleCatalog.Track, start: Int, all: [AppleCatalog.Track], owned: Bool) -> some View {
        let playing = player.current?.song?.storeID == String(t.id)
        return Button { player.play(songs: songs(all), startAt: start) } label: {
            HStack(spacing: 12) {
                CatalogArtwork(url: t.artwork, cornerRadius: 6).frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(.system(size: 16)).lineLimit(1)
                    Text([t.album == t.name ? "Single" : t.album, t.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                if playing {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: player.isPlaying).font(.caption)
                } else if owned {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.faint)
                        .accessibilityLabel("In your library")
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func releases(_ title: String, _ list: [AppleCatalog.Release]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.sectionTitle).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(list) { r in
                        NavigationLink(value: r) {
                            VStack(alignment: .leading, spacing: 5) {
                                CatalogArtwork(url: r.artwork, cornerRadius: 10).frame(width: 160, height: 160)
                                Text(r.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Text(r.year.map(String.init) ?? "").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                            }
                            .frame(width: 160, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// A cover from the web, with the usual placeholder while it loads.
struct CatalogArtwork: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
            if let image = phase.image { image.resizable().scaledToFill() } else { Palette.placeholder }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Palette.stroke))
    }
}

#Preview {
    NavigationStack { ScrollView { ArtistCatalogPage(artist: PreviewData.snapshot.artists[0], page: nil, loading: true) } }
        .environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark)
}
