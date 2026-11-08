import SwiftUI

/// Search results from the whole Apple Music catalogue: artists open their Page, albums and singles open with
/// their tracklist, songs play straight away (your own copy when you have it, otherwise streamed). Hold a song
/// for Play Next, Add to Queue or Add to Library.
struct CatalogSearchResults: View {
    let results: AppleCatalog.SearchResults
    let query: String
    let loading: Bool
    @Environment(LibraryService.self) private var library
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        let mine = library.snapshot.songsByStoreID
        let songs = results.songs.map { $0.song(in: library.snapshot, byStoreID: mine) }
        LazyVStack(alignment: .leading, spacing: 18) {
            if results.isEmpty {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                } else {
                    EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                   message: "Apple Music has nothing for “\(query)”, or you're offline.")
                }
            }
            if !results.artists.isEmpty {
                SectionLabel("Artists")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(results.artists) { a in
                            NavigationLink(value: a.artist(in: library.snapshot)) { artistTile(a) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if !results.albums.isEmpty {
                SectionLabel("Albums & Singles")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(results.albums) { r in
                            NavigationLink(value: r) { releaseTile(r) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if !songs.isEmpty {
                SectionLabel("Songs")
                ForEach(Array(songs.enumerated()), id: \.offset) { i, song in
                    songRow(song, artwork: results.songs[i].artwork) { player.play(songs: songs, startAt: i) }
                }
            }
        }
    }

    private func artistTile(_ a: AppleCatalog.CatalogArtist) -> some View {
        VStack(spacing: 6) {
            ArtistPortraitView(name: a.name, fallbackAlbumID: nil).frame(width: 92, height: 92).clipShape(Circle())
            Text(a.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if !a.genre.isEmpty { Text(a.genre).font(.caption2).foregroundStyle(Palette.secondary).lineLimit(1) }
        }
        .frame(width: 100)
    }

    private func releaseTile(_ r: AppleCatalog.Release) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CatalogArtwork(url: r.artwork, cornerRadius: 8).frame(width: 140, height: 140)
            Text(r.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Text([r.artist, r.isSingleOrEP ? (r.trackCount <= 3 ? "Single" : "EP") : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
        }
        .frame(width: 140)
    }

    private func songRow(_ song: Song, artwork: URL?, play: @escaping () -> Void) -> some View {
        Button(action: play) {
            HStack(spacing: 12) {
                CatalogArtwork(url: artwork, cornerRadius: 6).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.system(size: 16)).lineLimit(1)
                    Text("\(song.artist) · \(song.albumTitle)").font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if player.current?.song?.storeID == song.storeID {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: player.isPlaying).font(.caption)
                } else if !song.isCatalog {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.faint).accessibilityLabel("In your library")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { CatalogSongMenu(song: song) }
    }
}

/// Play Next, Add to Queue and (for songs you don't have) Add to Library.
struct CatalogSongMenu: View {
    let song: Song
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.playNext([.library(song)]) }
        Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.addToQueue([.library(song)]) }
        if song.isCatalog {
            Button("Add to Library", systemImage: "plus") {
                AppleCatalog.addToLibrary(song.storeID) { ok in
                    player.notice = ok ? "Added “\(song.title)” to your library." : "Couldn't add “\(song.title)” to your library."
                }
            }
        }
    }
}
