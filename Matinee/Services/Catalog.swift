import Foundation

/// Lenient JSON access so a missing or renamed field never crashes the app — it just shows less.
struct J {
    let raw: Any?
    init(_ raw: Any?) { self.raw = raw }
    subscript(_ key: String) -> J { J((raw as? [String: Any])?[key]) }
    var str: String? { (raw as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (raw as? NSNumber)?.stringValue }
    var int: Int? { (raw as? NSNumber)?.intValue ?? (raw as? String).flatMap { Int($0) } }
    var double: Double? { (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap { Double($0) } }
    var array: [J] { ((raw as? [Any]) ?? []).map { J($0) } }
    var isNull: Bool { raw == nil || raw is NSNull }
}

enum CatalogError: LocalizedError {
    case http(Int), offline, noToken
    var errorDescription: String? {
        switch self {
        case .http(401): return "TMDB didn't accept your token. Check it in Settings → Film data."
        case .http(let c): return "TMDB answered with error \(c)."
        case .offline: return "Couldn't reach TMDB. Check your connection."
        case .noToken: return "Connect TMDB to load films."
        }
    }
}

struct FilmArt: Hashable {
    var logo: URL?
    var logoAspect: Double = 3
    var poster: URL?      // textless poster
    var backdrop: URL?    // textless backdrop
}

struct WatchProvider: Hashable, Identifiable {
    var id: Int
    var name: String
    var logo: URL?

    /// Straight to the film on the service where we know how to search it; otherwise nil.
    func searchURL(for title: String) -> URL? {
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let n = name.lowercased()
        let s: String?
        if n.contains("netflix") { s = "https://www.netflix.com/search?q=\(q)" }
        else if n.contains("amazon") || n.contains("prime") { s = "https://www.primevideo.com/search/ref=atv_nb_sr?phrase=\(q)" }
        else if n.contains("hotstar") { s = "https://www.hotstar.com/in/explore?search_query=\(q)" }
        else if n.contains("apple") { s = "https://tv.apple.com/search?term=\(q)" }
        else if n.contains("google play") { s = "https://play.google.com/store/search?q=\(q)&c=movies" }
        else if n.contains("youtube") { s = "https://www.youtube.com/results?search_query=\(q)+full+movie" }
        else if n.contains("zee5") { s = "https://www.zee5.com/search?q=\(q)" }
        else if n.contains("mubi") { s = "https://mubi.com/en/in/search/films?query=\(q)" }
        else { s = nil }
        return s.flatMap(URL.init(string:))
    }
}

struct WatchProviders: Hashable {
    var link: URL?
    var stream: [WatchProvider] = []
    var free: [WatchProvider] = []
    var rent: [WatchProvider] = []
    var buy: [WatchProvider] = []
    var isEmpty: Bool { stream.isEmpty && free.isEmpty && rent.isEmpty && buy.isEmpty }
}

enum HomeShelf: String, CaseIterable, Identifiable {
    case trending, topRated, newReleases, trendingShows, topRatedShows
    var id: String { rawValue }
    var isShows: Bool { self == .trendingShows || self == .topRatedShows }
    var title: String {
        switch self {
        case .trending: return "Popular this week"
        case .topRated: return "All-time greats"
        case .newReleases: return "New & noteworthy"
        case .trendingShows: return "Shows everyone's watching"
        case .topRatedShows: return "Landmark TV"
        }
    }
}

/// Film data from TMDB (themoviedb.org) — the same database Letterboxd uses.
/// Needs a free API Read Access Token, pasted in the app or baked in at build time.
@MainActor
enum Catalog {
    static var tmdbToken: String {
        let saved = UserDefaults.standard.string(forKey: "tmdbToken") ?? ""
        if !saved.isEmpty { return saved }
        return (Bundle.main.object(forInfoDictionaryKey: "MatineeTMDBToken") as? String) ?? ""
    }
    static var hasToken: Bool { !tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func setToken(_ t: String) {
        UserDefaults.standard.set(t.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "tmdbToken")
        shelfCache = [:]
    }

    private static var detailCache: [String: FilmDetail] = [:]
    private static var shelfCache: [String: [FilmRef]] = [:]

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    // MARK: Public API

    static func shelf(_ s: HomeShelf) async throws -> [FilmRef] {
        let key = s.rawValue
        if let hit = shelfCache[key] { return hit }
        let films = try await TMDB.shelf(s)
        if !films.isEmpty { shelfCache[key] = films }
        return films
    }

    static func search(_ q: String) async throws -> [FilmRef] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return try await TMDB.search(q)
    }

    static func genre(_ g: String) async throws -> [FilmRef] {
        let key = "genre-\(g)"
        if let hit = shelfCache[key] { return hit }
        let films = try await TMDB.genre(g)
        if !films.isEmpty { shelfCache[key] = films }
        return films
    }

    static func detail(_ id: String) async throws -> FilmDetail {
        if let hit = detailCache[id] { return hit }
        let d = try await TMDB.detail(id)
        detailCache[id] = d
        return d
    }

    static func cached(_ id: String) -> FilmDetail? { detailCache[id] }

    private static var seasonCache: [String: [Episode]] = [:]

    /// Every episode in one season of a show.
    static func season(_ showID: String, _ number: Int) async throws -> [Episode] {
        let key = "\(showID)|\(number)"
        if let hit = seasonCache[key] { return hit }
        let eps = try await TMDB.season(showID, number)
        seasonCache[key] = eps
        return eps
    }

    static func cachedSeason(_ showID: String, _ number: Int) -> [Episode]? { seasonCache["\(showID)|\(number)"] }

    private static var artCache: [String: FilmArt] = [:]

    /// Textless poster/backdrop and the film's title logo, for Apple Music–style pages.
    static func art(_ id: String) async -> FilmArt? {
        guard let path = TMDB.path(id) else { return nil }
        if let hit = artCache[id] { return hit }
        guard let j = try? await TMDB.call("\(path)/images", ["include_image_language": "en,null"]) else { return nil }
        func best(_ list: [J], lang: String?) -> J? {
            list.filter { $0["iso_639_1"].str == lang }
                .sorted { ($0["vote_average"].double ?? 0, $0["vote_count"].double ?? 0) > ($1["vote_average"].double ?? 0, $1["vote_count"].double ?? 0) }
                .first
        }
        let logos = j["logos"].array.filter { ($0["file_path"].str ?? "").hasSuffix(".png") }
        let logo = await colourfulLogo(logos) ?? best(logos, lang: "en")
        var art = FilmArt()
        art.logo = TMDB.img(logo?["file_path"].str, "w500")
        art.logoAspect = logo?["aspect_ratio"].double ?? 3
        art.poster = TMDB.img(best(j["posters"].array, lang: nil)?["file_path"].str, "original")
        art.backdrop = TMDB.img(best(j["backdrops"].array, lang: nil)?["file_path"].str, "w1280")
        artCache[id] = art
        return art
    }

    private static var trailerCache: [String: String] = [:]

    /// The YouTube key of the film's best trailer, if TMDB has one.
    static func trailer(_ id: String) async -> String? {
        guard let path = TMDB.path(id) else { return nil }
        if let hit = trailerCache[id] { return hit.isEmpty ? nil : hit }
        guard let j = try? await TMDB.call("\(path)/videos") else { return nil }
        let vids = j["results"].array.filter { $0["site"].str == "YouTube" && $0["key"].str != nil }
        func rank(_ v: J) -> Int {
            (v["type"].str == "Trailer" ? 8 : v["type"].str == "Teaser" ? 4 : 0) + (v["official"].raw as? Bool == true ? 2 : 0)
                + (v["iso_639_1"].str == "en" ? 1 : 0)
        }
        let best = vids.max { rank($0) < rank($1) }?["key"].str
        trailerCache[id] = best ?? ""
        return best
    }

    private static var providerCache: [String: WatchProviders] = [:]

    /// Where the film streams, rents or sells in a country (India by default). Data from JustWatch via TMDB.
    static func providers(_ id: String, region: String = "IN") async -> WatchProviders? {
        guard let path = TMDB.path(id) else { return nil }
        let key = "\(id)|\(region)"
        if let hit = providerCache[key] { return hit }
        guard let j = try? await TMDB.call("\(path)/watch/providers") else { return nil }
        let r = j["results"][region]
        func list(_ k: String) -> [WatchProvider] {
            r[k].array.sorted { ($0["display_priority"].int ?? 99) < ($1["display_priority"].int ?? 99) }.compactMap { p in
                guard let name = p["provider_name"].str else { return nil }
                return WatchProvider(id: p["provider_id"].int ?? name.hashValue, name: name, logo: TMDB.img(p["logo_path"].str, "w154"))
            }
        }
        let out = WatchProviders(link: r["link"].str.flatMap(URL.init(string:)), stream: list("flatrate"),
                                 free: list("free") + list("ads"), rent: list("rent"), buy: list("buy"))
        providerCache[key] = out
        return out
    }

    /// Films often have several logos on TMDB — a coloured original plus white and black versions.
    /// Prefer the coloured one: check the best-rated English logos (small thumbnails) and take the
    /// first that has real colour in it. nil when every version is plain white or black.
    private static func colourfulLogo(_ logos: [J]) async -> J? {
        var english = logos.filter { $0["iso_639_1"].str == "en" }
        if english.isEmpty { english = logos }
        let ranked = english.sorted { ($0["vote_average"].double ?? 0, $0["vote_count"].double ?? 0) > ($1["vote_average"].double ?? 0, $1["vote_count"].double ?? 0) }
        let candidates = Array(ranked.prefix(6))
        guard candidates.count > 1 else { return nil }
        var kinds: [Int: Palette.LogoInk] = [:]
        await withTaskGroup(of: (Int, Palette.LogoInk?).self) { g in
            for (i, c) in candidates.enumerated() {
                guard let url = TMDB.img(c["file_path"].str, "w185") else { continue }
                g.addTask {
                    guard let img = await ImageStore.shared.load(url) else { return (i, nil) }
                    return (i, Palette.logoInk(img))
                }
            }
            for await (i, k) in g { if let k { kinds[i] = k } }
        }
        return candidates.indices.first { kinds[$0] == .colour || kinds[$0] == .darkColour }.map { candidates[$0] }
    }

    static let genres = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Documentary", "Drama",
                         "Family", "Fantasy", "History", "Horror", "Music", "Mystery", "Romance",
                         "Sci-Fi", "Thriller", "War", "Western"]

    // MARK: Networking

    static func get(_ url: URL, headers: [String: String] = [:]) async throws -> J {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let result: (Data, URLResponse)
        do { result = try await session.data(for: req) } catch { throw CatalogError.offline }
        let (data, resp) = result
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw CatalogError.http(h.statusCode) }
        return J(try? JSONSerialization.jsonObject(with: data))
    }

