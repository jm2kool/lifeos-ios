import Foundation
import SwiftUI

struct Toast: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var symbol: String
    var undo: Bool = false
}

/// Your films: diary, watchlist, likes, ratings, lists and profile. Saved on the phone,
/// and synced to your account when you're signed in.
@Observable @MainActor
final class Library {
    static let shared = Library()

    private(set) var doc = LibraryDoc()
    var toast: Toast?
    private var undoSnapshot: LibraryDoc?
    private var syncTask: Task<Void, Never>?

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Matinee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), var d = try? Self.decoder.decode(LibraryDoc.self, from: data) {
            let old = d.ratingScale == nil
            d.migrate()
            doc = d
            if old { persist(sync: false) }
        }
        WatchlistWidget.publish(doc.watchlist)
    }

    // MARK: Reading

    var entries: [LogEntry] { doc.entries.sorted { ($0.watchedOn, $0.createdAt) > ($1.watchedOn, $1.createdAt) } }
    func entries(for id: String) -> [LogEntry] { entries.filter { $0.film.id == id } }
    /// Episode and season entries don't make a show watched — finishing it (or marking it) does.
    func isWatched(_ id: String) -> Bool { doc.watched.contains { $0.id == id } || doc.entries.contains { $0.film.id == id && $0.season == nil } }
    func isLiked(_ id: String) -> Bool { doc.liked.contains { $0.id == id } }
    func inWatchlist(_ id: String) -> Bool { doc.watchlist.contains { $0.id == id } }
    func rating(_ id: String) -> Double? { doc.ratings[id] }
    /// Comfort films and shows get watched and logged, but never asked for a rating.
    func isComfort(_ id: String) -> Bool { doc.comfort?.contains(id) ?? false }
    var favoriteShows: [FilmRef] { doc.favoriteShows ?? [] }
    func favorites(shows: Bool) -> [FilmRef] { shows ? favoriteShows : doc.favorites }
    var currentlyWatching: [FilmRef] { doc.currentlyWatching ?? [] }
    func isCurrentlyWatching(_ id: String) -> Bool { currentlyWatching.contains { $0.id == id } }

    /// Every distinct film you've seen, newest first.
    var watchedFilms: [FilmRef] {
        var seen = Set<String>(), out: [FilmRef] = []
        for e in entries where e.season == nil && seen.insert(e.film.id).inserted { out.append(e.film) }
        for f in doc.watched.reversed() where seen.insert(f.id).inserted { out.append(f) }
        return out
    }

    var thisYearCount: Int { let y = Date.now.year; return doc.entries.filter { $0.watchedOn.year == y }.count }

    /// Scores (1–100) of films you've actually watched — the ones the ratings tracker can list.
    var watchedRatings: [Double] {
        let ids = Set(doc.watched.map(\.id) + doc.entries.map(\.film.id))
        return doc.ratings.filter { !FilmRef.isShowID($0.key) && ids.contains($0.key) && $0.value > 0 }.map(\.value)
    }

    /// How many films sit in each band of ten (index 0 = 1–10 … 9 = 91–100).
    var ratingHistogram: [Int] {
        var bins = Array(repeating: 0, count: 10)
        for r in watchedRatings { bins[Self.band(r)] += 1 }
        return bins
    }

    static func band(_ score: Double) -> Int { min(9, max(0, Int((score.rounded() - 1) / 10))) }

    var averageRating: Double? {
        let v = watchedRatings
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    var allTags: [String] { Array(Set(doc.entries.flatMap(\.tags))).sorted() }

    // MARK: Writing

    private func mutate(_ toastText: String? = nil, symbol: String = "checkmark", undoable: Bool = false, _ change: (inout LibraryDoc) -> Void) {
        if undoable { undoSnapshot = doc }
        var d = doc
        change(&d)
        d.updatedAt = .now
        withAnimation(.smooth) { doc = d }
        persist()
        if let toastText { toast = Toast(text: toastText, symbol: symbol, undo: undoable) }
    }

    func undo() {
        guard let s = undoSnapshot else { return }
        undoSnapshot = nil
        withAnimation(.smooth) { doc = s }
        persist()
        toast = Toast(text: "Undone", symbol: "arrow.uturn.backward")
    }

    func log(_ e: LogEntry) {
        mutate("Logged \(e.film.title)\(e.episodeLabel.map { " · \($0)" } ?? "")", symbol: "eye.fill") { d in
            if let i = d.entries.firstIndex(where: { $0.id == e.id }) { d.entries[i] = e } else { d.entries.append(e) }
            // An unrated comfort watch leaves any rating you gave before alone.
            let keepRating = (d.comfort ?? []).contains(e.film.id) && e.rating == nil
            if let s = e.season {
                // An episode or season of a show: it's seen, and the newest viewing sets its rating.
                let newest = d.entries.filter { $0.film.id == e.film.id && $0.season == e.season && $0.episode == e.episode }
                    .max { ($0.watchedOn, $0.createdAt) < ($1.watchedOn, $1.createdAt) }
                let r = e.rating.flatMap { $0 > 0 ? $0 : nil }
                Self.editShow(e.film, &d) { p in
                    if let n = e.episode {
                        let k = EpisodeKey.make(s, n)
                        if p.seen[k] == nil { p.seen[k] = e.watchedOn }
                        if newest?.id == e.id && !keepRating { p.episodeRatings[k] = r }
                    } else if newest?.id == e.id && !keepRating {
                        p.seasonRatings[String(s)] = r
                    }
                }
                d.watchlist.removeAll { $0.id == e.film.id }
                return
            }
            // The newest viewing sets the film's rating, so clearing the stars there clears it everywhere.
            let newest = d.entries.filter { $0.film.id == e.film.id }.max { ($0.watchedOn, $0.createdAt) < ($1.watchedOn, $1.createdAt) }
            if newest?.id == e.id && !keepRating { d.ratings[e.film.id] = e.rating.flatMap { $0 > 0 ? $0 : nil } }
            else if let r = e.rating, d.ratings[e.film.id] == nil { d.ratings[e.film.id] = r }
            if e.liked, !d.liked.contains(where: { $0.id == e.film.id }) { d.liked.append(e.film) }
            d.watchlist.removeAll { $0.id == e.film.id }
        }
    }

    func delete(_ e: LogEntry) {
        mutate("Entry deleted", symbol: "trash", undoable: true) { d in
            d.entries.removeAll { $0.id == e.id }
            // Deleting a diary entry doesn't un-watch the film (use Remove from watched for that).
            if e.season == nil, !d.entries.contains(where: { $0.film.id == e.film.id && $0.season == nil }) && !d.watched.contains(where: { $0.id == e.film.id }) {
                d.watched.append(e.film)
            }
        }
    }

    func toggleWatched(_ f: FilmRef) {
        if isWatched(f.id) {
            // Un-watching wipes everything that says you saw it: diary entries, the rating and the like.
            mutate("Removed from watched", symbol: "eye.slash", undoable: true) { d in
                d.watched.removeAll { $0.id == f.id }
                // For a show, episode logs and progress stay: you still saw those.
                d.entries.removeAll { $0.film.id == f.id && $0.season == nil }
                d.ratings[f.id] = nil
                d.liked.removeAll { $0.id == f.id }
            }
        } else {
            mutate("Marked as watched", symbol: "eye.fill") { d in
                d.watched.append(f)
                d.watchlist.removeAll { $0.id == f.id }
            }
        }
    }

    func toggleLike(_ f: FilmRef) {
        let on = !isLiked(f.id)
        mutate(on ? "Liked" : nil, symbol: "heart.fill") { d in
            if on { d.liked.append(f); if !d.watched.contains(where: { $0.id == f.id }) && !d.entries.contains(where: { $0.film.id == f.id }) { d.watched.append(f) } }
            else { d.liked.removeAll { $0.id == f.id } }
        }
    }

    func toggleWatchlist(_ f: FilmRef) {
        let on = !inWatchlist(f.id)
        mutate(on ? "Added to watchlist" : "Removed from watchlist", symbol: on ? "clock.fill" : "clock") { d in
            if on { d.watchlist.insert(f, at: 0) } else { d.watchlist.removeAll { $0.id == f.id } }
        }
    }

    /// Rating on its own never marks a film watched or touches the watchlist — a stray tap on the
    /// stars shouldn't change your history. Use Watched or Log for that.
    func rate(_ f: FilmRef, _ r: Double?) {
        mutate { d in
            if let r, r > 0 { d.ratings[f.id] = r } else { d.ratings[f.id] = nil }
        }
    }

    /// Four favourite films and four favourite shows; a show goes into the shows row.
    func setFavorite(_ f: FilmRef, slot: Int) {
        mutate("Added to favourites", symbol: "star.fill") { d in
            var list = f.isShow ? d.favoriteShows ?? [] : d.favorites
            list.removeAll { $0.id == f.id }
            if slot < list.count { list[slot] = f } else { list.append(f) }
            if f.isShow { d.favoriteShows = Array(list.prefix(4)) } else { d.favorites = Array(list.prefix(4)) }
        }
    }
    func removeFavorite(_ f: FilmRef) {
        mutate { d in
            if f.isShow { d.favoriteShows?.removeAll { $0.id == f.id } } else { d.favorites.removeAll { $0.id == f.id } }
        }
    }

    func toggleComfort(_ f: FilmRef) { setComfort(f, !isComfort(f.id)) }
    func setComfort(_ f: FilmRef, _ on: Bool) {
        guard on != isComfort(f.id) else { return }
        let kind = f.isShow ? "show" : "film"
        mutate(on ? "Comfort \(kind) — no ratings asked" : "No longer a comfort \(kind)", symbol: on ? "sofa.fill" : "sofa") { d in
            var ids = d.comfort ?? []
            if on { ids.append(f.id) } else { ids.removeAll { $0 == f.id } }
            d.comfort = ids
        }
    }

    @discardableResult
    func createList(_ name: String, note: String = "", ranked: Bool = false, with film: FilmRef? = nil) -> FilmList {
        var l = FilmList(name: name, note: note, ranked: ranked)
        if let film { l.films = [film] }
        mutate("Created “\(name)”", symbol: "list.bullet") { d in d.lists.insert(l, at: 0) }
        return l
    }
    func updateList(_ l: FilmList) {
        var l = l; l.updatedAt = .now
        mutate { d in if let i = d.lists.firstIndex(where: { $0.id == l.id }) { d.lists[i] = l } }
    }
    func deleteList(_ l: FilmList) { mutate("List deleted", symbol: "trash", undoable: true) { d in d.lists.removeAll { $0.id == l.id } } }
    func toggle(_ f: FilmRef, in list: FilmList) {
        mutate { d in
            guard let i = d.lists.firstIndex(where: { $0.id == list.id }) else { return }
            if d.lists[i].films.contains(where: { $0.id == f.id }) { d.lists[i].films.removeAll { $0.id == f.id } }
            else { d.lists[i].films.append(f) }
            d.lists[i].updatedAt = .now
        }
        let added = doc.lists.first { $0.id == list.id }?.films.contains { $0.id == f.id } ?? false
        toast = Toast(text: added ? "Added to \(list.name)" : "Removed from \(list.name)", symbol: "list.bullet")
    }

    // MARK: Shows

    func progress(_ showID: String) -> ShowProgress? { doc.shows?[showID] }
    func isSeen(_ showID: String, _ ep: Episode) -> Bool { doc.shows?[showID]?.seen[ep.id] != nil }
    func episodeRating(_ showID: String, _ ep: Episode) -> Double? { doc.shows?[showID]?.episodeRatings[ep.id] }
    func seasonRating(_ showID: String, _ season: Int) -> Double? { doc.shows?[showID]?.seasonRatings[String(season)] }
    func seenCount(_ showID: String, season: Int) -> Int { doc.shows?[showID]?.seenCount(season: season) ?? 0 }

    /// Shows you've started, most recently watched first. Finished shows drop off.
    var showsInProgress: [FilmRef] {
        let done = Set(doc.watched.map(\.id))
        return (doc.shows ?? [:]).values
            .filter { !$0.seen.isEmpty && !done.contains($0.show.id) }
            .sorted { ($0.seen.values.max() ?? .distantPast) > ($1.seen.values.max() ?? .distantPast) }
            .map(\.show)
    }

    func setSeen(_ show: FilmRef, _ eps: [Episode], _ on: Bool) {
        guard !eps.isEmpty else { return }
        let text = eps.count == 1 ? "\(on ? "Watched" : "Unwatched") \(eps[0].code)" : on ? "Marked \(eps.count) episodes watched" : "Unmarked \(eps.count) episodes"
        // Unmarking clears the episode's rating too, so it's undoable.
        mutate(text, symbol: on ? "checkmark.circle.fill" : "circle", undoable: !on) { d in
            Self.editShow(show, &d) { p in
                for e in eps {
                    if on { if p.seen[e.id] == nil { p.seen[e.id] = .now } } else { p.seen[e.id] = nil; p.episodeRatings[e.id] = nil }
                }
            }
            if on { d.watchlist.removeAll { $0.id == show.id } }
        }
    }

    func toggleSeen(_ show: FilmRef, _ ep: Episode) { setSeen(show, [ep], !isSeen(show.id, ep)) }

    /// Shows pinned to the top of Home, with the next episode ready to tick off and the last one to rate.
    func toggleCurrentlyWatching(_ show: FilmRef) {
        let on = !isCurrentlyWatching(show.id)
        mutate(on ? "Pinned to Currently watching" : "Removed from Currently watching", symbol: on ? "pin.fill" : "pin.slash") { d in
            var list = d.currentlyWatching ?? []
            if on { list.insert(show, at: 0) } else { list.removeAll { $0.id == show.id } }
            d.currentlyWatching = list
        }
    }

    /// Rating an episode counts as having watched it.
    func rateEpisode(_ show: FilmRef, _ ep: Episode, _ r: Double?) {
        mutate { d in
            Self.editShow(show, &d) { p in
                if let r, r > 0 {
                    p.episodeRatings[ep.id] = r
                    if p.seen[ep.id] == nil { p.seen[ep.id] = .now }
                } else {
                    p.episodeRatings[ep.id] = nil
                }
            }
            if let r, r > 0 { d.watchlist.removeAll { $0.id == show.id } }
        }
    }

    func rateSeason(_ show: FilmRef, _ season: Int, _ r: Double?) {
        mutate { d in Self.editShow(show, &d) { p in p.seasonRatings[String(season)] = r.flatMap { $0 > 0 ? $0 : nil } } }
    }

    /// After the last episode of a show that has ended: it joins your watched titles.
    func finishShow(_ show: FilmRef) {
        guard !doc.watched.contains(where: { $0.id == show.id }) else { return }
        mutate { d in
            d.watched.append(show)
            d.watchlist.removeAll { $0.id == show.id }
            d.currentlyWatching?.removeAll { $0.id == show.id }
        }
    }

    private static func editShow(_ show: FilmRef, _ d: inout LibraryDoc, _ change: (inout ShowProgress) -> Void) {
        var all = d.shows ?? [:]
        var p = all[show.id] ?? ShowProgress(show: show)
        if p.show.poster == nil { p.show = show }
        change(&p)
        p.updatedAt = .now
        all[show.id] = p.isEmpty ? nil : p
        d.shows = all
    }

    func setProfile(_ p: Profile) { mutate { d in d.profile = p } }

    /// Quiet batch changes (imports): no toast per film.
    func apply(_ change: (inout LibraryDoc) -> Void) { mutate(nil, change) }

    /// Films in progress ride along with the library so they sync to your account. Quiet: no toast,
    /// no undo, and the shared timestamp moves so the newest phone wins.
    func storeWatching(_ sessions: [WatchSession]) {
        guard sessions != (doc.watching ?? []) else { return }
        var d = doc
        d.watching = sessions
        d.updatedAt = .now
        doc = d
        persist()
    }

    /// Your film character rides along with the library so it syncs to your account.
    func storeTaste(_ t: TasteProfile) {
        var d = doc
        d.taste = t
        d.updatedAt = .now
        doc = d
        persist()
    }

    func rememberSearch(_ q: String) {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        mutate { d in d.recentSearches.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }; d.recentSearches.insert(q, at: 0); d.recentSearches = Array(d.recentSearches.prefix(8)) }
    }
    func clearSearches() { mutate { d in d.recentSearches = [] } }

    /// Fill in a poster for films saved without one (e.g. imported or seeded entries).
    func hydrate(_ f: FilmRef, with detail: FilmDetail) {
        guard f.poster == nil, detail.ref.poster != nil else { return }
        let r = detail.ref
        func fix(_ x: inout FilmRef) { if x.id == r.id { x.poster = r.poster; x.backdrop = r.backdrop; x.year = x.year ?? r.year } }
        var d = doc
        for i in d.entries.indices { fix(&d.entries[i].film) }
        for i in d.watchlist.indices { fix(&d.watchlist[i]) }
        for i in d.liked.indices { fix(&d.liked[i]) }
        for i in d.watched.indices { fix(&d.watched[i]) }
        for i in d.favorites.indices { fix(&d.favorites[i]) }
        if var l = d.favoriteShows { for i in l.indices { fix(&l[i]) }; d.favoriteShows = l }
        if var l = d.currentlyWatching { for i in l.indices { fix(&l[i]) }; d.currentlyWatching = l }
        for l in d.lists.indices { for i in d.lists[l].films.indices { fix(&d.lists[l].films[i]) } }
        if var shows = d.shows, shows[r.id] != nil { fix(&shows[r.id]!.show); d.shows = shows }
        doc = d
        persist(sync: false)
    }

    func eraseAll() { mutate("Library cleared", symbol: "trash", undoable: true) { d in let p = d.profile; d = LibraryDoc(); d.profile = p } }

    // MARK: Persistence & sync

    private func persist(sync: Bool = true) {
        WatchlistWidget.publish(doc.watchlist)
        let data = try? Self.encoder.encode(doc)
        if let data { try? data.write(to: Self.fileURL, options: .atomic) }
        guard sync, Auth.shared.signedIn, let data else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await Auth.shared.pushLibrary(data)
            await publishProfile()
        }
    }

    /// Your public profile (name, photo, favourites, Currently watching) for everyone to see.
    /// Sent only when one of those changed.
    func publishProfile() async {
        guard let id = Auth.shared.session?.userID else { return }
        if await Auth.shared.pushProfile(PublicProfile.mine(self, userID: id)) == .handleTaken {
            toast = Toast(text: "@\(Handle.clean(doc.profile.handle) ?? "") is taken — pick another username", symbol: "at")
        }
    }

    @ObservationIgnored private var reconciling = false

    /// Take whichever copy (phone or account) was changed most recently. Runs after signing in, at launch
    /// and whenever the app comes back, so changes from another phone arrive and a push that failed
    /// (offline, app closed too soon) gets another go.
    func reconcileWithCloud() async {
        guard Auth.shared.signedIn, !reconciling else { return }
        reconciling = true
        defer { reconciling = false }
        defer { Task { await publishProfile() } }
        if let data = await Auth.shared.pullLibrary(), var remote = try? Self.decoder.decode(LibraryDoc.self, from: data) {
            remote.migrate()
            // Saved dates keep whole seconds only, so a copy within a second of this one is the same copy.
            if abs(remote.updatedAt.timeIntervalSince(doc.updatedAt)) < 1 { return }
            if remote.updatedAt > doc.updatedAt || doc.entries.isEmpty && doc.watchlist.isEmpty {
                var r = remote
                if r.taste == nil { r.taste = doc.taste }
                doc = r
                persist(sync: false)
                if let t = r.taste { Taste.shared.adopt(t) }
                if let w = r.watching { Watching.shared.adopt(w) }
                return
            }
        }
        if let data = try? Self.encoder.encode(doc) { await Auth.shared.pushLibrary(data) }
    }

    func adoptAccountProfile() {
        guard let s = Auth.shared.session else { return }
        var p = doc.profile
        if p.name.isEmpty { p.name = s.name ?? s.email?.components(separatedBy: "@").first ?? "" }
        if p.avatar == nil { p.avatar = s.avatar }
        if p.handle.isEmpty, let n = s.email?.components(separatedBy: "@").first { p.handle = n.lowercased() }
        if p != doc.profile { setProfile(p) }
    }

    // MARK: Demo data for simulator previews

    func seedDemo() {
        let cal = Calendar.current
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: .now)! }
        let films: [(String, String, Int)] = [
            ("tmdb-693134", "Dune: Part Two", 2024), ("tmdb-872585", "Oppenheimer", 2023), ("tmdb-496243", "Parasite", 2019),
            ("tmdb-27205", "Inception", 2010), ("tmdb-157336", "Interstellar", 2014), ("tmdb-680", "Pulp Fiction", 1994),
            ("tmdb-238", "The Godfather", 1972), ("tmdb-569094", "Spider-Man: Across the Spider-Verse", 2023),
            ("tmdb-438631", "Dune", 2021), ("tmdb-129", "Spirited Away", 2001), ("tmdb-475557", "Joker", 2019),
            ("tmdb-550", "Fight Club", 1999)]
        let refs = films.map { FilmRef(id: $0.0, title: $0.1, year: $0.2) }
        var d = LibraryDoc()
        let ratings: [Double] = [97, 91, 95, 82, 89, 78, 99, 88, 71, 94]
        for (i, f) in refs.prefix(10).enumerated() {
            d.entries.append(LogEntry(film: f, watchedOn: day(i * 4 + 1), rating: ratings[i], liked: ratings[i] >= 88,
                                      rewatch: i == 3, review: i == 0 ? "Sand has never looked this good. Saw it in IMAX and my ears are still ringing." : "",
                                      tags: i % 3 == 0 ? ["imax"] : []))
            d.ratings[f.id] = ratings[i]
            if ratings[i] >= 88 { d.liked.append(f) }
        }
        d.ratingScale = 100
        // A show partway through: all of season 1 rated, two episodes into season 2.
        let show = FilmRef(id: "tmdbtv-1396", title: "Breaking Bad", year: 2008)
        var p = ShowProgress(show: show)
        let s1: [Double] = [90, 80, 82, 70, 84, 91, 100]
        for (i, r) in s1.enumerated() { p.seen[EpisodeKey.make(1, i + 1)] = day(30 - i); p.episodeRatings[EpisodeKey.make(1, i + 1)] = r }
        p.seasonRatings["1"] = 92
        p.seen[EpisodeKey.make(2, 1)] = day(3); p.seen[EpisodeKey.make(2, 2)] = day(2)
        p.episodeRatings[EpisodeKey.make(2, 1)] = 85
        d.shows = [show.id: p]
        d.currentlyWatching = [show]
        d.favoriteShows = [show]
        d.watchlist = [refs[10], refs[11]]
        d.favorites = [refs[2], refs[0], refs[6], refs[9]]
        d.lists = [FilmList(name: "Desert planets & big sound", note: "Films to feel in your chest.", ranked: true, films: [refs[0], refs[8], refs[4], refs[3]])]
        d.profile = Profile(name: "Alex Rivera", handle: "alex", bio: "Film nights every Friday.")
        doc = d
        persist(sync: false)
    }
}
