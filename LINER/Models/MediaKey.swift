import Foundation

/// A song's identity. `persistentID` can change after an iCloud Library re-sync, so we keep enough to find it again
/// (SPEC §4): persistentID → storeID → normalised title + artist + album with duration ±2 s.
struct MediaKey: Codable, Hashable, Sendable {
    var persistentID: UInt64
    var storeID: String?
    var title: String
    var artist: String
    var album: String
    var duration: Double

    /// Lower-case, accent-free, letters and digits only, so "Señorita (Remastered)" ≈ "senoritaremastered".
    static func normalise(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// The fuzzy fallback match.
    func looselyMatches(_ other: MediaKey) -> Bool {
        Self.normalise(title) == Self.normalise(other.title)
            && Self.normalise(artist) == Self.normalise(other.artist)
            && Self.normalise(album) == Self.normalise(other.album)
            && abs(duration - other.duration) <= 2
    }
}

/// An album's identity: its persistent ID plus title and album artist for re-matching.
struct AlbumKey: Codable, Hashable, Sendable {
    var albumPersistentID: UInt64
    var title: String
    var albumArtist: String
}
