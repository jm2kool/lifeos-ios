import SwiftData
import SwiftUI

/// Home's pins (SPEC §6.1), laid out to fit however many there are: one fills the width, two sit side by side,
/// an odd number puts the first across the top and the rest in pairs underneath. Each pin shows the artist
/// portrait (with a small cover in the corner) or the album artwork.
struct PinnedGrid: View {
    @Query(filter: #Predicate<AlbumNote> { $0.pinned }, sort: \AlbumNote.pinnedAt) private var albumPins: [AlbumNote]
    @Query(sort: \PinnedPlaylist.pinnedAt) private var playlistPins: [PinnedPlaylist]
    @Environment(LibraryService.self) private var library

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
            // An odd count leads with one wide card; the rest go two to a row.
            let wide = list.count % 2 == 1 ? list.first : nil
            let pairs = Array(list.dropFirst(wide == nil ? 0 : 1))
            VStack(spacing: 12) {
                if let wide {
                    card(wide, size: list.count == 1 ? .single : .wide)
                }
                if !pairs.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(pairs) { card($0, size: .half) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func card(_ entry: Entry, size: PinCard.Size) -> some View {
        switch entry {
        case .album(let album, let look):
            NavigationLink(value: album) {
                PinCard(title: album.title, subtitle: album.artist, portraitName: look == .artistPortrait ? album.artist : nil, albumID: album.id, size: size)
            }
            .buttonStyle(.plain)
            .contextMenu { AlbumActionsMenu(album: album) }
        case .playlist(let playlist, let look):
            let topArtist = library.snapshot.songs(playlist.songIDs).max { $0.playCount < $1.playCount }?.albumArtist
            NavigationLink(value: playlist) {
                PinCard(title: playlist.name, subtitle: "Playlist · \(playlist.songIDs.count) songs",
                        portraitName: look == .artistPortrait ? topArtist : nil, albumID: playlist.coverAlbumIDs.first, size: size)
            }
            .buttonStyle(.plain)
            .contextMenu { PlaylistActionsMenu(playlist: playlist) }
        }
    }
}

/// One pinned card: tall 4:5 when it's the only pin, wide across the top of an odd number, square in pairs.
struct PinCard: View {
    enum Size { case single, wide, half }

    let title: String
    let subtitle: String
    let portraitName: String?
    let albumID: UInt64?
    var size: Size = .single

    private var half: Bool { size == .half }
    private var aspect: CGFloat { switch size { case .single: 4 / 5; case .wide: 16 / 10; case .half: 4 / 5 } }

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
                    Text(title).font(.serif(half ? 19 : 30)).lineLimit(2).minimumScaleFactor(0.8)
                    Text(subtitle).linerLabel(size: half ? 9 : 10).lineLimit(1)
                }
                Spacer()
                if portraitName != nil {
                    ArtworkView(albumID: albumID, cornerRadius: 8).frame(width: half ? 34 : 54, height: half ? 34 : 54)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2)))
                }
            }
            .padding(half ? 12 : 18)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.right").font(.system(size: half ? 12 : 15, weight: .semibold))
                .frame(width: half ? 30 : 40, height: half ? 30 : 40).glassEffect(.regular, in: .circle).padding(half ? 10 : 14)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).stroke(Palette.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pinned: \(title), \(subtitle)")
    }
}

#Preview {
    ScrollView { PinnedGrid().padding() }
        .environment(PreviewData.library).modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
