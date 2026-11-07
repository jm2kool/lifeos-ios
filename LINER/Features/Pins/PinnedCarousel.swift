import SwiftData
import SwiftUI

/// Home's pinned carousel (SPEC §6.1): paged 4:5 cards with page dots. Each pin shows the artist portrait
/// (with a small cover in the corner) or the album artwork.
struct PinnedCarousel: View {
    @Query(filter: #Predicate<AlbumNote> { $0.pinned }, sort: \AlbumNote.pinnedAt) private var albumPins: [AlbumNote]
    @Query(sort: \PinnedPlaylist.pinnedAt) private var playlistPins: [PinnedPlaylist]
    @Environment(LibraryService.self) private var library
    @State private var page: String?

    enum Entry: Identifiable {
        case album(Album, PinAppearance)
        case playlist(Playlist, PinAppearance)
        var id: String {
            switch self {
            case .album(let a, _): "a\(a.id)"
            case .playlist(let p, _): "p\(p.id)"
            }
        }
    }

    private var entries: [Entry] {
        let albums: [Entry] = albumPins.compactMap { n in
            guard n.albumID.hasPrefix("album-"), let id = UInt64(n.albumID.dropFirst(6)), let a = library.snapshot.album(id) else { return nil }
            return .album(a, n.pinnedAppearance)
        }
        let playlists: [Entry] = playlistPins.compactMap { p in
            library.snapshot.playlists.first { $0.id == UInt64(bitPattern: p.playlistID) }
                .map { .playlist($0, PinAppearance(rawValue: p.appearanceRaw) ?? .albumArtwork) }
        }
        return albums + playlists
    }

    var body: some View {
        let list = entries
        if !list.isEmpty {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(list) { entry in
                            card(entry).containerRelativeFrame(.horizontal).id(entry.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                if list.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(list) { e in
                            Circle().fill((page ?? list.first?.id) == e.id ? Color.white : Palette.faint).frame(width: 6, height: 6)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder private func card(_ entry: Entry) -> some View {
        switch entry {
        case .album(let album, let look):
            NavigationLink(value: album) {
                PinCard(title: album.title, subtitle: album.artist, portraitName: look == .artistPortrait ? album.artist : nil, albumID: album.id)
            }
            .buttonStyle(.plain)
            .contextMenu { AlbumActionsMenu(album: album) }
        case .playlist(let playlist, let look):
            let topArtist = library.snapshot.songs(playlist.songIDs).max { $0.playCount < $1.playCount }?.albumArtist
            NavigationLink(value: playlist) {
                PinCard(title: playlist.name, subtitle: "Playlist · \(playlist.songIDs.count) songs",
                        portraitName: look == .artistPortrait ? topArtist : nil, albumID: playlist.coverAlbumIDs.first)
            }
            .buttonStyle(.plain)
            .contextMenu { PlaylistActionsMenu(playlist: playlist) }
        }
    }
}

/// One 4:5 pinned card.
struct PinCard: View {
    let title: String
    let subtitle: String
    let portraitName: String?
    let albumID: UInt64?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let portraitName {
                    ArtistPortraitView(name: portraitName, fallbackAlbumID: albumID)
                } else {
                    ArtworkView(albumID: albumID, cornerRadius: 0)
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.serif(30)).lineLimit(2)
                    Text(subtitle).linerLabel(size: 10)
                }
                Spacer()
                if portraitName != nil {
                    ArtworkView(albumID: albumID, cornerRadius: 8).frame(width: 54, height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2)))
                }
            }
            .padding(18)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40).glassEffect(.regular, in: .circle).padding(14)
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).stroke(Palette.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pinned: \(title), \(subtitle)")
    }
}
