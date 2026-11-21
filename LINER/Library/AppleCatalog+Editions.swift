import Foundation

/// Other editions of an album in the Apple Music catalogue ("WILD (Deluxe)", "WILD (Expanded Edition)"), found by
/// the album's base name and artist.
extension AppleCatalog {
    private static let editionsCache = EditionsCache()

    /// Every edition Apple lists for this album, newest first, without the one being shown (`excluding`: its
    /// Apple Music ID, or its exact name when that isn't known).
    static func editions(title: String, artist: String, excludingID: Int? = nil, excludingName: String? = nil) async -> [Release] {
        let base = MediaKey.normalise(AlbumEditions.baseTitle(title))
        guard !base.isEmpty else { return [] }
        let lead = MediaKey.normalise(artist.components(separatedBy: CharacterSet(charactersIn: "&,")).first ?? artist)
        let cacheKey = "\(base)|\(lead)"
        let all: [Release]
        if let hit = await editionsCache.get(cacheKey) {
            all = hit
        } else {
            let found = results(await fetch("search", ["term": "\(AlbumEditions.baseTitle(title)) \(artist)", "entity": "album", "limit": "60"]))
                .compactMap(release)
            var seen = Set<String>()
            all = found
                .filter { MediaKey.normalise(AlbumEditions.baseTitle($0.title)) == base && MediaKey.normalise($0.artist).contains(lead) }
                .sorted { ($0.trackCount, $0.releaseDate ?? .distantPast) > ($1.trackCount, $1.releaseDate ?? .distantPast) }
                .filter { seen.insert("\($0.name.lowercased())|\($0.trackCount)").inserted }
            await editionsCache.set(all, for: cacheKey)
        }
        let skipName = excludingName.map(MediaKey.normalise)
        return all.filter { $0.id != excludingID && (skipName == nil || MediaKey.normalise($0.name) != skipName) }
    }
}

private actor EditionsCache {
    private var found: [String: [AppleCatalog.Release]] = [:]
    func get(_ key: String) -> [AppleCatalog.Release]? { found[key] }
    func set(_ list: [AppleCatalog.Release], for key: String) { found[key] = list }
}
