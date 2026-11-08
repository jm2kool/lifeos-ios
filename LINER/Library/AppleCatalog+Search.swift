@preconcurrency import MediaPlayer

/// Searching the whole Apple Music catalogue (iTunes Search API: no key, no MusicKit), and adding what you find
/// to your library through MediaPlayer.
extension AppleCatalog {
    struct CatalogArtist: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let genre: String
    }

    struct SearchResults: Sendable {
        var artists: [CatalogArtist] = []
        var albums: [Release] = []
        var songs: [Track] = []
        var isEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty }
    }

    /// Artists, albums and songs matching the text, in Apple's order.
    static func search(_ text: String) async -> SearchResults {
        let term = text.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return SearchResults() }
        async let a = fetch("search", ["term": term, "entity": "musicArtist", "limit": "8"])
        async let b = fetch("search", ["term": term, "entity": "album", "limit": "25"])
        async let s = fetch("search", ["term": term, "entity": "song", "limit": "40"])
        let artists = results(await a).compactMap { r -> CatalogArtist? in
            guard let id = r["artistId"] as? Int, let name = r["artistName"] as? String else { return nil }
            return CatalogArtist(id: id, name: name, genre: r["primaryGenreName"] as? String ?? "")
        }
        var seen = Set<String>()
        let albums = results(await b).compactMap(release).filter { seen.insert("\($0.title.lowercased())|\($0.artist.lowercased())").inserted }
        return SearchResults(artists: artists, albums: albums, songs: results(await s).compactMap(track))
    }

    /// Adds a song or album to your Apple Music library by its Apple Music ID (needs a subscription).
    @MainActor static func addToLibrary(_ productID: String, done: @escaping @MainActor @Sendable (Bool) -> Void) {
        MPMediaLibrary.default().addItem(withProductID: productID) { @Sendable entities, error in
            let ok = error == nil && !entities.isEmpty
            Task { @MainActor in done(ok) }
        }
    }
}

extension AppleCatalog.CatalogArtist {
    /// The artist as a page can show it: your library's artist when you have them, otherwise one with only
    /// their Apple Music Page.
    @MainActor func artist(in snapshot: LibrarySnapshot) -> Artist {
        if let mine = snapshot.artist(named: name) { return mine }
        return Artist(id: MediaKey.normalise(name), name: name, albumIDs: [], songCount: 0, playCount: 0, dateAdded: .now, rating: 0)
    }
}
