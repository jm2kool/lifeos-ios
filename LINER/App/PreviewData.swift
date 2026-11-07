import Foundation

/// Made-up library data for SwiftUI previews.
@MainActor
enum PreviewData {
    static let library = LibraryService(preview: snapshot)
    static let player = PlaybackCoordinator(library: library)
    static let passports = PassportPresenter()

    static let snapshot: LibrarySnapshot = {
        let albums: [(String, String, String, Int)] = [
            ("Melodrama", "Lorde", "Pop", 2017), ("Blonde", "Frank Ocean", "R&B", 2016),
            ("cold/mess", "Prateek Kuhad", "Indie", 2018), ("Roja", "A. R. Rahman", "Soundtrack", 1992),
        ]
        var songs: [Song] = []
        var albumList: [Album] = []
        for (a, info) in albums.enumerated() {
            let albumID = UInt64(100 + a)
            var ids: [UInt64] = []
            for t in 1...6 {
                let id = UInt64(a * 10 + t)
                ids.append(id)
                songs.append(Song(id: id, title: "\(info.0) Track \(t)", artist: info.1, albumTitle: info.0, albumArtist: info.1,
                                  albumID: albumID, genre: info.2, composer: info.1, duration: 200 + Double(t * 13),
                                  playCount: (7 - t) * (a + 3) * 4, rating: t % 5, trackNumber: t, discNumber: 1,
                                  dateAdded: .now.addingTimeInterval(Double(-a * 86_400 - t)), lastPlayed: .now,
                                  releaseDate: Calendar.current.date(from: DateComponents(year: info.3)),
                                  storeID: "", isCloudOnly: t == 6, hasArtwork: false))
            }
            let mine = songs.filter { $0.albumID == albumID }
            albumList.append(Album(id: albumID, title: info.0, artist: info.1, genre: info.2, year: info.3, songIDs: ids,
                                   playCount: mine.reduce(0) { $0 + $1.playCount }, duration: mine.reduce(0) { $0 + $1.duration },
                                   dateAdded: .now.addingTimeInterval(Double(-a * 86_400)), rating: 3))
        }
        let artists = albumList.map {
            Artist(id: MediaKey.normalise($0.artist), name: $0.artist, albumIDs: [$0.id], songCount: $0.songCount,
                   playCount: $0.playCount, dateAdded: $0.dateAdded, rating: 3)
        }
        let playlists = [Playlist(id: 900, name: "Late Night", songIDs: songs.prefix(12).map(\.id),
                                  coverAlbumIDs: albumList.map(\.id), playCount: 300, dateAdded: .now)]
        return LibrarySnapshot(songs: songs, albums: albumList, artists: artists, playlists: playlists)
    }()
}
