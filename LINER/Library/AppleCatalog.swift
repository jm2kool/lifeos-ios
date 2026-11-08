import Foundation

/// The Apple Music catalogue through Apple's public iTunes Search API (no key, no MusicKit — fine on free
/// signing): an artist's top songs, albums and singles for the artist page, and a release's tracks.
/// Songs from here play by their Apple Music ID, with your subscription.
enum AppleCatalog {
    struct Track: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let artist: String
        let album: String
        let collectionID: Int
        let artwork: URL?
        let duration: Double
        let trackNumber: Int
        let discNumber: Int
        let genre: String
        let releaseDate: Date?
    }

    struct Release: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let artist: String
        let artwork: URL?
        let releaseDate: Date?
        let trackCount: Int
        let genre: String
        var year: Int? { releaseDate.map { Calendar.current.component(.year, from: $0) } }
        /// Apple names singles and EPs "… - Single" / "… - EP".
        var isSingleOrEP: Bool { name.hasSuffix(" - Single") || name.hasSuffix(" - EP") || trackCount <= 3 }
        /// The name without Apple's " - Single" / " - EP".
        var title: String {
            for suffix in [" - Single", " - EP"] where name.hasSuffix(suffix) { return String(name.dropLast(suffix.count)) }
            return name
        }
    }

    struct ArtistPage: Sendable {
        var topSongs: [Track] = []
        var albums: [Release] = []
        var singles: [Release] = []
        var latest: Release? { (albums + singles).max { ($0.releaseDate ?? .distantPast) < ($1.releaseDate ?? .distantPast) } }
    }

    private static let cache = PageCache()
    static var country: String { Locale.current.region?.identifier ?? "US" }

    /// The artist's page, or nil when Apple doesn't know them (or there's no connection).
    static func artistPage(name: String) async -> ArtistPage? {
        if let hit = await cache.page(name) { return hit }
        guard let found = await artistID(name) else { return nil }
        async let songs = fetch("lookup", ["id": String(found), "entity": "song", "limit": "30"])
        async let releases = fetch("lookup", ["id": String(found), "entity": "album", "limit": "100"])
        let tracks = results(await songs).compactMap(track)
        let all = results(await releases).compactMap(release).sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.title.lowercased()).inserted }
        let page = ArtistPage(topSongs: Array(tracks.prefix(20)), albums: unique.filter { !$0.isSingleOrEP },
                              singles: unique.filter(\.isSingleOrEP))
        await cache.store(page, for: name)
        return page
    }

    /// A release's tracks, in order. Apple's lookup sometimes returns a release with no songs (new singles,
    /// streaming-only releases), so it falls back to searching for the release's songs by name.
    static func tracks(of release: Release) async -> [Track] {
        func ordered(_ t: [Track]) -> [Track] {
            var seen = Set<Int>()
            return t.filter { seen.insert($0.id).inserted }.sorted { ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber) }
        }
        let looked = results(await fetch("lookup", ["id": String(release.id), "entity": "song", "limit": "200"])).compactMap(track)
        if !looked.isEmpty { return ordered(looked) }
        let found = results(await fetch("search", ["term": "\(release.title) \(release.artist)", "entity": "song", "limit": "100"]))
            .compactMap(track)
        let onRelease = found.filter { $0.collectionID == release.id }
        if !onRelease.isEmpty { return ordered(onRelease) }
        // A single listed under another release: the song with the single's name, by the same artist.
        guard release.isSingleOrEP else { return [] }
        let title = MediaKey.normalise(release.title)
        let lead = MediaKey.normalise(release.artist.components(separatedBy: CharacterSet(charactersIn: "&,")).first ?? release.artist)
        let named = found.filter {
            MediaKey.normalise($0.name).hasPrefix(title) && MediaKey.normalise($0.artist).contains(lead)
        }
        return Array(ordered(named).prefix(1))
    }

    /// The whole album as Apple Music lists it, found from the Apple Music ID of any song of yours on it (nil
    /// when none of your songs has one, or Apple doesn't answer). Asks with a few of your songs in case one has
    /// moved to another edition.
    static func fullAlbum(songStoreIDs ids: [String]) async -> [Track]? {
        let key = ids.sorted().joined(separator: ",")
        if let hit = await albumCache.album(key) { return hit }
        for id in ids.prefix(3) {
            guard let song = results(await fetch("lookup", ["id": id])).compactMap(track).first, song.collectionID != 0 else { continue }
            let all = results(await fetch("lookup", ["id": String(song.collectionID), "entity": "song", "limit": "200"]))
                .compactMap(track).sorted { ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber) }
            guard !all.isEmpty else { continue }
            await albumCache.store(all, for: key)
            return all
        }
        return nil
    }

    private static let albumCache = AlbumCache()

    // MARK: Requests

    private static func artistID(_ name: String) async -> Int? {
        let found = results(await fetch("search", ["term": name, "entity": "musicArtist", "attribute": "artistTerm", "limit": "10"]))
        let wanted = MediaKey.normalise(name)
        let match = found.first { MediaKey.normalise($0["artistName"] as? String ?? "") == wanted } ?? found.first
        return match?["artistId"] as? Int
    }

    private static func fetch(_ path: String, _ query: [String: String]) async -> Data? {
        var parts = URLComponents(string: "https://itunes.apple.com/\(path)")!
        parts.queryItems = (query.merging(["country": country]) { a, _ in a }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = parts.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func results(_ data: Data?) -> [[String: Any]] {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return json["results"] as? [[String: Any]] ?? []
    }

    // MARK: Parsing

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }

    private static func artwork(_ r: [String: Any]) -> URL? {
        (r["artworkUrl100"] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")) }
    }

    private static func track(_ r: [String: Any]) -> Track? {
        guard r["wrapperType"] as? String == "track", (r["kind"] as? String ?? "song") == "song", let id = r["trackId"] as? Int else { return nil }
        return Track(id: id, name: r["trackName"] as? String ?? "", artist: r["artistName"] as? String ?? "",
                     album: r["collectionName"] as? String ?? "", collectionID: r["collectionId"] as? Int ?? 0,
                     artwork: artwork(r), duration: Double(r["trackTimeMillis"] as? Int ?? 0) / 1000,
                     trackNumber: r["trackNumber"] as? Int ?? 0, discNumber: r["discNumber"] as? Int ?? 1,
                     genre: r["primaryGenreName"] as? String ?? "",
                     releaseDate: date(r["releaseDate"]))
    }

    private static func release(_ r: [String: Any]) -> Release? {
        guard r["wrapperType"] as? String == "collection", let id = r["collectionId"] as? Int else { return nil }
        return Release(id: id, name: r["collectionName"] as? String ?? "", artist: r["artistName"] as? String ?? "",
                       artwork: artwork(r), releaseDate: date(r["releaseDate"]),
                       trackCount: r["trackCount"] as? Int ?? 0, genre: r["primaryGenreName"] as? String ?? "")
    }
}

extension AppleCatalog.Track {
    /// The song to queue: your library's copy when you have it, otherwise the catalogue song (streamed).
    @MainActor func song(in snapshot: LibrarySnapshot, byStoreID mine: [String: Song]) -> Song {
        if let s = mine[String(id)] { return s }
        let albumID = UInt64(collectionID) | (1 << 61)
        if let artwork { ArtworkCache.shared.register(remote: artwork, for: albumID) }
        return Song(id: UInt64(id) | Song.catalogFlag, title: name, artist: artist, albumTitle: album, albumArtist: artist,
                    albumID: albumID, genre: genre, composer: "", duration: duration, playCount: 0, rating: 0,
                    trackNumber: trackNumber, discNumber: discNumber, dateAdded: .now, lastPlayed: nil, releaseDate: releaseDate,
                    storeID: String(id), isCloudOnly: true, hasArtwork: false)
    }
}

extension LibrarySnapshot {
    /// Library songs by Apple Music ID, to match catalogue songs with your own copies.
    var songsByStoreID: [String: Song] {
        Dictionary(songs.filter(\.hasStoreID).map { ($0.storeID, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Artist pages fetched this session.
private actor PageCache {
    private var pages: [String: AppleCatalog.ArtistPage] = [:]
    func page(_ name: String) -> AppleCatalog.ArtistPage? { pages[name] }
    func store(_ page: AppleCatalog.ArtistPage, for name: String) { pages[name] = page }
}

/// Full albums fetched this session.
private actor AlbumCache {
    private var albums: [String: [AppleCatalog.Track]] = [:]
    func album(_ key: String) -> [AppleCatalog.Track]? { albums[key] }
    func store(_ album: [AppleCatalog.Track], for key: String) { albums[key] = album }
}
