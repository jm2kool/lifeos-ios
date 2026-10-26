import Foundation

/// A lightweight reference to a film or a show — enough to draw a poster and open its page.
/// Film IDs are "tmdb-<id>", show IDs "tmdbtv-<id>" (TMDB numbers films and shows separately).
/// Older "tt…" (IMDb) ids still resolve through TMDB's find endpoint.
struct FilmRef: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var year: Int?
    var poster: URL?
    var backdrop: URL?

    var yearText: String { year.map(String.init) ?? "" }
    var isShow: Bool { Self.isShowID(id) }

    static let showPrefix = "tmdbtv-"
    static func isShowID(_ id: String) -> Bool { id.hasPrefix(showPrefix) }
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
    // Shows only
    var creators: [String] = []
    var networks: [String] = []
    var status: String?               // "Returning Series", "Ended", "Canceled"…
    var seasons: [SeasonInfo] = []    // season 0 (specials) included when TMDB has it
    var lastYear: Int?
    var nextEpisode: Episode?

    /// Seasons that count towards finishing a show: everything except the specials.
    var regularSeasons: [SeasonInfo] { seasons.filter { $0.number > 0 && $0.episodeCount > 0 } }
    var hasEnded: Bool { status == "Ended" || status == "Canceled" }
}

struct SeasonInfo: Codable, Hashable, Identifiable {
    var number: Int
    var name: String
    var episodeCount: Int
    var year: Int?
    var poster: URL?
    var overview: String?
    var id: Int { number }
}

struct Episode: Codable, Hashable, Identifiable {
    var season: Int
    var number: Int
    var name: String
    var overview: String?
    var airDate: Date?
    var runtime: Int?
    var still: URL?
    var communityRating: Double?      // 0–10

    var id: String { EpisodeKey.make(season, number) }
    var code: String { EpisodeKey.code(season, number) }
    /// Episodes with no date yet haven't aired.
    var aired: Bool { airDate.map { $0 <= .now } ?? false }
}

enum EpisodeKey {
    static func make(_ season: Int, _ episode: Int) -> String { "s\(season)e\(episode)" }
    static func code(_ season: Int, _ episode: Int) -> String { "S\(season) E\(episode)" }
    static func season(of key: String) -> Int? {
        guard key.hasPrefix("s"), let e = key.firstIndex(of: "e") else { return nil }
        return Int(key[key.index(after: key.startIndex)..<e])
    }
    static func episode(of key: String) -> Int? {
        guard let e = key.firstIndex(of: "e") else { return nil }
        return Int(key[key.index(after: e)...])
    }
}

/// How far you are through a show, and what you thought of each episode and season.
/// Episodes and seasons are rated in stars (0.5–5); the show's own rating lives with the others in `ratings`.
struct ShowProgress: Codable, Hashable {
    var show: FilmRef
    var seen: [String: Date] = [:]                // "s1e3" → when you watched it
    var episodeRatings: [String: Double] = [:]    // "s1e3" → stars
    var seasonRatings: [String: Double] = [:]     // "1" → your own rating for the season
    var updatedAt = Date.now

    var isEmpty: Bool { seen.isEmpty && episodeRatings.isEmpty && seasonRatings.isEmpty }
    func seenCount(season: Int) -> Int { seen.keys.filter { EpisodeKey.season(of: $0) == season }.count }

    /// The average of your episode ratings — for one season, or the whole show when season is nil.
    func average(season: Int? = nil) -> (stars: Double, count: Int)? {
        let r = episodeRatings.filter { season == nil ? (EpisodeKey.season(of: $0.key) ?? 0) > 0 : EpisodeKey.season(of: $0.key) == season }
            .map(\.value).filter { $0 > 0 }
        return r.isEmpty ? nil : (r.reduce(0, +) / Double(r.count), r.count)
    }
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
    // For shows: a season and episode, when the entry is about one rather than the whole show.
    var season: Int?
    var episode: Int?
    var episodeTitle: String?

    var isEpisode: Bool { season != nil && episode != nil }
    /// "S1 E3", "Season 2", or nil for a film or a whole show.
    var episodeLabel: String? {
        guard let s = season else { return nil }
        return episode.map { EpisodeKey.code(s, $0) } ?? "Season \(s)"
    }
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
    var avatarData: Data?             // a photo you picked, small enough to sync with the library
}

/// The whole user library — saved to disk as one JSON document and, when signed in, synced.
struct LibraryDoc: Codable {
    var entries: [LogEntry] = []
    var watchlist: [FilmRef] = []
    var liked: [FilmRef] = []
    var ratings: [String: Double] = [:]      // latest rating per id: films 1–100, shows 0.5–5 stars
    var watched: [FilmRef] = []               // films marked watched without a diary entry
    var lists: [FilmList] = []
    var favorites: [FilmRef] = []             // up to four, shown on your profile
    var profile = Profile()
    var recentSearches: [String] = []
    var taste: TasteProfile?                  // your film character, so it follows you between devices
    var updatedAt = Date.now
    var shows: [String: ShowProgress]?        // episode tracking, by show id
    var ratingScale: Int?                     // nil: film ratings saved before they moved from stars to 1–100

    /// Film ratings used to be 0.5–5 stars; they're scores out of 100 now. Shows and episodes stay in stars.
    mutating func migrate() {
        guard ratingScale == nil else { return }
        for (k, v) in ratings where !FilmRef.isShowID(k) { ratings[k] = Score.fromStars(v) }
        for i in entries.indices where !entries[i].film.isShow { entries[i].rating = entries[i].rating.map(Score.fromStars) }
        ratingScale = 100
    }
}

/// How you like to rate films. Either way the library stores a score out of 100, so switching
/// back and forth never loses anything: stars show it in half steps (10 points each).
enum FilmRatingStyle: String, CaseIterable {
    case score, stars
    static let key = "filmRatingStyle"
    static var current: FilmRatingStyle { UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .score }
}

/// Films are scored 1–100.
enum Score {
    static func fromStars(_ s: Double) -> Double { min(100, max(1, (s * 20).rounded())) }
    static func toStars(_ s: Double) -> Double { s / 20 }
    /// A score as the nearest half star, for showing it in stars.
    static func starsShown(_ s: Double) -> Double { max(0.5, (s / 10).rounded() / 2) }
    static func word(_ s: Double) -> String {
        switch s {
        case ..<20: return "Awful"
        case ..<40: return "Not for me"
        case ..<55: return "Meh"
        case ..<70: return "Good"
        case ..<85: return "Great"
        case ..<95: return "Brilliant"
        default: return "Masterpiece"
        }
    }
    static func text(_ s: Double?) -> String { s.map { $0 > 0 ? String(Int($0.rounded())) : "" } ?? "" }
    /// Ratings as stars for anything: film scores are converted, show and episode stars pass through.
    static func asStars(_ r: Double, id: String) -> Double { FilmRef.isShowID(id) ? r : toStars(r) }
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
