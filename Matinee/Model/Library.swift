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
        if let data = try? Data(contentsOf: Self.fileURL), let d = try? Self.decoder.decode(LibraryDoc.self, from: data) { doc = d }
    }

    // MARK: Reading

    var entries: [LogEntry] { doc.entries.sorted { ($0.watchedOn, $0.createdAt) > ($1.watchedOn, $1.createdAt) } }
    func entries(for id: String) -> [LogEntry] { entries.filter { $0.film.id == id } }
    func isWatched(_ id: String) -> Bool { doc.watched.contains { $0.id == id } || doc.entries.contains { $0.film.id == id } }
    func isLiked(_ id: String) -> Bool { doc.liked.contains { $0.id == id } }
    func inWatchlist(_ id: String) -> Bool { doc.watchlist.contains { $0.id == id } }
    func rating(_ id: String) -> Double? { doc.ratings[id] }

    /// Every distinct film you've seen, newest first.
    var watchedFilms: [FilmRef] {
        var seen = Set<String>(), out: [FilmRef] = []
        for e in entries where seen.insert(e.film.id).inserted { out.append(e.film) }
        for f in doc.watched.reversed() where seen.insert(f.id).inserted { out.append(f) }
        return out
    }

    var thisYearCount: Int { let y = Date.now.year; return doc.entries.filter { $0.watchedOn.year == y }.count }

    /// How many films sit at each half-star (index 0 = ½ … 9 = 5★).
    var ratingHistogram: [Int] {
        var bins = Array(repeating: 0, count: 10)
        for r in doc.ratings.values { let i = Int((r * 2).rounded()) - 1; if (0..<10).contains(i) { bins[i] += 1 } }
        return bins
    }

    var averageRating: Double? {
        let v = doc.ratings.values
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
        mutate("Logged \(e.film.title)", symbol: "eye.fill") { d in
            if let i = d.entries.firstIndex(where: { $0.id == e.id }) { d.entries[i] = e } else { d.entries.append(e) }
            if let r = e.rating { d.ratings[e.film.id] = r }
            if e.liked, !d.liked.contains(where: { $0.id == e.film.id }) { d.liked.append(e.film) }
            d.watchlist.removeAll { $0.id == e.film.id }
        }
    }

    func delete(_ e: LogEntry) {
        mutate("Entry deleted", symbol: "trash", undoable: true) { d in d.entries.removeAll { $0.id == e.id } }
    }

    func toggleWatched(_ f: FilmRef) {
        if isWatched(f.id) {
            mutate("Removed from watched", symbol: "eye.slash", undoable: true) { d in
                d.watched.removeAll { $0.id == f.id }
                d.entries.removeAll { $0.film.id == f.id }
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

    func setFavorite(_ f: FilmRef, slot: Int) {
        mutate("Added to favourites", symbol: "star.fill") { d in
            d.favorites.removeAll { $0.id == f.id }
            if slot < d.favorites.count { d.favorites[slot] = f } else { d.favorites.append(f) }
            d.favorites = Array(d.favorites.prefix(4))
        }
    }
    func removeFavorite(_ f: FilmRef) { mutate { d in d.favorites.removeAll { $0.id == f.id } } }
    func moveFavorites(from: IndexSet, to: Int) { mutate { d in d.favorites.move(fromOffsets: from, toOffset: to) } }

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

    func setProfile(_ p: Profile) { mutate { d in d.profile = p } }

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
        for l in d.lists.indices { for i in d.lists[l].films.indices { fix(&d.lists[l].films[i]) } }
        doc = d
        persist(sync: false)
    }

    func eraseAll() { mutate("Library cleared", symbol: "trash", undoable: true) { d in let p = d.profile; d = LibraryDoc(); d.profile = p } }

    // MARK: Persistence & sync

    private func persist(sync: Bool = true) {
        let data = try? Self.encoder.encode(doc)
        if let data { try? data.write(to: Self.fileURL, options: .atomic) }
        guard sync, Auth.shared.signedIn, let data else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await Auth.shared.pushLibrary(data)
        }
    }

    /// After signing in: take whichever copy (phone or account) was changed most recently.
    func reconcileWithCloud() async {
        guard Auth.shared.signedIn else { return }
        if let data = await Auth.shared.pullLibrary(), let remote = try? Self.decoder.decode(LibraryDoc.self, from: data) {
            if remote.updatedAt > doc.updatedAt || doc.entries.isEmpty && doc.watchlist.isEmpty {
                doc = remote
                persist(sync: false)
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
        let ratings: [Double] = [5, 4.5, 5, 4, 4.5, 4, 5, 4.5, 3.5, 5]
        for (i, f) in refs.prefix(10).enumerated() {
            d.entries.append(LogEntry(film: f, watchedOn: day(i * 4 + 1), rating: ratings[i], liked: ratings[i] >= 4.5,
                                      rewatch: i == 3, review: i == 0 ? "Sand has never looked this good. Saw it in IMAX and my ears are still ringing." : "",
                                      tags: i % 3 == 0 ? ["imax"] : []))
            d.ratings[f.id] = ratings[i]
            if ratings[i] >= 4.5 { d.liked.append(f) }
        }
        d.watchlist = [refs[10], refs[11]]
        d.favorites = [refs[2], refs[0], refs[6], refs[9]]
        d.lists = [FilmList(name: "Desert planets & big sound", note: "Films to feel in your chest.", ranked: true, films: [refs[0], refs[8], refs[4], refs[3]])]
        d.profile = Profile(name: "Alex Rivera", handle: "alex", bio: "Film nights every Friday.")
        doc = d
        persist(sync: false)
    }
}
