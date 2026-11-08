import Foundation

/// Which tracklist an album page shows when no edition is picked: the full album as Apple Music lists it, or only
/// the songs you saved to your library. Full is the default; albums you switch to Saved are remembered (a comma-
/// separated list in `@AppStorage(AlbumTracklist.storageKey)`, so every open page updates together).
enum AlbumTracklist {
    static let storageKey = "savedOnlyAlbums"

    static func savedOnly(_ albumID: String, in stored: String) -> Bool {
        stored.split(separator: ",").contains { $0 == albumID }
    }

    static func setting(_ albumID: String, savedOnly: Bool, in stored: String) -> String {
        var ids = stored.split(separator: ",").map(String.init).filter { $0 != albumID }
        if savedOnly { ids.append(albumID) }
        return ids.joined(separator: ",")
    }
}