    static func url(_ base: String, _ path: String, _ q: [String: String] = [:]) -> URL {
        var c = URLComponents(string: base + path)!
        if !q.isEmpty { c.queryItems = q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return c.url!
    }
}

// MARK: - TMDB (optional, needs a free token)

@MainActor
enum TMDB {
    static let base = "https://api.themoviedb.org/3"
    static func img(_ p: String?, _ size: String) -> URL? {
        guard let p, !p.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(p)")
    }

    static let genreIDs: [String: Int] = [
        "Action": 28, "Adventure": 12, "Animation": 16, "Comedy": 35, "Crime": 80, "Documentary": 99,
        "Drama": 18, "Family": 10751, "Fantasy": 14, "History": 36, "Horror": 27, "Music": 10402,
        "Mystery": 9648, "Romance": 10749, "Sci-Fi": 878, "Thriller": 53, "War": 10752, "Western": 37]

    /// Accepts either a v4 "API Read Access Token" (long JWT) or a v3 API key.
    static func call(_ path: String, _ q: [String: String] = [:]) async throws -> J {
        let token = Catalog.tmdbToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw CatalogError.noToken }
        var q = q
        q["language"] = "en-US"
        if token.count > 40 {
            return try await Catalog.get(Catalog.url(base, path, q), headers: ["Authorization": "Bearer \(token)"])
        }
        q["api_key"] = token
        return try await Catalog.get(Catalog.url(base, path, q))
    }

