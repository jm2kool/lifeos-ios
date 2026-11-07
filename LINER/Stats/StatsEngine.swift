import Foundation

/// Ranks and totals for the whole library (SPEC §7), worked out once per snapshot off the main thread.
/// Minutes are always estimates: Σ(play count × duration).
struct LibraryStats: Sendable {
    var totalPlays = 0
    var totalMinutes = 0
    var artists: [Artist] = []
    var albums: [Album] = []
    var songs: [Song] = []
    private var artistRanks: [String: Int] = [:]
    private var albumRanks: [UInt64: Int] = [:]
    private var albumMinutes: [UInt64: Int] = [:]
    private var artistMinutes: [String: Int] = [:]

    func rank(of artist: Artist) -> Int? { artistRanks[artist.id] }
    func rank(of album: Album) -> Int? { albumRanks[album.id] }
    func minutes(of album: Album) -> Int { albumMinutes[album.id] ?? 0 }
    func minutes(of artist: Artist) -> Int { artistMinutes[artist.id] ?? 0 }

    /// Average plays per song on an album.
    static func averagePlays(_ album: Album) -> Double {
        album.songCount == 0 ? 0 : Double(album.playCount) / Double(album.songCount)
    }

    init() {}

    init(_ snap: LibrarySnapshot) {
        var lastPlayedByAlbum: [UInt64: Date] = [:]
        var lastPlayedByArtist: [String: Date] = [:]
        var plays = 0
        var minutes = 0.0
        for s in snap.songs {
            plays += s.playCount
            let m = Double(s.playCount) * s.duration / 60
            minutes += m
            albumMinutes[s.albumID, default: 0] += Int(m.rounded())
            let artistKey = MediaKey.normalise(s.albumArtist)
            artistMinutes[artistKey, default: 0] += Int(m.rounded())
            if let d = s.lastPlayed {
                lastPlayedByAlbum[s.albumID] = max(lastPlayedByAlbum[s.albumID] ?? .distantPast, d)
                lastPlayedByArtist[artistKey] = max(lastPlayedByArtist[artistKey] ?? .distantPast, d)
            }
        }
        totalPlays = plays
        totalMinutes = Int(minutes.rounded())

        // Ties break by most recently played.
        songs = snap.songs.filter { $0.playCount > 0 }.sorted {
            ($0.playCount, $0.lastPlayed ?? .distantPast) > ($1.playCount, $1.lastPlayed ?? .distantPast)
        }
        albums = snap.albums.filter { $0.playCount > 0 }.sorted {
            ($0.playCount, lastPlayedByAlbum[$0.id] ?? .distantPast) > ($1.playCount, lastPlayedByAlbum[$1.id] ?? .distantPast)
        }
        artists = snap.artists.filter { $0.playCount > 0 }.sorted {
            ($0.playCount, lastPlayedByArtist[$0.id] ?? .distantPast) > ($1.playCount, lastPlayedByArtist[$1.id] ?? .distantPast)
        }
        for (i, a) in albums.enumerated() { albumRanks[a.id] = i + 1 }
        for (i, a) in artists.enumerated() { artistRanks[a.id] = i + 1 }
    }
}

enum StatsEngine {
    @concurrent
    static func build(_ snapshot: LibrarySnapshot) async -> LibraryStats { LibraryStats(snapshot) }
}
