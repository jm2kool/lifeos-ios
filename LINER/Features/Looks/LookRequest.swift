import SwiftUI

/// Something to restyle, and which editor to open for it. Presented from the root view through `PassportPresenter`.
struct LookRequest: Identifiable {
    enum Kind { case logo, font, pinCover }
    enum Backdrop: Hashable {
        case album(UInt64)
        case remote(URL?)
        case artist(String, fallbackAlbumID: UInt64?)
    }

    let id = UUID()
    let kind: Kind
    let key: String
    let title: String
    let artist: String
    let backdrop: Backdrop
    /// Sample song titles for the font preview.
    var songs: [String] = []
    /// The library album, for pin covers (its editions) and other editions.
    var album: Album? = nil

    var isArtist: Bool { if case .artist = backdrop { true } else { false } }
    /// Width over height of the header the logo sits on.
    var aspect: CGFloat { isArtist ? 0.82 : 1 }

    static func album(_ kind: Kind, _ album: Album, snapshot: LibrarySnapshot) -> LookRequest {
        LookRequest(kind: kind, key: LookKey.album(album.id), title: album.title, artist: album.artist, backdrop: .album(album.id),
                    songs: snapshot.songs(album.songIDs).map(\.title), album: album)
    }

    static func release(_ kind: Kind, _ r: AppleCatalog.Release, songs: [String]) -> LookRequest {
        LookRequest(kind: kind, key: LookKey.release(r.id), title: r.title, artist: r.artist, backdrop: .remote(r.artwork), songs: songs)
    }

    static func artist(_ artist: Artist) -> LookRequest {
        LookRequest(kind: .logo, key: LookKey.artist(artist.name), title: artist.name, artist: artist.name,
                    backdrop: .artist(artist.name, fallbackAlbumID: artist.albumIDs.first))
    }
}

/// The cover or photo a logo is placed on.
struct LookBackdrop: View {
    let backdrop: LookRequest.Backdrop

    var body: some View {
        switch backdrop {
        case .album(let id): ArtworkView(albumID: id, cornerRadius: 0)
        case .remote(let url): RemoteFill(url: url)
        case .artist(let name, let fallback): ArtistPortraitView(name: name, fallbackAlbumID: fallback, colour: true)
        }
    }
}

/// A remote picture filling its frame.
struct RemoteFill: View {
    let url: URL?
    var body: some View {
        Color.clear.overlay {
            AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Palette.placeholder }
            }
        }
        .clipped()
    }
}

/// The cover's main colour (for logos tinted "Cover"), loaded once per album.
enum CoverColor {
    @MainActor static func dominant(_ backdrop: LookRequest.Backdrop) async -> Color {
        var image: UIImage?
        switch backdrop {
        case .album(let id):
            image = CoverOverrides.shared.image(id)
            if image == nil { image = await ArtworkCache.shared.image(album: id, pixels: 300) }
        case .remote(let url):
            if let url, let loaded = try? await URLSession.shared.data(from: url) { image = UIImage(data: loaded.0) }
        case .artist(let name, _):
            image = await ArtistImageStore.shared.portrait(for: name, colour: true)
        }
        guard let image else { return .white }
        return await ArtworkAnalysis.look(for: image, key: "colour-\(key(backdrop))").dominant.mix(with: .white, by: 0.2)
    }

    private static func key(_ b: LookRequest.Backdrop) -> String {
        switch b {
        case .album(let id): "album-\(id)"
        case .remote(let url): url?.absoluteString ?? "none"
        case .artist(let name, _): "artist-\(name)"
        }
    }
}

/// The editor for a look request.
struct LookSheet: View {
    let request: LookRequest
    var body: some View {
        switch request.kind {
        case .logo: LogoEditorSheet(request: request)
        case .font: FontPickerSheet(request: request)
        case .pinCover: PinCoverSheet(request: request)
        }
    }
}