    /// The API path for a film or show id: "/movie/603" or "/tv/1399". nil for ids TMDB can't look up directly.
    static func path(_ id: String) -> String? {
        if FilmRef.isShowID(id) { return "/tv/" + String(id.dropFirst(FilmRef.showPrefix.count)) }
        if id.hasPrefix("tmdb-") { return "/movie/" + String(id.dropFirst(5)) }
        return nil
    }

    /// A film or a show from any TMDB list. Shows have a name and first air date instead of a title and release date.
    static func ref(_ m: J) -> FilmRef? {
        let type = m["media_type"].str
        if type == "tv" || (type == nil && m["title"].isNull && !m["first_air_date"].isNull) { return showRef(m) }
        guard type == nil || type == "movie", let id = m["id"].int, let title = m["title"].str ?? m["original_title"].str else { return nil }
        let year = m["release_date"].str.flatMap { Int($0.prefix(4)) }
        return FilmRef(id: "tmdb-\(id)", title: title, year: year,
                       poster: img(m["poster_path"].str, "w500"), backdrop: img(m["backdrop_path"].str, "w1280"))
    }

    static func showRef(_ m: J) -> FilmRef? {
        guard let id = m["id"].int, let name = m["name"].str ?? m["original_name"].str else { return nil }
        let year = m["first_air_date"].str.flatMap { Int($0.prefix(4)) }
        return FilmRef(id: FilmRef.showPrefix + String(id), title: name, year: year,
                       poster: img(m["poster_path"].str, "w500"), backdrop: img(m["backdrop_path"].str, "w1280"))
    }

