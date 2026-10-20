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
    case http(Int), offline
    var errorDescription: String? {
        switch self {
        case .http(let c): return "The film database answered with error \(c)."
        case .offline: return "Couldn't reach the film database."
        }
    }
}

enum HomeShelf: String, CaseIterable, Identifiable {
    case trending, topRated, newReleases
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trending: return "Popular this week"
        case .topRated: return "All-time greats"
        case .newReleases: return "New & noteworthy"
        }
    }
}

/// Film data. With a TMDB token it uses TMDB (richer: backdrops, trending, recommendations);
/// otherwise it uses the free, keyless imdbapi.dev catalog so the app works out of the box.
@MainActor
enum Catalog {
    static var tmdbToken: String {
        let saved = UserDefaults.standard.string(forKey: "tmdbToken") ?? ""
        if !saved.isEmpty { return saved }
        return (Bundle.main.object(forInfoDictionaryKey: "MatineeTMDBToken") as? String) ?? ""
    }
    static var usingTMDB: Bool { !tmdbToken.trimmingCharacters(in: .whitespaces).isEmpty }

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
        let key = "\(usingTMDB)-\(s.rawValue)"
        if let hit = shelfCache[key] { return hit }
        let films = usingTMDB ? try await TMDB.shelf(s) : try await IMDb.shelf(s)
        if !films.isEmpty { shelfCache[key] = films }
        return films
    }

    static func search(_ q: String) async throws -> [FilmRef] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return usingTMDB ? try await TMDB.search(q) : try await IMDb.search(q)
    }

    static func genre(_ g: String) async throws -> [FilmRef] {
        let key = "\(usingTMDB)-genre-\(g)"
        if let hit = shelfCache[key] { return hit }
        let films = usingTMDB ? try await TMDB.genre(g) : try await IMDb.genre(g)
        if !films.isEmpty { shelfCache[key] = films }
        return films
    }

    static func detail(_ id: String) async throws -> FilmDetail {
        if let hit = detailCache[id] { return hit }
        let d = id.hasPrefix("tmdb-") ? try await TMDB.detail(id) : try await IMDb.detail(id)
        detailCache[id] = d
        return d
    }

    static func cached(_ id: String) -> FilmDetail? { detailCache[id] }

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

// MARK: - imdbapi.dev (free, no key)

@MainActor
enum IMDb {
    static let base = "https://api.imdbapi.dev"

    /// Amazon image URLs can be resized by editing the `._V1_` marker.
    static func image(_ s: String?, width: Int) -> URL? {
        guard let s, !s.isEmpty else { return nil }
        if let r = s.range(of: "._V1_") {
            let head = s[..<r.lowerBound]
            return URL(string: "\(head)._V1_QL80_UX\(width)_.jpg")
        }
        return URL(string: s)
    }

    static func isFilm(_ t: J) -> Bool {
        guard let type = t["type"].str?.lowercased() else { return true }
        return type.contains("movie") && !type.contains("tv")
    }

    static func ref(_ t: J) -> FilmRef? {
        guard let id = t["id"].str, let title = t["primaryTitle"].str ?? t["originalTitle"].str else { return nil }
        let img = t["primaryImage"]["url"].str
        return FilmRef(id: id, title: title, year: t["startYear"].int,
                       poster: image(img, width: 500), backdrop: image(img, width: 1200))
    }

    static func titles(_ q: [String: String]) async throws -> [FilmRef] {
        var q = q
        q["types"] = "MOVIE"
        let j = try await Catalog.get(Catalog.url(base, "/titles", q))
        return j["titles"].array.filter(isFilm).compactMap(ref).filter { $0.poster != nil }
    }

    static func shelf(_ s: HomeShelf) async throws -> [FilmRef] {
        let y = Date.now.year
        switch s {
        case .trending:
            return try await titles(["sortBy": "SORT_BY_POPULARITY", "sortOrder": "ASC", "minVoteCount": "20000", "startYear": String(y - 3)])
        case .topRated:
            return try await titles(["sortBy": "SORT_BY_USER_RATING", "sortOrder": "DESC", "minVoteCount": "300000"])
        case .newReleases:
            return try await titles(["sortBy": "SORT_BY_POPULARITY", "sortOrder": "ASC", "minVoteCount": "2000", "startYear": String(y)])
        }
    }

