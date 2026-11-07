@preconcurrency import MediaPlayer

/// One library song, copied out of MediaPlayer into a plain value so it can cross threads.
struct Song: Identifiable, Hashable, Sendable {
    let id: UInt64            // persistentID
    let title: String
    let artist: String
    let albumTitle: String
    let albumArtist: String
    let albumID: UInt64
    let genre: String
    let composer: String
    let duration: Double
    let playCount: Int
    /// The star rating from the Music app, 0–5 (LINER.'s own hearts arrive with the passports).
    let rating: Int
    let trackNumber: Int
    let discNumber: Int
    let dateAdded: Date
    let lastPlayed: Date?
    let releaseDate: Date?
    let storeID: String
    let isCloudOnly: Bool
    let hasArtwork: Bool
    /// A playable file for songs without copy protection (iTunes purchases, synced or ripped music).
    var assetURL: URL? = nil
    /// Apple Music (DRM) songs can only be played by the system's queue player.
    var isProtected = false

    /// Songs LINER. can play with its own player, which gives them the full-screen animated lock screen.
    var playsInLINER: Bool { assetURL != nil && !isProtected && UserDefaults.standard.object(forKey: "ownPlayerForFiles") as? Bool ?? true }

    var key: MediaKey {
        MediaKey(persistentID: id, storeID: storeID.isEmpty ? nil : storeID, title: title, artist: artist, album: albumTitle, duration: duration)
    }
}

/// An album, built from its songs.
struct Album: Identifiable, Hashable, Sendable {
    let id: UInt64            // albumPersistentID
    let title: String
    let artist: String
    let genre: String
    let year: Int?
    let songIDs: [UInt64]     // in disc/track order
    let playCount: Int
    let duration: Double
    let dateAdded: Date       // newest song's date added
    let rating: Double        // mean of rated songs, 0 if none

    var songCount: Int { songIDs.count }
    var key: AlbumKey { AlbumKey(albumPersistentID: id, title: title, albumArtist: artist) }
}

/// An artist, grouped by album artist (falling back to the song artist).
struct Artist: Identifiable, Hashable, Sendable {
    let id: String            // normalised name
    let name: String
    let albumIDs: [UInt64]
    let songCount: Int
    let playCount: Int
    let dateAdded: Date
    let rating: Double
}

/// A Music app playlist.
struct Playlist: Identifiable, Hashable, Sendable {
    let id: UInt64
    let name: String
    let songIDs: [UInt64]
    /// Albums of the first few songs, for a cover mosaic.
    let coverAlbumIDs: [UInt64]
    let playCount: Int
    let dateAdded: Date?
}

/// The MediaPlayer items behind a snapshot, by persistent ID, so playback can start without re-querying.
/// MediaPlayer items are read-only proxies, safe to hand between threads.
final class MediaItemIndex: @unchecked Sendable {
    let items: [UInt64: MPMediaItem]
    init(_ items: [UInt64: MPMediaItem] = [:]) { self.items = items }
    subscript(id: UInt64) -> MPMediaItem? { items[id] }
}

/// Everything read from the library in one pass.
struct LibrarySnapshot: Sendable {
    var items = MediaItemIndex()
    /// For each album, a song whose item carries the artwork.
    var artworkSongs: [UInt64: UInt64] = [:]
    let songs: [Song]
    let albums: [Album]
    let artists: [Artist]
    let playlists: [Playlist]
    var scannedAt: Date = .distantPast
    var scanDuration: Duration = .zero

    private let songsByID: [UInt64: Song]
    private let albumsByID: [UInt64: Album]
    private let artistsByID: [String: Artist]

    init(songs: [Song] = [], albums: [Album] = [], artists: [Artist] = [], playlists: [Playlist] = []) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
        self.playlists = playlists
        songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        albumsByID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        artistsByID = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func songs(_ ids: [UInt64]) -> [Song] { ids.compactMap { songsByID[$0] } }
    func album(_ id: UInt64) -> Album? { albumsByID[id] }
    func artist(named name: String) -> Artist? { artistsByID[MediaKey.normalise(name)] }
    func albums(of artist: Artist) -> [Album] { artist.albumIDs.compactMap { albumsByID[$0] } }
    func songs(of artist: Artist) -> [Song] {
        songs.filter { MediaKey.normalise($0.albumArtist) == artist.id || MediaKey.normalise($0.artist) == artist.id }
    }
}

/// How library lists can be ordered (SPEC §6.2).
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case alphabetical = "A–Z", mostPlayed = "Most played", recentlyAdded = "Recently added", rating = "Rating"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .alphabetical: "textformat"
        case .mostPlayed: "flame"
        case .recentlyAdded: "clock"
        case .rating: "heart"
        }
    }
}