    static let airDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func episode(_ e: J, season: Int) -> Episode? {
        guard let n = e["episode_number"].int else { return nil }
        return Episode(season: e["season_number"].int ?? season, number: n, name: e["name"].str ?? "Episode \(n)",
                       overview: e["overview"].str, airDate: e["air_date"].str.flatMap { airDate.date(from: $0) },
                       runtime: e["runtime"].int, still: img(e["still_path"].str, "w780"),
                       communityRating: e["vote_average"].double)
    }

    static func list(_ path: String, _ q: [String: String] = [:]) async throws -> [FilmRef] {
        try await call(path, q)["results"].array.compactMap(ref).filter { $0.poster != nil }
    }

    static let genreNames: [Int: String] = Dictionary(uniqueKeysWithValues: genreIDs.map { ($0.value, $0.key) })

    /// Cards for the taste quiz: well-known films across genres, each with its genre names.
    static func deck() async throws -> [(film: FilmRef, genres: [String])] {
        async let a = call("/movie/top_rated", ["page": "1"])
        async let b = call("/movie/popular", ["page": "1"])
        async let c = call("/discover/movie", ["sort_by": "vote_count.desc", "page": "1"])
        async let d = call("/discover/movie", ["sort_by": "vote_count.desc", "page": "2"])
        async let e = call("/movie/top_rated", ["page": "2"])
        let pages = try await [a, b, c, d, e]
        var seen = Set<String>(), out: [(film: FilmRef, genres: [String])] = []
        for j in pages {
            for m in j["results"].array {
                guard let f = ref(m), f.poster != nil, seen.insert(f.id).inserted else { continue }
                let g = m["genre_ids"].array.compactMap { $0.int.flatMap { genreNames[$0] } }
                if !g.isEmpty { out.append((f, g)) }
            }
        }
        // Spread genres out so the first cards aren't all one kind of film.
        var byGenre: [String: [(film: FilmRef, genres: [String])]] = [:]
        for item in out.shuffled() { byGenre[item.genres[0], default: []].append(item) }
        var mixed: [(film: FilmRef, genres: [String])] = []
        while mixed.count < out.count {
            var progressed = false
            for k in byGenre.keys.sorted() where !(byGenre[k]?.isEmpty ?? true) {
                mixed.append(byGenre[k]!.removeFirst()); progressed = true
            }
            if !progressed { break }
        }
        return Array(mixed.prefix(30))
    }

