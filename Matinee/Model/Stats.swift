import Foundation

/// One bar in a chart: a genre, a decade, a director… and how many films.
struct Tally: Identifiable, Hashable {
    var name: String
    var count: Int
    var person: Person? = nil
    var id: String { person?.id ?? name }
}

private func tally(_ names: [String], top: Int) -> [Tally] {
    var counts: [String: Int] = [:]
    for n in names where !n.isEmpty { counts[n, default: 0] += 1 }
    return counts.map { Tally(name: $0.key, count: $0.value) }
        .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        .prefix(top).map { $0 }
}

private func tallyPeople(_ people: [Person], top: Int) -> [Tally] {
    var counts: [String: (Person, Int)] = [:]
    for p in people { counts[p.id, default: (p, 0)].1 += 1 }
    return counts.values.map { Tally(name: $0.0.name, count: $0.1, person: $0.0) }
        .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        .prefix(top).map { $0 }
}

/// Everything on the Stats page, worked out from your films and what Matinee knows about them.
struct LibraryStats {
    var films: [FilmRef]
    var known: Int                     // how many of them have facts yet
    var minutes: Int
    var genres: [Tally]
    var decades: [Tally]
    var countries: [Tally]
    var directors: [Tally]
    var actors: [Tally]
    var episodes: Int
    var showsFinished: Int

    @MainActor init(_ library: Library, facts: FactStore) {
        let films = library.watchedFilms.filter { !$0.isShow }
        self.films = films
        let f = films.compactMap { facts[$0.id] }
        known = f.count
        // Each viewing counts toward time watched, rewatches included.
        let viewings = library.doc.entries.filter { !$0.film.isShow }
        let viewed = Set(viewings.map(\.film.id))
        var minutes = viewings.reduce(0) { $0 + (facts[$1.film.id]?.runtime ?? 0) }
            + films.filter { !viewed.contains($0.id) }.reduce(0) { $0 + (facts[$1.id]?.runtime ?? 0) }
        genres = tally(f.flatMap(\.genres), top: 10)
        decades = tally(films.compactMap { ($0.year ?? facts[$0.id]?.year).map { "\($0 / 10 * 10)s" } }, top: 12)
            .sorted { $0.name < $1.name }
        countries = tally(f.flatMap { $0.countries.prefix(1) }, top: 8)
        directors = tallyPeople(f.flatMap(\.directors), top: 10)
        actors = tallyPeople(f.flatMap { $0.cast.prefix(5) }, top: 12)
        let shows = (library.doc.shows ?? [:]).values
        episodes = shows.reduce(0) { $0 + $1.seen.count }
        showsFinished = library.watchedFilms.filter(\.isShow).count
        minutes += shows.reduce(0) { $0 + $1.seen.count * (facts[$1.show.id]?.runtime ?? 0) }
        self.minutes = minutes
    }
}

/// Your year in film, for Year in Review.
struct YearReview {
    let year: Int
    var entries: [LogEntry]            // films (not shows) logged that year, oldest first
    var filmCount: Int                 // distinct films
    var minutes: Int
    var episodes: Int
    var topRated: [(film: FilmRef, score: Double)]
    var months: [Int]                  // 12 counts
    var tags: [Tally]
    var rewatches: Int
    var liked: Int
    var average: Double?
    var weekday: (name: String, count: Int)?
    var streak: Int                    // most days in a row with a film
    var genres: [Tally]
    var director: Tally?
    var topShows: [(show: FilmRef, episodes: Int)]
    var first: LogEntry? { entries.first }
    var last: LogEntry? { entries.last }

    var busiestMonth: (name: String, count: Int)? {
        guard let i = months.indices.max(by: { months[$0] < months[$1] }), months[i] > 0 else { return nil }
        return (Calendar.current.monthSymbols[i], months[i])
    }

