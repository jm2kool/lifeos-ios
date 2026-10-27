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
    // Films only: the release date (for reminders), and directors with their TMDB ids (for filmographies).
    var releaseDate: Date?
    var directorPeople: [Person] = []    // for shows, the creators
    var crew: [Person] = []              // writers, producers, composer, cinematographer, editor — role is their jobs

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
/// Episodes and seasons are scored 1–100 like everything else; the show's own rating lives with the others in `ratings`.
struct ShowProgress: Codable, Hashable {
    var show: FilmRef
    var seen: [String: Date] = [:]                // "s1e3" → when you watched it
    var episodeRatings: [String: Double] = [:]    // "s1e3" → score
    var seasonRatings: [String: Double] = [:]     // "1" → your own score for the season
    var updatedAt = Date.now

    var isEmpty: Bool { seen.isEmpty && episodeRatings.isEmpty && seasonRatings.isEmpty }
    func seenCount(season: Int) -> Int { seen.keys.filter { EpisodeKey.season(of: $0) == season }.count }

    /// The average of your episode ratings — for one season, or the whole show when season is nil.
    func average(season: Int? = nil) -> (score: Double, count: Int)? {
        let r = episodeRatings.filter { season == nil ? (EpisodeKey.season(of: $0.key) ?? 0) > 0 : EpisodeKey.season(of: $0.key) == season }
            .map(\.value).filter { $0 > 0 }
        return r.isEmpty ? nil : (r.reduce(0, +) / Double(r.count), r.count)
    }

    /// The furthest episode you've ticked off in the regular seasons.
    var lastSeen: (season: Int, episode: Int)? {
        seen.keys.compactMap { k -> (Int, Int)? in
            guard let s = EpisodeKey.season(of: k), let e = EpisodeKey.episode(of: k), s > 0 else { return nil }
            return (s, e)
        }.max { $0 < $1 }
    }
}

/// One viewing in your diary.
struct LogEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var film: FilmRef
    var watchedOn: Date = .now
    var rating: Double?               // 1–100
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

/// "Tell me when it's out": a film and the day it's released.
struct ReleaseReminder: Codable, Hashable, Identifiable {
    var film: FilmRef
    var date: Date
    var id: String { film.id }
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
    var ratings: [String: Double] = [:]      // latest rating per id, 1–100
    var watched: [FilmRef] = []               // films marked watched without a diary entry
    var lists: [FilmList] = []
    var favorites: [FilmRef] = []             // up to four films, shown on your profile
    var profile = Profile()
    var recentSearches: [String] = []
    var taste: TasteProfile?                  // your film character, so it follows you between devices
    var updatedAt = Date.now
    var shows: [String: ShowProgress]?        // episode tracking, by show id
    // A new library starts on today's scales; a missing key in a saved one decodes as nil, so it gets migrated.
    var ratingScale: Int? = 100               // nil: film ratings saved before they moved from stars to 1–100
    var showScale: Int? = 100                 // nil: show, season and episode ratings saved in stars
    var favoriteShows: [FilmRef]?             // up to four shows, shown on your profile
    var currentlyWatching: [FilmRef]?         // shows pinned to the top of Home
    var comfort: [String]?                    // ids of comfort films and shows: watched, never rated
    var watching: [WatchSession]?             // films and episodes in progress, with their intermissions
    var topFavorites: [FilmRef]?              // up to eight films and shows, in your order; nil in libraries from before
    var reminders: [ReleaseReminder]?         // films you asked to be told about when they come out

    /// Favourite films and shows together, in your order. Older libraries kept them apart, films first.
    var allFavorites: [FilmRef] { topFavorites ?? (favorites + (favoriteShows ?? [])) }

    /// Sets the one favourites list, and keeps the films and shows halves (used for your character and by older versions) in step.
    mutating func setFavorites(_ list: [FilmRef]) {
        var seen = Set<String>()
        let list = Array(list.filter { seen.insert($0.id).inserted }.prefix(LibraryDoc.maxFavorites))
        topFavorites = list
        favorites = list.filter { !$0.isShow }
        favoriteShows = list.filter(\.isShow)
    }
    static let maxFavorites = 8

    /// Ratings used to be 0.5–5 stars: films first, then shows, seasons and episodes. They're all scores out of 100 now.
    mutating func migrate() {
        if ratingScale == nil {
            for (k, v) in ratings where !FilmRef.isShowID(k) { ratings[k] = Score.fromStars(v) }
            for i in entries.indices where !entries[i].film.isShow { entries[i].rating = entries[i].rating.map(Score.fromStars) }
            ratingScale = 100
        }
        if showScale == nil {
            for (k, v) in ratings where FilmRef.isShowID(k) { ratings[k] = Score.fromStars(v) }
            for i in entries.indices where entries[i].film.isShow { entries[i].rating = entries[i].rating.map(Score.fromStars) }
            shows = shows?.mapValues { p in
                var p = p
                p.episodeRatings = p.episodeRatings.mapValues(Score.fromStars)
                p.seasonRatings = p.seasonRatings.mapValues(Score.fromStars)
                return p
            }
            showScale = 100
        }
    }
}

/// The All / Movies / Shows switch on Home, the watchlist and the random pick.
enum MediaFilter: String, CaseIterable {
    case all, movies, shows
    var label: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .shows: return "Shows"
        }
    }
    var symbol: String? {
        switch self {
        case .all: return nil
        case .movies: return "film"
        case .shows: return "tv"
        }
    }
    func includes(_ f: FilmRef) -> Bool { self == .all || (self == .shows) == f.isShow }
}

/// How you like to rate films and shows. Either way the library stores a score out of 100, so switching
/// back and forth never loses anything: stars show it in half steps (10 points each).
enum FilmRatingStyle: String, CaseIterable {
    case score, stars
    static let key = "filmRatingStyle"
    static var current: FilmRatingStyle { UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .score }
}

/// Films, shows, seasons and episodes are all scored 1–100.
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
    /// An average in the scale you rate with: "4.2 ★" or "84".
    static func describe(_ s: Double, style: FilmRatingStyle = .current) -> String {
        style == .stars ? "\(toStars(s).formatted(.number.precision(.fractionLength(1)))) ★" : text(s)
    }
    /// A score you'd give yourself: whole points, or the nearest half star when you rate in stars.
    static func rounded(_ s: Double, style: FilmRatingStyle = .current) -> Double {
        style == .stars ? fromStars(starsShown(s)) : min(100, max(1, s.rounded()))
    }
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
