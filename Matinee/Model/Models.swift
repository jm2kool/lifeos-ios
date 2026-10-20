import Foundation

/// A lightweight reference to a film — enough to draw a poster and open its page.
/// IDs are "tt…" for the free IMDb-backed catalog and "tmdb-…" for TMDB, so entries
/// keep working even if you switch catalogs later.
struct FilmRef: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var year: Int?
    var poster: URL?
    var backdrop: URL?

    var yearText: String { year.map(String.init) ?? "" }
}

struct Person: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var role: String
    var photo: URL?
}

/// Everything shown on a film's page.
struct FilmDetail: Codable, Hashable {
    var ref: FilmRef
    var tagline: String?
    var overview: String?
    var runtimeMinutes: Int?
    var genres: [String] = []
    var directors: [String] = []
    var cast: [Person] = []
    var communityRating: Double?      // 0–10
    var voteCount: Int?
    var similar: [FilmRef] = []
    var countries: [String] = []
}

/// One viewing in your diary.
struct LogEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var film: FilmRef
    var watchedOn: Date = .now
    var rating: Double?               // 0.5 … 5.0 in half steps
    var liked = false
    var rewatch = false
    var review = ""
    var tags: [String] = []
    var createdAt = Date.now
}

struct FilmList: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var note = ""
    var ranked = false
    var films: [FilmRef] = []
    var updatedAt = Date.now
}

struct Profile: Codable, Hashable {
    var name = ""
    var handle = ""
    var bio = ""
    var avatar: URL?
}

/// The whole user library — saved to disk as one JSON document and, when signed in, synced.
struct LibraryDoc: Codable {
    var entries: [LogEntry] = []
    var watchlist: [FilmRef] = []
    var liked: [FilmRef] = []
    var ratings: [String: Double] = [:]      // latest rating per film id
    var watched: [FilmRef] = []               // films marked watched without a diary entry
    var lists: [FilmList] = []
    var favorites: [FilmRef] = []             // up to four, shown on your profile
    var profile = Profile()
    var recentSearches: [String] = []
    var updatedAt = Date.now
}

enum Stars {
    static func text(_ r: Double?) -> String {
        guard let r, r > 0 else { return "" }
        let full = Int(r)
        return String(repeating: "★", count: full) + (r - Double(full) >= 0.5 ? "½" : "")
    }
}

extension Date {
    var monthYear: String { formatted(.dateTime.month(.wide).year()) }
    var dayNumber: String { formatted(.dateTime.day()) }
    var weekdayShort: String { formatted(.dateTime.weekday(.abbreviated)) }
    var year: Int { Calendar.current.component(.year, from: self) }
}
