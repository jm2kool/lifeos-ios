import Foundation

/// Explicit first: wherever Apple lists a clean and an explicit version of the same song, album or EP, LINER.
/// shows and opens the explicit one. A clean version is only used when Apple has no other.
extension AppleCatalog {
    static let explicit = "explicit", cleaned = "cleaned"

    /// One item per key, in the order they first appear: the explicit version when there is one, otherwise one
    /// that was never censored, otherwise the clean one.
    static func oneEach<T>(_ items: [T], key: (T) -> String, rating: (T) -> String) -> [T] {
        func rank(_ item: T) -> Int { rating(item) == explicit ? 0 : rating(item) == cleaned ? 2 : 1 }
        var best: [String: T] = [:]
        var order: [String] = []
        for item in items {
            let k = key(item)
            if let have = best[k] { if rank(item) < rank(have) { best[k] = item } } else { best[k] = item; order.append(k) }
        }
        return order.compactMap { best[$0] }
    }

    /// The list without the clean versions of things that are also there explicit.
    static func withoutCleanTwins<T>(_ items: [T], key: (T) -> String, rating: (T) -> String) -> [T] {
        let explicitKeys = Set(items.filter { rating($0) == explicit }.map(key))
        return items.filter { rating($0) != cleaned || !explicitKeys.contains(key($0)) }
    }

    /// The explicit version of a clean release, when the artist has one; the release itself otherwise.
    static func explicitVersion(of release: Release) async -> Release {
        guard release.explicitness == cleaned, release.artistID != 0 else { return release }
        let theirs = results(await fetch("lookup", ["id": String(release.artistID), "entity": "album", "limit": "200"])).compactMap(Self.release)
        let wanted = MediaKey.normalise(release.title)
        return theirs.filter { $0.explicitness == explicit && MediaKey.normalise($0.title) == wanted }
            .min { abs($0.trackCount - release.trackCount) < abs($1.trackCount - release.trackCount) } ?? release
    }

    /// For a song on a clean album: the explicit album's ID, when there is one.
    static func explicitCollection(for song: [String: Any]) async -> Int? {
        guard song["collectionExplicitness"] as? String == cleaned, let artist = song["artistId"] as? Int,
              let id = song["collectionId"] as? Int else { return nil }
        let clean = Release(id: id, name: song["collectionName"] as? String ?? "", artist: song["artistName"] as? String ?? "",
                            artwork: nil, releaseDate: nil, trackCount: song["trackCount"] as? Int ?? 0, genre: "",
                            explicitness: cleaned, artistID: artist)
        let found = await explicitVersion(of: clean)
        return found.id == id ? nil : found.id
    }
}

extension AppleCatalog.Track {
    /// The same song on the same release, whichever version it is.
    var twinKey: String { "\(name.lowercased())|\(artist.lowercased())|\(album.lowercased())" }
}
