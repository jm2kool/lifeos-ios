import SwiftUI

/// Home's "Made for You" and "From Apple Music" shelves; tap a title to fold the shelf away.
struct ForYouShelves: View {
    @Environment(LibraryService.self) private var library
    @State private var editorial: [AppleMusicWeb.PlaylistRef] = []

    var body: some View {
        let mixes = MadeForYouMix.all(library.snapshot, stats: library.stats)
        VStack(alignment: .leading, spacing: 20) {
            if !mixes.isEmpty {
                CollapsibleShelf("Made for You", id: "madeForYou") {
                    ForEach(mixes) { mix in
                        NavigationLink(value: mix) {
                            tile(title: mix.title, subtitle: mix.subtitle) { MixCover(mix: mix) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !editorial.isEmpty {
                CollapsibleShelf("From Apple Music", id: "fromAppleMusic") {
                    ForEach(editorial.prefix(24)) { ref in
                        NavigationLink(value: ref) {
                            tile(title: ref.title, subtitle: ref.curator) { CatalogArtwork(url: ref.artwork(400), cornerRadius: 0) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task { if editorial.isEmpty { editorial = await AppleMusicWeb.editorial() } }
    }

    private func tile<A: View>(title: String, subtitle: String, @ViewBuilder art: () -> A) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            art().frame(width: 150, height: 150).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One of the Made for You mixes.
struct MadeForYouView: View {
    let mix: MadeForYouMix
    @Environment(LibraryService.self) private var library

    var body: some View {
        let songs = library.snapshot.songs(mix.songIDs)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MixCover(mix: mix).frame(width: 260, height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mix.title).font(.itemTitle)
                    Text("Made for you · \(songs.count) songs · \(songs.reduce(0) { $0 + $1.duration }.minutesLabel)").linerLabel(size: 10)
                    Text(mix.subtitle).font(.footnote).foregroundStyle(Palette.secondary)
                }
                PlayShuffleRow(songs: songs)
                LazyVStack(spacing: 0) {
                    ForEach(songs) { PlayableSongRow(song: $0, list: songs).padding(.vertical, 6) }
                }
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// An Apple Music playlist (Essentials, editors' picks): artwork, curator and songs, played from Apple Music.
struct AppleMusicPlaylistView: View {
    let ref: AppleMusicWeb.PlaylistRef
    @Environment(LibraryService.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var playlist: AppleMusicWeb.Playlist?
    @State private var loading = true

    private var songs: [Song] {
        let mine = library.snapshot.songsByStoreID
        return (playlist?.tracks ?? []).map { $0.song(in: library.snapshot, byStoreID: mine) }
    }

    var body: some View {
        let list = songs
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CatalogArtwork(url: ref.artwork(900), cornerRadius: 14).frame(width: 270, height: 270)
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 12).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ref.title).font(.itemTitle).lineLimit(3)
                    Text(ref.curator).linerLabel(size: 11)
                    if !list.isEmpty {
                        Text("\(list.count) songs · \(list.reduce(0) { $0 + $1.duration }.minutesLabel)").linerLabel(size: 10)
                    }
                }
                PlayShuffleRow(songs: list)
                if loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                if !loading && list.isEmpty {
                    EmptyStateView(symbol: "wifi.slash", title: "Couldn't open this playlist",
                                   message: "Apple Music's page didn't load. Try again later, or open it in Music.")
                }
                LazyVStack(spacing: 0) {
                    ForEach(list) { PlayableSongRow(song: $0, list: list).padding(.vertical, 6) }
                }
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Open in Music", systemImage: "arrow.up.forward.app") { if let url = ref.webURL { openURL(url) } }
            }
        }
        .task(id: ref.id) {
            playlist = await AppleMusicWeb.playlist(ref)
            loading = false
        }
    }
}

/// The artist's playlists on Apple Music (Essentials and the rest), on their Page. Tap the title to fold it away.
struct ArtistPlaylistsShelf: View {
    let artist: String
    @State private var playlists: [AppleMusicWeb.PlaylistRef] = []

    var body: some View {
        Group {
            if !playlists.isEmpty {
                CollapsibleShelf("Apple Music Playlists", id: "artistPlaylists", horizontalPadding: 16) {
                    ForEach(playlists) { ref in
                        NavigationLink(value: ref) {
                            VStack(alignment: .leading, spacing: 6) {
                                CatalogArtwork(url: ref.artwork(400), cornerRadius: 10).frame(width: 150, height: 150)
                                Text(ref.title).font(.system(size: 14, weight: .medium)).lineLimit(2).frame(width: 150, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: artist) { playlists = await AppleMusicWeb.artistPlaylists(artist) }
    }
}

#Preview {
    NavigationStack { ScrollView { ForYouShelves().padding() } }
        .environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark)
}