    @MainActor init(year: Int, library: Library, facts: FactStore) {
        self.year = year
        let cal = Calendar.current
        // A local copy, so the closures below don't capture self before it's fully set up.
        let entries = library.doc.entries.filter { $0.watchedOn.year == year && !$0.film.isShow }
            .sorted { ($0.watchedOn, $0.createdAt) < ($1.watchedOn, $1.createdAt) }
        self.entries = entries
        filmCount = Set(entries.map(\.film.id)).count
        var best: [String: (FilmRef, Double)] = [:]
        for e in entries { if let r = e.rating, r > (best[e.film.id]?.1 ?? 0) { best[e.film.id] = (e.film, r) } }
        topRated = best.values.sorted { $0.1 > $1.1 }.prefix(5).map { (film: $0.0, score: $0.1) }
        months = (1...12).map { m in entries.filter { cal.component(.month, from: $0.watchedOn) == m }.count }
        tags = tally(entries.flatMap(\.tags), top: 5)
        rewatches = entries.filter(\.rewatch).count
        liked = entries.filter(\.liked).count
        let scores = entries.compactMap(\.rating).filter { $0 > 0 }
        average = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let days = entries.map { cal.component(.weekday, from: $0.watchedOn) }
        if let top = tally(days.map(String.init), top: 1).first, let d = Int(top.name) {
            weekday = (cal.weekdaySymbols[d - 1], top.count)
        } else { weekday = nil }
        // Longest run of consecutive days with something logged.
        let uniqueDays = Set(entries.map { cal.startOfDay(for: $0.watchedOn) }).sorted()
        var run = 0, longest = 0
        var prev: Date?
        for d in uniqueDays {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = d
        }
        streak = longest
        let f = entries.compactMap { facts[$0.film.id] }
        genres = tally(f.flatMap(\.genres), top: 5)
        director = tallyPeople(f.flatMap(\.directors), top: 1).first.flatMap { $0.count > 1 ? $0 : nil }
        // Episodes count when you ticked them off.
        var perShow: [(show: FilmRef, episodes: Int)] = []
        var eps = 0
        var showMinutes = 0
        for p in (library.doc.shows ?? [:]).values {
            let n = p.seen.values.filter { $0.year == year }.count
            guard n > 0 else { continue }
            eps += n
            showMinutes += n * (facts[p.show.id]?.runtime ?? 0)
            perShow.append((p.show, n))
        }
        episodes = eps
        topShows = perShow.sorted { $0.episodes > $1.episodes }.prefix(3).map { $0 }
        minutes = entries.reduce(0) { $0 + (facts[$1.film.id]?.runtime ?? 0) } + showMinutes
    }

    /// A few plain facts, for the on-device model to write a summary from.
    var factSheet: String {
        var lines = ["Year: \(year)", "Films watched: \(filmCount) (\(entries.count) viewings, \(rewatches) rewatches)"]
        if minutes > 0 { lines.append("Hours watched: \(minutes / 60)") }
        if episodes > 0 { lines.append("TV episodes: \(episodes)") }
        if !topRated.isEmpty { lines.append("Highest rated: " + topRated.prefix(3).map { "\($0.film.title) (\(Int($0.score))/100)" }.joined(separator: ", ")) }
        if !genres.isEmpty { lines.append("Top genres: " + genres.prefix(3).map(\.name).joined(separator: ", ")) }
        if let d = director { lines.append("Most-watched director: \(d.name) (\(d.count) films)") }
        if let m = busiestMonth { lines.append("Busiest month: \(m.name) (\(m.count) films)") }
        if let w = weekday { lines.append("Favourite night: \(w.name)") }
        if streak > 2 { lines.append("Longest streak: \(streak) days in a row") }
        if let s = topShows.first { lines.append("Most-watched show: \(s.show.title) (\(s.episodes) episodes)") }
        if let f = first { lines.append("First film of the year: \(f.film.title)") }
        return lines.joined(separator: "\n")
    }
}
