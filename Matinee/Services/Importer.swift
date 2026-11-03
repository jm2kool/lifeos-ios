import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
            guard var text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { continue }
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            let kind: Kind = forceKind ?? (name.contains("diary") ? .diary : name.contains("watchlist") ? .watchlist : name.contains("rating") ? .ratings
                : name.contains("like") ? .likes : name.contains("review") ? .reviews : .watched)
            rows += parse(text, kind: kind)
        }
        total = rows.count
        guard total > 0 else {
            summary = "Couldn't find any films in that file. Pick a Letterboxd CSV such as ratings.csv."
            library.toast = Toast(text: "Nothing to import", symbol: "exclamationmark.triangle")
            return
        }
        library.toast = Toast(text: "Importing \(total) films…", symbol: "square.and.arrow.down")
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
                        // Letterboxd is films only, so search films (never a show with the same name), in the right year.
                        guard let hits = try? await Catalog.searchMovies(r.name, year: r.year) else { return (importKey(r), nil) }
                        return (importKey(r), Importer.best(hits, for: r))
                    }
                }
                for await (k, f) in g { if let f { resolved[k] = f } }
            }
            done = start + chunk.count
        }
        var entries: [LogEntry] = []
        var unmatchedKeys = Set<String>()
        library.apply { d in
            // Sets, so a history of thousands of films imports in a blink rather than checking every film against every other.
            var watchedIDs = Set(d.watched.map(\.id)).union(d.entries.map(\.film.id))
            var inWatchlist = Set(d.watchlist.map(\.id))
            var likedIDs = Set(d.liked.map(\.id))
            for r in rows {
                guard let f = resolved[importKey(r)] else {
                    if unmatchedKeys.insert(importKey(r)).inserted { unmatched.append("\(r.name) (\(r.year.map(String.init) ?? "?"))") }
                    continue
                }
                let watched = watchedIDs.contains(f.id)
                func markWatched() { if !watched { d.watched.append(f); watchedIDs.insert(f.id) } }
                func leaveWatchlist() { if inWatchlist.remove(f.id) != nil { d.watchlist.removeAll { $0.id == f.id } } }
                switch r.kind {
                case .diary, .reviews:
                    // Letterboxd rates in stars; Matinee scores films out of 100.
                    entries.append(LogEntry(film: f, watchedOn: r.date ?? .now, rating: r.rating.map(Score.fromStars), liked: false, rewatch: r.rewatch, review: r.review, tags: r.tags))
                case .watched:
                    markWatched()
                    leaveWatchlist()
                case .watchlist:
                    if !watched && inWatchlist.insert(f.id).inserted { d.watchlist.append(f) }
                case .ratings:
                    // On Letterboxd a rating means you've seen it, so it lands in your films and ratings tracker.
                    if let rt = r.rating, rt > 0 { d.ratings[f.id] = Score.fromStars(rt) }
                    markWatched()
                    leaveWatchlist()
                case .likes:
                    if likedIDs.insert(f.id).inserted { d.liked.append(f) }
                    markWatched()
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
        // A film already logged on the same day isn't logged twice, so importing the same file again is harmless.
        library.apply { d in
            let cal = Calendar.current
            var logged = Set(d.entries.map { "\($0.film.id)|\(cal.startOfDay(for: $0.watchedOn).timeIntervalSince1970)" })
            var added = Set<String>()
            for e in byKey.values.sorted(by: { $0.watchedOn < $1.watchedOn }) {
                guard logged.insert("\(e.film.id)|\(cal.startOfDay(for: e.watchedOn).timeIntervalSince1970)").inserted else { continue }
                d.entries.append(e)
                if let r = e.rating, r > 0 { d.ratings[e.film.id] = r }
                added.insert(e.film.id)
            }
            if !added.isEmpty { d.watchlist.removeAll { added.contains($0.id) } }
        }
        library.toast = Toast(text: "Imported \(total - unmatched.count) of \(total) films", symbol: "square.and.arrow.down")
        summary = "Matched \(total - unmatched.count) of \(total) films." + (unmatched.isEmpty ? "" : " \(unmatched.count) couldn't be matched.")
    }

    /// The search hit that is this row: same title and year first, then the same year, then a year either side.
    nonisolated static func best(_ hits: [FilmRef], for r: Row) -> FilmRef? {
        func exact(_ list: [FilmRef]) -> FilmRef? { list.first { $0.title.caseInsensitiveCompare(r.name) == .orderedSame } }
        let sameYear = hits.filter { r.year == nil || $0.year == r.year }
        let near = r.year.map { y in hits.filter { abs(($0.year ?? 0) - y) <= 1 } } ?? []
        return exact(sameYear) ?? sameYear.first ?? exact(near) ?? near.first
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

/// The Files picker for Letterboxd CSVs (or, with `types`, a Matinee backup). Files are copied into the app first,
/// so reading them never depends on security-scoped access, and one tap on a file picks it (no Select / Done step).
struct CSVPicker: UIViewControllerRepresentable {
    var multiple = false
    var types: [UTType] = [.commaSeparatedText, .plainText, .text, UTType(filenameExtension: "csv")].compactMap { $0 }
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) }
    }
}