    static func genre(_ g: String) async throws -> [FilmRef] {
        try await titles(["genres": g, "sortBy": "SORT_BY_POPULARITY", "sortOrder": "ASC", "minVoteCount": "50000"])
    }

    static func search(_ q: String) async throws -> [FilmRef] {
        let j = try await Catalog.get(Catalog.url(base, "/search/titles", ["query": q, "limit": "40"]))
        return j["titles"].array.filter(isFilm).compactMap(ref)
    }

    static func detail(_ id: String) async throws -> FilmDetail {
        let t = try await Catalog.get(Catalog.url(base, "/titles/\(id)"))
        guard let r = ref(t) else { throw CatalogError.http(404) }
        var d = FilmDetail(ref: r)
        d.overview = t["plot"].str
        d.runtimeMinutes = t["runtimeSeconds"].int.map { $0 / 60 }
        d.genres = t["genres"].array.compactMap(\.str)
        d.directors = t["directors"].array.compactMap { $0["displayName"].str }
        d.communityRating = t["rating"]["aggregateRating"].double
        d.voteCount = t["rating"]["voteCount"].int
        d.countries = t["originCountries"].array.compactMap { $0["name"].str }
        d.cast = t["stars"].array.compactMap(person)

        // Fuller cast list and some similar films — both optional.
        let firstGenre = d.genres.first
        async let creditsJ = try? Catalog.get(Catalog.url(base, "/titles/\(id)/credits", ["pageSize": "30"]))
        async let similarF = similar(to: firstGenre)
        if let c = await creditsJ {
            let actors = c["credits"].array.filter {
                let cat = ($0["category"].str ?? "").lowercased()
                return cat.contains("actor") || cat.contains("actress") || cat.contains("self")
            }.compactMap { cr -> Person? in
                guard var p = person(cr["name"]) else { return nil }
                p.role = cr["characters"].array.compactMap(\.str).first ?? ""
                return p
            }
            if !actors.isEmpty { d.cast = actors }
        }
        let sim = await similarF
        d.similar = Array(sim.filter { $0.id != id }.prefix(15))
        return d
    }

    static func similar(to genre: String?) async -> [FilmRef] {
        guard let genre else { return [] }
        return (try? await self.genre(genre)) ?? []
    }

    static func person(_ n: J) -> Person? {
        guard let id = n["id"].str, let name = n["displayName"].str else { return nil }
        return Person(id: id, name: name, role: "", photo: image(n["primaryImage"]["url"].str, width: 200))
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
        var q = q
        q["language"] = "en-US"
        if token.count > 40 {
            return try await Catalog.get(Catalog.url(base, path, q), headers: ["Authorization": "Bearer \(token)"])
        }
        q["api_key"] = token
        return try await Catalog.get(Catalog.url(base, path, q))
    }

    static func ref(_ m: J) -> FilmRef? {
        guard let id = m["id"].int, let title = m["title"].str ?? m["original_title"].str else { return nil }
        let year = m["release_date"].str.flatMap { Int($0.prefix(4)) }
        return FilmRef(id: "tmdb-\(id)", title: title, year: year,
                       poster: img(m["poster_path"].str, "w500"), backdrop: img(m["backdrop_path"].str, "w1280"))
    }

    static func list(_ path: String, _ q: [String: String] = [:]) async throws -> [FilmRef] {
        try await call(path, q)["results"].array.compactMap(ref).filter { $0.poster != nil }
    }

    static func shelf(_ s: HomeShelf) async throws -> [FilmRef] {
        switch s {
        case .trending: return try await list("/trending/movie/week")
        case .topRated: return try await list("/movie/top_rated")
        case .newReleases: return try await list("/movie/now_playing")
        }
    }

    static func genre(_ g: String) async throws -> [FilmRef] {
        try await list("/discover/movie", ["with_genres": String(genreIDs[g] ?? 18), "sort_by": "popularity.desc", "vote_count.gte": "300"])
    }

    static func search(_ q: String) async throws -> [FilmRef] {
        try await call("/search/movie", ["query": q, "include_adult": "false"])["results"].array.compactMap(ref)
    }

    static func detail(_ id: String) async throws -> FilmDetail {
        let num = id.replacingOccurrences(of: "tmdb-", with: "")
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
}