    /// Well-known films in the given genres (all of them), for the endless taste quiz.
    static func deckPage(genres: [String], page: Int) async -> [(film: FilmRef, genres: [String])] {
        var q = ["sort_by": "vote_count.desc", "vote_count.gte": "400", "page": String(page), "include_adult": "false"]
        let ids = genres.compactMap { genreIDs[$0] }.map(String.init)
        if !ids.isEmpty { q["with_genres"] = ids.joined(separator: ",") }
        guard let j = try? await call("/discover/movie", q) else { return [] }
        return j["results"].array.compactMap { m in
            guard let f = ref(m), f.poster != nil else { return nil }
            let g = m["genre_ids"].array.compactMap { $0.int.flatMap { genreNames[$0] } }
            return g.isEmpty ? nil : (f, g)
        }
    }

    static func recommendations(_ id: String) async -> [FilmRef] {
        guard let path = path(id) else { return [] }
        return (try? await list("\(path)/recommendations")) ?? []
    }

    static func discover(genres: [String]) async -> [FilmRef] {
        let ids = genres.compactMap { genreIDs[$0] }.map(String.init).joined(separator: ",")
        guard !ids.isEmpty else { return [] }
        return (try? await list("/discover/movie", ["with_genres": ids, "sort_by": "vote_average.desc", "vote_count.gte": "1500"])) ?? []
    }

    static func shelf(_ s: HomeShelf) async throws -> [FilmRef] {
        switch s {
        case .trending: return try await list("/trending/movie/week")
        case .topRated: return try await list("/movie/top_rated")
        case .newReleases: return try await list("/movie/now_playing")
        case .trendingShows: return try await list("/trending/tv/week")
        case .topRatedShows: return try await list("/tv/top_rated")
        }
    }

    static func genre(_ g: String) async throws -> [FilmRef] {
        try await list("/discover/movie", ["with_genres": String(genreIDs[g] ?? 18), "sort_by": "popularity.desc", "vote_count.gte": "300"])
    }

    /// Films and shows together, in TMDB's order of relevance (people are left out).
    static func search(_ q: String) async throws -> [FilmRef] {
        try await call("/search/multi", ["query": q, "include_adult": "false"])["results"].array
            .filter { $0["media_type"].str == "movie" || $0["media_type"].str == "tv" }
            .compactMap(ref)
    }

