import SwiftUI

/// Square cover, title and artist, for grids (Recently Added, Albums).
struct AlbumTile: View {
    let album: Album
    var namespace: Namespace.ID?
    /// Shows the album's play count in the cover's bottom-right corner (top albums).
    var showPlays = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(albumID: album.id, cornerRadius: 12)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if showPlays {
                        Text(album.playCount.playsLabel)
                            .font(.system(size: 11, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .glassEffect(.regular, in: Capsule())
                            .padding(7)
                    }
                }
                .modifier(ZoomSource(id: album.id, namespace: namespace))
            Text(album.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Text(album.artist).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.title), \(album.artist)")
        .contextMenu { AlbumActionsMenu(album: album) }
    }
}

/// Marks a view as the start of a zoom transition, when there's a namespace to zoom in.
struct ZoomSource: ViewModifier {
    let id: UInt64
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace { content.matchedTransitionSource(id: id, in: namespace) } else { content }
    }
}

/// A song in a list: small cover (or track number), title, artist, plays.
struct SongRow: View {
    let song: Song
    var number: Int?
    var showArtwork = true
    @Environment(LibraryService.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            if let number {
                Text("\(number)").font(.serif(17)).monospacedDigit().foregroundStyle(Palette.label).frame(width: 26)
            } else if showArtwork {
                ArtworkView(albumID: song.albumID, cornerRadius: 6).frame(width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.8)
                Text(number == nil && library.snapshot.albumOf(song) != nil ? "\(song.artist) · \(song.albumTitle)" : song.artist)
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if song.isCloudOnly { Image(systemName: "icloud").font(.caption).foregroundStyle(Palette.faint) }
            Text(song.playCount.grouped).font(.serif(16)).monospacedDigit().foregroundStyle(Palette.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title) by \(song.artist), \(song.playCount.playsLabel)")
    }
}

/// An artist in a list: round black-and-white portrait, name, counts.
struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 14) {
            ArtistPortraitView(name: artist.name, fallbackAlbumID: artist.albumIDs.first)
                .frame(width: 56, height: 56).clipShape(Circle())
                .overlay(Circle().stroke(Palette.stroke))
            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name).font(.serif(19)).lineLimit(1)
                Text("\(artist.albumIDs.count) release\(artist.albumIDs.count == 1 ? "" : "s") · \(artist.songCount) songs")
                    .linerLabel(size: 10)
            }
            Spacer()
            Text(artist.playCount.grouped).font(.serif(16)).monospacedDigit().foregroundStyle(Palette.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(artist.name), \(artist.playCount.playsLabel)")
    }
}

/// Up to four covers in a 2×2 mosaic, for playlists.
struct PlaylistCover: View {
    let playlist: Playlist
    var body: some View {
        let ids = playlist.coverAlbumIDs
        Group {
            if ids.count >= 4 {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { ArtworkView(albumID: ids[0], cornerRadius: 0); ArtworkView(albumID: ids[1], cornerRadius: 0) }
                    GridRow { ArtworkView(albumID: ids[2], cornerRadius: 0); ArtworkView(albumID: ids[3], cornerRadius: 0) }
                }
            } else {
                ArtworkView(albumID: ids.first, cornerRadius: 0)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A playlist in a list.
struct PlaylistRow: View {
    let playlist: Playlist
    var body: some View {
        HStack(spacing: 14) {
            PlaylistCover(playlist: playlist).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name).font(.serif(19)).lineLimit(1)
                Text("\(playlist.songIDs.count) songs").linerLabel(size: 10)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Where library rows lead. Albums zoom open from their tile.
struct LibraryDestinations: ViewModifier {
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Album.self) { album in
                AlbumDestination(album: album).navigationTransition(.zoom(sourceID: album.id, in: namespace))
            }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0, namespace: namespace) }
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
            .navigationDestination(for: Mixtape.self) { MixtapeDetailView(mixtape: $0) }
            .navigationDestination(for: MoodPlaylist.self) { MoodPlaylistDetail(playlist: $0) }
            .navigationDestination(for: AppleCatalog.Release.self) { CatalogReleaseView(release: $0) }
    }
}

extension View {
    func libraryDestinations(_ namespace: Namespace.ID) -> some View { modifier(LibraryDestinations(namespace: namespace)) }
}

#Preview {
    let lib = PreviewData.library
    List {
        ArtistRow(artist: lib.snapshot.artists[0])
        SongRow(song: lib.snapshot.songs[0])
        SongRow(song: lib.snapshot.songs[1], number: 2)
        PlaylistRow(playlist: lib.snapshot.playlists[0])
    }
    .environment(lib)
    .preferredColorScheme(.dark)
}
