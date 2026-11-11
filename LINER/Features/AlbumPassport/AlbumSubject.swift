import Foundation

/// Anything with an Album Passport: a library album or a mixtape.
struct AlbumSubject: Identifiable, Hashable {
    let id: String              // "album-<pid>" or "mixtape-<uuid>"
    let title: String
    let artist: String
    let tracks: [QueueItem]
    /// The library album, when there is one (for play-count history).
    let album: Album?
    var key: AlbumKey? { album?.key }

    static func library(_ album: Album, snapshot: LibrarySnapshot) -> AlbumSubject {
        AlbumSubject(id: "album-\(album.id)", title: album.title, artist: album.artist,
                     tracks: snapshot.songs(album.songIDs).map(QueueItem.library), album: album)
    }
}

/// Shows passports as sheets from anywhere in the tabs (context menus, album pages).
@MainActor @Observable
final class PassportPresenter {
    var song: QueueItem?
    var album: AlbumSubject?
    var editions: AlbumSubject?
    var cover: CoverRequest?
    var logo: LogoRequest?
}
