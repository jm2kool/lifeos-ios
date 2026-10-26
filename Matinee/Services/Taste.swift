import Foundation
import SwiftUI

/// The character Matinee builds from your swipes.
struct Persona: Codable, Hashable {
    var name: String
    var emoji: String
    var blurb: String
    var topGenres: [String]
    var genreShares: [Double]       // 0…1, same order as topGenres
    var era: String
    var traits: [String]
}

struct TasteProfile: Codable {
    var scores: [String: Double] = [:]      // genre name → score
    var liked: [FilmRef] = []
    var disliked: [String] = []             // film ids
    var likedYears: [Int] = []
    var seen = 0
    var persona: Persona?
    var skipped = false
    var updatedAt = Date.now
    // From your library: genres of films you've saved, rated and liked.
    var libraryScores: [String: Double]?
    var libraryYears: [Int]?
    var librarySignature: String?
    var libraryFilms: Int?
}

/// Your taste: built by the swipe quiz, refined by your ratings, and used for the films and shows picked for you.
@Observable @MainActor
final class Taste {
    static let shared = Taste()
    private(set) var profile = TasteProfile()
    private(set) var picks: [FilmRef] = []           // films and shows, best match first
    private(set) var loadingPicks = false
    private(set) var picksReady = false              // a refresh has finished at least once
    @ObservationIgnored private var picksSignature: String?
    var showQuiz = false

    var done: Bool { profile.persona != nil }
    var shouldOffer: Bool { !done && !profile.skipped }

    private static let key = "tasteProfile"