    static func detail(_ id: String) async throws -> FilmDetail {
        if FilmRef.isShowID(id) { return try await showDetail(id) }
        var num = id.replacingOccurrences(of: "tmdb-", with: "")
        if id.hasPrefix("tt") {
            // Older entries saved with an IMDb id: look the film up on TMDB.
            let found = try await call("/find/\(id)", ["external_source": "imdb_id"])
            guard let m = found["movie_results"].array.first?["id"].int else { throw CatalogError.http(404) }
            num = String(m)
        }
        let m = try await call("/movie/\(num)", ["append_to_response": "credits,recommendations"])
        guard let r = ref(m) else { throw CatalogError.http(404) }
        var d = FilmDetail(ref: r)
        d.tagline = m["tagline"].str
        d.overview = m["overview"].str
        d.runtimeMinutes = m["runtime"].int
        d.genres = m["genres"].array.compactMap { $0["name"].str?.replacingOccurrences(of: "Science Fiction", with: "Sci-Fi") }
        d.directors = m["credits"]["crew"].array.filter { $0["job"].str == "Director" }.compactMap { $0["name"].str }
        d.cast = m["credits"]["cast"].array.prefix(30).compactMap { c in
            guard let pid = c["id"].int, let name = c["name"].str else { return nil }
            return Person(id: "tmdbp-\(pid)", name: name, role: c["character"].str ?? "", photo: img(c["profile_path"].str, "w185"))
        }
        d.communityRating = m["vote_average"].double
        d.voteCount = m["vote_count"].int
        d.countries = m["production_countries"].array.compactMap { $0["name"].str }
        d.similar = m["recommendations"]["results"].array.compactMap(ref).filter { $0.poster != nil }
        return d
    }

    static func showDetail(_ id: String) async throws -> FilmDetail {
        let num = id.dropFirst(FilmRef.showPrefix.count)
        // aggregate_credits covers every season; plain credits only lists the latest one.
        let m = try await call("/tv/\(num)", ["append_to_response": "aggregate_credits,recommendations"])
        guard let r = showRef(m) else { throw CatalogError.http(404) }
        var d = FilmDetail(ref: r)
        d.tagline = m["tagline"].str
        d.overview = m["overview"].str
        // Shows rarely give a single runtime; take the usual episode length, else the latest episode's.
        d.runtimeMinutes = m["episode_run_time"].array.compactMap(\.int).first ?? m["last_episode_to_air"]["runtime"].int
        d.genres = m["genres"].array.compactMap { $0["name"].str?.replacingOccurrences(of: "Sci-Fi & Fantasy", with: "Sci-Fi") }
        d.creators = m["created_by"].array.compactMap { $0["name"].str }
        d.networks = m["networks"].array.compactMap { $0["name"].str }
        d.status = m["status"].str
        d.lastYear = m["last_air_date"].str.flatMap { Int($0.prefix(4)) }
        d.cast = m["aggregate_credits"]["cast"].array.prefix(30).compactMap { c in
            guard let pid = c["id"].int, let name = c["name"].str else { return nil }
            let role = c["roles"].array.first?["character"].str ?? ""
            return Person(id: "tmdbp-\(pid)", name: name, role: role, photo: img(c["profile_path"].str, "w185"))
        }
        d.communityRating = m["vote_average"].double
        d.voteCount = m["vote_count"].int
        d.countries = m["origin_country"].array.compactMap { $0.str.flatMap { Locale.current.localizedString(forRegionCode: $0) } }
        d.seasons = m["seasons"].array.compactMap { s in
            guard let n = s["season_number"].int else { return nil }
            return SeasonInfo(number: n, name: s["name"].str ?? "Season \(n)", episodeCount: s["episode_count"].int ?? 0,
                              year: s["air_date"].str.flatMap { Int($0.prefix(4)) }, poster: img(s["poster_path"].str, "w500"),
                              overview: s["overview"].str)
        }
        if !m["next_episode_to_air"].isNull { d.nextEpisode = episode(m["next_episode_to_air"], season: 0) }
        d.similar = m["recommendations"]["results"].array.compactMap(showRef).filter { $0.poster != nil }
        return d
    }

    static func season(_ showID: String, _ number: Int) async throws -> [Episode] {
        let num = showID.dropFirst(FilmRef.showPrefix.count)
        let j = try await call("/tv/\(num)/season/\(number)")
        return j["episodes"].array.compactMap { episode($0, season: number) }
    }
}
