@preconcurrency import MediaPlayer

/// Reads the whole library off the main thread and turns it into plain values (SPEC §7: 10k songs in under 1 s).
enum LibraryScanner {
    @concurrent
    static func scan() async -> LibrarySnapshot {
        let clock = ContinuousClock()
        let start = clock.now
        let items = MPMediaQuery.songs().items ?? []
        let songs = items.map(song(from:))

        // Albums, from songs grouped by album ID.
        var albumSongs: [UInt64: [Song]] = [:]
        for s in songs { albumSongs[s.albumID, default: []].append(s) }
        let albums: [Album] = albumSongs.compactMap { id, tracks in
            guard let first = tracks.first else { return nil }
            let ordered = tracks.sorted { ($0.discNumber, $0.trackNumber, $0.title) < ($1.discNumber, $1.trackNumber, $1.title) }
            let rated = tracks.filter { $0.rating > 0 }
            let year = tracks.compactMap(\.releaseDate).first.map { Calendar.current.component(.year, from: $0) }
            return Album(id: id, title: first.albumTitle.isEmpty ? "Unknown Album" : first.albumTitle,
                         artist: first.albumArtist, genre: mostCommon(tracks.map(\.genre)), year: year,
                         songIDs: ordered.map(\.id), playCount: tracks.reduce(0) { $0 + $1.playCount },
                         duration: tracks.reduce(0) { $0 + $1.duration },
                         dateAdded: tracks.map(\.dateAdded).max() ?? .distantPast,
                         rating: rated.isEmpty ? 0 : Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count))
        }

        // Artists, from albums grouped by album artist.
        var artistAlbums: [String: [Album]] = [:]
        var artistNames: [String: String] = [:]
        for a in albums {
            let key = MediaKey.normalise(a.artist)
            artistAlbums[key, default: []].append(a)
            if artistNames[key] == nil { artistNames[key] = a.artist }
        }
        let artists: [Artist] = artistAlbums.compactMap { key, list in
            guard !key.isEmpty, let name = artistNames[key] else { return nil }
            let rated = list.filter { $0.rating > 0 }
            return Artist(id: key, name: name,
                          albumIDs: list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }.map(\.id),
                          songCount: list.reduce(0) { $0 + $1.songCount },
                          playCount: list.reduce(0) { $0 + $1.playCount },
                          dateAdded: list.map(\.dateAdded).max() ?? .distantPast,
                          rating: rated.isEmpty ? 0 : rated.reduce(0) { $0 + $1.rating } / Double(rated.count))
        }

        let playlists: [Playlist] = (MPMediaQuery.playlists().collections ?? []).compactMap { c in
            guard let p = c as? MPMediaPlaylist else { return nil }
            let ids = p.items.map(\.persistentID)
            var covers: [UInt64] = []
            for item in p.items where !covers.contains(item.albumPersistentID) && covers.count < 4 { covers.append(item.albumPersistentID) }
            return Playlist(id: p.persistentID, name: p.name ?? "Untitled Playlist", songIDs: ids, coverAlbumIDs: covers,
                            playCount: p.items.reduce(0) { $0 + $1.playCount },
                            dateAdded: p.value(forProperty: "dateCreated") as? Date)
        }

        var snapshot = LibrarySnapshot(songs: songs, albums: albums, artists: artists, playlists: playlists)
        snapshot.scannedAt = .now
        snapshot.scanDuration = clock.now - start
        return snapshot
    }

    private static func song(from item: MPMediaItem) -> Song {
        let artist = item.artist ?? "Unknown Artist"
        let albumArtist = (item.albumArtist?.isEmpty == false ? item.albumArtist : nil) ?? artist
        return Song(id: item.persistentID, title: item.title ?? "Untitled", artist: artist,
                    albumTitle: item.albumTitle ?? "", albumArtist: albumArtist, albumID: item.albumPersistentID,
                    genre: item.genre ?? "", composer: item.composer ?? "", duration: item.playbackDuration,
                    playCount: item.playCount, rating: item.rating, trackNumber: item.albumTrackNumber,
                    discNumber: max(1, item.discNumber), dateAdded: item.dateAdded, lastPlayed: item.lastPlayedDate,
                    releaseDate: item.releaseDate, storeID: item.playbackStoreID, isCloudOnly: item.isCloudItem,
                    hasArtwork: item.artwork != nil)
    }

    private static func mostCommon(_ values: [String]) -> String {
        var counts: [String: Int] = [:]
        for v in values where !v.isEmpty { counts[v, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? ""
    }
}