    private var beforeQuiz: TasteProfile?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let p = try? JSONDecoder().decode(TasteProfile.self, from: data) { profile = p }
        else if let t = Library.shared.doc.taste { profile = t }
    }

    private func save(sync: Bool = true) {
        profile.updatedAt = .now
        if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: Self.key) }
        if sync { Library.shared.storeTaste(profile) }
    }

    /// Take the character saved on your account (after signing in on another device).
    func adopt(_ t: TasteProfile) {
        guard t.updatedAt > profile.updatedAt || profile.persona == nil else { return }
        profile = t
        if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: Self.key) }
        picks = []
    }

    // MARK: Quiz

    func beginQuiz() {
        // Keep the old character until the new one is ready, so skipping a retake loses nothing.
        beforeQuiz = profile
        var fresh = TasteProfile()
        fresh.libraryScores = profile.libraryScores
        fresh.libraryYears = profile.libraryYears
        fresh.librarySignature = profile.librarySignature
        fresh.libraryFilms = profile.libraryFilms
        profile = fresh
        save(sync: false)
    }

    /// Leaving the quiz without finishing puts your previous character back.
    func abandonQuiz() {
        guard let old = beforeQuiz else { return }
        beforeQuiz = nil
        profile = old
        save(sync: false)
    }

    func record(_ film: FilmRef, genres: [String], liked: Bool) {
        profile.seen += 1
        for g in genres { profile.scores[g, default: 0] += liked ? 1 : -0.6 }
        if liked {
            profile.liked.append(film)
            if let y = film.year { profile.likedYears.append(y) }
        } else {
            profile.disliked.append(film.id)
        }
        save()
    }

    func skipQuiz() {
        if beforeQuiz?.persona != nil { abandonQuiz(); return }
        beforeQuiz = nil
        profile.skipped = true
        save()
    }

    @discardableResult
    func finish() -> Persona {
        beforeQuiz = nil
        let p = Self.persona(from: profile)
        profile.persona = p
        save()
        picks = []
        return p
    }

    // MARK: From your library

    /// A fingerprint of the titles that feed the character and the picks, so they're only rebuilt when these change.
    static func signature(_ library: Library) -> String {
        let favs = (library.doc.favorites + library.favoriteShows).map { "fav:\($0.id)" }
        let ids = favs + library.doc.watchlist.map(\.id) + library.doc.liked.map(\.id)
            + library.doc.ratings.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var h = Hasher()
        ids.forEach { h.combine($0) }
        return "\(ids.count)-\(h.finalize())"
    }

    /// Work out your character from what you've saved, liked and rated — no quiz needed.
    /// Watchlisted films count, rated films count by how much you liked them.
    func learnFromLibrary(_ library: Library, force: Bool = false) async {
        let sig = Self.signature(library)
        guard force || profile.librarySignature != sig, Catalog.hasToken else { return }
        var weights: [String: Double] = [:]
        for f in library.doc.favorites { weights[f.id, default: 0] += 2 }
        for f in library.doc.watchlist { weights[f.id, default: 0] += 1 }
        for f in library.doc.liked { weights[f.id, default: 0] += 1.2 }
        for (id, score) in library.doc.ratings {
            let r = Score.toStars(score)
            weights[id, default: 0] += r >= 4 ? 1.2 : r >= 3 ? 0.4 : r <= 2 ? -0.7 : 0
        }
        let ids = Array(weights.keys.filter { $0.hasPrefix("tmdb-") || $0.hasPrefix("tt") }.prefix(160))
        guard !ids.isEmpty else { return }
        var details: [String: FilmDetail] = [:]
        // A few at a time, so a big watchlist doesn't flood TMDB.
        for chunk in stride(from: 0, to: ids.count, by: 8).map({ Array(ids[$0..<min($0 + 8, ids.count)]) }) {
            await withTaskGroup(of: (String, FilmDetail?).self) { g in
                for id in chunk { g.addTask { (id, try? await Catalog.detail(id)) } }
                for await (id, d) in g { if let d { details[id] = d } }
            }
        }
        var scores: [String: Double] = [:], years: [Int] = []
        for (id, d) in details {
            let w = weights[id] ?? 0
            for g in d.genres where Catalog.genres.contains(g) { scores[g, default: 0] += w / Double(max(1, min(d.genres.count, 3))) * 1.5 }
            if w > 0, let y = d.ref.year { years.append(y) }
        }
        guard !scores.isEmpty else { return }
        profile.libraryScores = scores
        profile.libraryYears = years
        profile.librarySignature = sig
        profile.libraryFilms = details.count
        // Build (or refresh) the character once there's enough to go on.
        if profile.persona != nil || details.count >= 5 {
            profile.persona = Self.persona(from: profile)
            picks = []
        }
        save()
    }

    // MARK: Persona

    private static let nouns: [String: String] = [
        "Horror": "Night Owl", "Thriller": "Sleuth", "Crime": "Sleuth", "Mystery": "Sleuth", "Sci-Fi": "Stargazer",
        "Fantasy": "Dreamer", "Drama": "Heartbreaker", "History": "Time Traveller", "War": "Veteran", "Romance": "Romantic",
        "Comedy": "Optimist", "Action": "Maximalist", "Adventure": "Explorer", "Animation": "Kid at Heart",
        "Family": "Kid at Heart", "Documentary": "Truth Hunter", "Music": "Soundtrack Soul", "Western": "Drifter"]
    private static let adjectives: [String: String] = [
        "Horror": "Spooky", "Thriller": "Restless", "Crime": "Shady", "Mystery": "Curious", "Sci-Fi": "Cosmic",
        "Fantasy": "Enchanted", "Drama": "Soulful", "History": "Old-Soul", "War": "Battle-Worn", "Romance": "Tender-Hearted",
        "Comedy": "Cheerful", "Action": "Adrenaline-Fuelled", "Adventure": "Wandering", "Animation": "Wide-Eyed",
        "Family": "Warm", "Documentary": "Inquisitive", "Music": "Rhythmic", "Western": "Dusty"]
    private static let emojis: [String: String] = [
        "Horror": "🕯️", "Thriller": "🕵️", "Crime": "🕵️", "Mystery": "🔍", "Sci-Fi": "🚀", "Fantasy": "🐉", "Drama": "🎻",
        "History": "🏛️", "War": "🎖️", "Romance": "💌", "Comedy": "😂", "Action": "💥", "Adventure": "🧭",
        "Animation": "🎈", "Family": "🎈", "Documentary": "🔎", "Music": "🎧", "Western": "🤠"]
    private static let blurbs: [String: String] = [
        "Horror": "You go looking for the thing under the bed — and judge a film by how long it stays with you after the lights go off.",
        "Thriller": "You clock the twist by minute twenty and secretly love it when you're wrong.",
        "Crime": "Heists, hustles and morally grey anti-heroes. You root for the clever one, not the good one.",
        "Mystery": "Every film is a puzzle box, and you won't rest until you've opened it.",
        "Sci-Fi": "Big ideas, bigger worlds. You'd trade any small talk for one good wormhole.",
        "Fantasy": "You want maps in the opening credits and a world you could get lost in.",
        "Drama": "You want to leave the cinema slightly wrecked — and better for it.",
        "History": "Real lives, real stakes. You love a film that sends you down a Wikipedia hole after.",
        "War": "Courage, chaos and the cost of it all. You don't flinch.",
        "Romance": "Rain-soaked confessions and airport sprints. You're not embarrassed, and you shouldn't be.",
        "Comedy": "Life's heavy enough — you pick the film that makes the room laugh.",
        "Action": "Practical stunts, huge sound, zero apologies. You came for the spectacle.",
        "Adventure": "You want to go somewhere — the further from home, the better.",
        "Animation": "Hand-drawn or pixel-perfect, you know animation is for everyone.",
        "Family": "Warm, funny and secretly emotional. The films you'll rewatch for years.",
        "Documentary": "Truth is stranger than fiction, and you want all of it.",
        "Music": "If the soundtrack's good, you're already halfway in love.",
        "Western": "Wide skies, long silences, one last ride."]

    static func persona(from p: TasteProfile) -> Persona {
        // Quiz swipes and your library both count.
        let combined = p.scores.merging(p.libraryScores ?? [:], uniquingKeysWith: +)
        let ranked = combined.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let top = ranked.first?.key ?? "Drama"
        let second = ranked.dropFirst().first?.key ?? (top == "Drama" ? "Comedy" : "Drama")
        let noun = nouns[top] ?? "Film Fan"
        var adj = adjectives[second] ?? "Curious"
        if nouns[second] == noun { adj = adjectives[ranked.dropFirst(2).first?.key ?? "Mystery"] ?? "Curious" }
        let leaders = Array(ranked.prefix(4))
        let maxScore = leaders.first?.value ?? 1

        let years = p.likedYears + (p.libraryYears ?? [])
        let avgYear = years.isEmpty ? 2010 : years.reduce(0, +) / years.count
        let era: String
        switch avgYear {
        case ..<1975: era = "Golden-age soul"
        case ..<1995: era = "Loves the classics"
        case ..<2008: era = "2000s at heart"
        case ..<2018: era = "Modern-era regular"
        default: era = "Always on the new stuff"
        }
        let likes = p.liked.count, total = likes + p.disliked.count
        var traits: [String] = []
        if total > 0 {
            let ratio = Double(likes) / Double(total)
            traits.append(ratio > 0.7 ? "Easy to please" : ratio < 0.35 ? "Tough crowd" : "Picky in the best way")
        } else if let avg = Library.shared.averageRating {
            traits.append(avg >= 78 ? "Easy to please" : avg <= 58 ? "Tough crowd" : "Picky in the best way")
        }
        if ranked.count >= 5 { traits.append("Genre-hopper") } else { traits.append("Knows what they like") }
        if Library.shared.doc.watchlist.count >= 40 { traits.append("Watchlist hoarder") }

        return Persona(name: "The \(adj) \(noun)", emoji: emojis[top] ?? "🎬", blurb: blurbs[top] ?? "",
                       topGenres: leaders.map(\.key), genreShares: leaders.map { $0.value / maxScore },
                       era: era, traits: traits)
    }

    // MARK: Picked for you

    /// A title recommendations grow from, and how much it counts.
    struct Seed { var film: FilmRef; var weight: Double }

    /// What you love counts most: your favourites, then titles you scored highly, then your watchlist,
    /// then titles you scored lower. Anything under 50 isn't a seed at all.
    static func seeds(_ library: Library, quizLikes: [FilmRef]) -> [Seed] {
        let d = library.doc
        var pool: [String: Seed] = [:]
        func add(_ f: FilmRef, _ w: Double) {
            guard TMDB.path(f.id) != nil, w > (pool[f.id]?.weight ?? 0) else { return }
            pool[f.id] = Seed(film: f, weight: w)
        }
        // Ratings are kept by id; find a poster-ready ref for each from wherever the title appears.
        var refs = library.watchedFilms + d.watchlist + d.liked
        refs += (d.shows ?? [:]).values.map(\.show)
        refs += library.currentlyWatching
        var known: [String: FilmRef] = [:]
        for f in refs where known[f.id] == nil { known[f.id] = f }
        for (id, score) in d.ratings where score >= 50 && !library.isComfort(id) {
            guard let f = known[id] else { continue }
            add(f, score >= 80 ? 3 + (score - 80) / 20 : 0.6 + (score - 50) / 30 * 0.8)   // high: 3–4, lower: 0.6–1.4
        }
        for f in d.watchlist { add(f, 2) }
        for f in quizLikes { add(f, 2) }
        for f in d.liked + library.currentlyWatching { add(f, 2.5) }
        for f in d.favorites + library.favoriteShows { add(f, 6) }

        // A weighted draw, so favourites are almost always in and the rest rotate between refreshes.
        func draw(_ s: [Seed], _ k: Int) -> [Seed] {
            s.map { ($0, pow(Double.random(in: 0.0001..<1), 1 / $0.weight)) }.sorted { $0.1 > $1.1 }.prefix(k).map { $0.0 }
        }
        let all = Array(pool.values)
        return draw(all.filter { !$0.film.isShow }, 9) + draw(all.filter(\.film.isShow), 6)
    }

    func refreshPicks(library: Library, force: Bool = false) async {
        let sig = Self.signature(library)
        if !force && !picks.isEmpty && sig == picksSignature { return }
        guard Catalog.hasToken else { return }
        loadingPicks = true
        defer { loadingPicks = false }
        let seeds = Self.seeds(library, quizLikes: Array(profile.liked.suffix(8)))
        // Each recommendation scores the weight of every seed that suggested it, a little more near the top of TMDB's list.
        var found: [String: (film: FilmRef, score: Double, firstSeen: Int)] = [:]
        var order = 0
        await withTaskGroup(of: (Double, [FilmRef]).self) { g in
            for s in seeds { g.addTask { (s.weight, await TMDB.recommendations(s.film.id)) } }
            for await (w, list) in g {
                for (rank, f) in list.enumerated() {
                    order += 1
                    let add = w * (1 - 0.5 * Double(rank) / Double(max(list.count, 1)))
                    if let c = found[f.id] { found[f.id] = (c.film, c.score + add, c.firstSeen) } else { found[f.id] = (f, add, order) }
                }
            }
        }
        let exclude = Set(profile.disliked + profile.liked.map(\.id) + seeds.map(\.film.id))
        // Only things you haven't seen, saved or rated yet.
        func isNew(_ f: FilmRef) -> Bool {
            !exclude.contains(f.id) && !library.isWatched(f.id) && !library.inWatchlist(f.id)
                && library.rating(f.id) == nil && library.progress(f.id) == nil && !library.isCurrentlyWatching(f.id)
        }
        var ranked = found.values.filter { isNew($0.film) }
            .sorted { ($0.score, -$0.firstSeen) > ($1.score, -$1.firstSeen) }
            .map(\.film)
        if ranked.filter({ !$0.isShow }).count < 10 {
            let more = await TMDB.discover(genres: Array((profile.persona?.topGenres ?? []).prefix(2)))
            ranked += more.filter { f in isNew(f) && !ranked.contains { $0.id == f.id } }
        }
        let films = ranked.filter { !$0.isShow }.prefix(24), shows = ranked.filter(\.isShow).prefix(24)
        let keep = Set((films + shows).map(\.id))
        picksSignature = sig
        picksReady = true
        withAnimation(.smooth) { picks = ranked.filter { keep.contains($0.id) } }
    }

    func seedDemo() {
        var p = TasteProfile()
        p.scores = ["Sci-Fi": 6, "Thriller": 4.4, "Drama": 3, "Animation": 1.4, "Horror": -1.2]
        p.likedYears = [2014, 2010, 2019, 2023, 2001]
        p.liked = [FilmRef(id: "tmdb-157336", title: "Interstellar", year: 2014), FilmRef(id: "tmdb-27205", title: "Inception", year: 2010)]
        p.disliked = ["tmdb-0", "tmdb-1", "tmdb-2"]
        p.seen = 20
        p.persona = Self.persona(from: p)
        profile = p
    }
}
