import Foundation

/// Brings over a Letterboxd export (Settings → Import & Export on letterboxd.com gives a ZIP of CSVs).
/// Each film is matched against the catalog by title and year.
@Observable @MainActor
final class Importer {
    var running = false
    var done = 0
    var total = 0
    var unmatched: [String] = []
    var summary: String?

    struct Row { var name: String; var year: Int?; var date: Date?; var rating: Double?; var rewatch = false; var review = ""; var tags: [String] = []; var kind: Kind }
    enum Kind { case diary, watched, watchlist, ratings, likes, reviews }

    func run(_ urls: [URL], into library: Library, forceKind: Kind? = nil) async {
        running = true; done = 0; unmatched = []; summary = nil
        defer { running = false }
        var rows: [Row] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            let kind: Kind = forceKind ?? (name.contains("diary") ? .diary : name.contains("watchlist") ? .watchlist : name.contains("rating") ? .ratings
                : name.contains("like") ? .likes : name.contains("review") ? .reviews : .watched)
            rows += parse(text, kind: kind)
        }
        total = rows.count
        // Match each distinct title once, a few at a time.
        var resolved: [String: FilmRef] = [:]
        var distinct: [Row] = []
        var seenKeys = Set<String>()
        for r in rows where seenKeys.insert(importKey(r)).inserted { distinct.append(r) }
        total = distinct.count
        for start in stride(from: 0, to: distinct.count, by: 6) {
            let chunk = Array(distinct[start..<min(start + 6, distinct.count)])
            await withTaskGroup(of: (String, FilmRef?).self) { g in
                for r in chunk {
                    g.addTask {
                        guard let hits = try? await Catalog.search(r.name) else { return (importKey(r), nil) }
                        let f = hits.first { $0.year == r.year } ?? hits.first { abs(($0.year ?? 0) - (r.year ?? 0)) <= 1 } ?? (r.year == nil ? hits.first : nil)
                        return (importKey(r), f)
                    }
                }
                for await (k, f) in g { if let f { resolved[k] = f } }
            }
            done = start + chunk.count
        }
        var entries: [LogEntry] = []
        var unmatchedKeys = Set<String>()
        library.apply { d in
            for r in rows {
                guard let f = resolved[importKey(r)] else {
                    if unmatchedKeys.insert(importKey(r)).inserted { unmatched.append("\(r.name) (\(r.year.map(String.init) ?? "?"))") }
                    continue
                }
                let watched = d.watched.contains { $0.id == f.id } || d.entries.contains { $0.film.id == f.id }
                switch r.kind {
                case .diary, .reviews:
                    entries.append(LogEntry(film: f, watchedOn: r.date ?? .now, rating: r.rating, liked: false, rewatch: r.rewatch, review: r.review, tags: r.tags))
                case .watched:
                    if !watched { d.watched.append(f) }
                    d.watchlist.removeAll { $0.id == f.id }
                case .watchlist:
                    if !watched && !d.watchlist.contains(where: { $0.id == f.id }) { d.watchlist.append(f) }
                case .ratings:
                    // On Letterboxd a rating means you've seen it, so it lands in your films and ratings tracker.
                    if let rt = r.rating, rt > 0 { d.ratings[f.id] = rt }
                    if !watched { d.watched.append(f) }
                    d.watchlist.removeAll { $0.id == f.id }
                case .likes:
                    if !d.liked.contains(where: { $0.id == f.id }) { d.liked.append(f) }
                    if !watched { d.watched.append(f) }
                }
            }
        }
        done = total
        // Reviews and diary rows describe the same viewing; keep one per film+date, preferring the one with text.
        var byKey: [String: LogEntry] = [:]
        for e in entries {
            let k = "\(e.film.id)|\(Calendar.current.startOfDay(for: e.watchedOn).timeIntervalSince1970)"
            if let old = byKey[k], old.review.count >= e.review.count { continue }
            byKey[k] = e
        }
        // Add diary entries in one go (no toast per film); the newest viewing sets each film's rating.
        library.apply { d in
            for e in byKey.values.sorted(by: { $0.watchedOn < $1.watchedOn })
            where !d.entries.contains(where: { $0.film.id == e.film.id && Calendar.current.isDate($0.watchedOn, inSameDayAs: e.watchedOn) }) {
                d.entries.append(e)
                if let r = e.rating, r > 0 { d.ratings[e.film.id] = r }
                d.watchlist.removeAll { $0.id == e.film.id }
            }
        }
        library.toast = Toast(text: "Imported \(total - unmatched.count) of \(total) films", symbol: "square.and.arrow.down")
        summary = "Matched \(total - unmatched.count) of \(total) films." + (unmatched.isEmpty ? "" : " \(unmatched.count) couldn't be matched.")
    }

    private func parse(_ text: String, kind: Kind) -> [Row] {
        let table = CSV.parse(text)
        guard let header = table.first?.map({ $0.lowercased() }) else { return [] }
        func col(_ n: String) -> Int? { header.firstIndex(of: n) }
        let iName = col("name"), iYear = col("year"), iDate = col("watched date") ?? col("date"), iRating = col("rating"),
            iRewatch = col("rewatch"), iReview = col("review"), iTags = col("tags")
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.locale = Locale(identifier: "en_US_POSIX")
        return table.dropFirst().compactMap { cells in
            func v(_ i: Int?) -> String { guard let i, i < cells.count else { return "" }; return cells[i] }
            let name = v(iName)
            guard !name.isEmpty else { return nil }
            return Row(name: name, year: Int(v(iYear)), date: df.date(from: v(iDate)), rating: Double(v(iRating)),
                       rewatch: v(iRewatch).lowercased() == "yes", review: v(iReview),
                       tags: v(iTags).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty },
                       kind: kind)
        }
    }
}

/// One film per title + year, however many CSV rows mention it.
private func importKey(_ r: Importer.Row) -> String { "\(r.name.lowercased())|\(r.year ?? 0)" }

enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var it = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { field.append("\"") } else { quoted = false; pending = n } } else { quoted = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
