import Foundation
import SwiftUI
import UIKit

/// Your library as files you keep: a full Matinee backup (JSON) that Restore brings back, and your diary and
/// watchlist as CSVs in the format letterboxd.com/import reads, so your history is never stuck in one app.
@MainActor
enum Backup {
    enum Failure: LocalizedError {
        case notABackup
        var errorDescription: String? { "That file isn't a Matinee backup. Pick a file saved with Settings → Back up my library." }
    }

    /// Everything — diary, ratings, lists, shows, profile — in one file.
    static func backupFile(_ library: Library) throws -> URL {
        let url = folder().appendingPathComponent("Matinee backup \(stamp()).json")
        try Library.encoder.encode(library.doc).write(to: url, options: .atomic)
        return url
    }

    /// A backup file picked in Files.
    static func read(_ url: URL) throws -> LibraryDoc {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let doc = try? Library.decoder.decode(LibraryDoc.self, from: data) else { throw Failure.notABackup }
        return doc
    }

    /// Films you've logged, with dates, ratings, reviews and tags — plus films marked watched or rated without a
    /// diary entry — as Letterboxd's import CSV. Shows aren't included: Letterboxd is films only.
    static func diaryCSV(_ library: Library) throws -> URL {
        var rows = [["Title", "Year", "tmdbID", "WatchedDate", "Rating", "Rewatch", "Tags", "Review"]]
        var logged = Set<String>()
        for e in library.entries.reversed() where !e.film.isShow {
            logged.insert(e.film.id)
            rows.append([e.film.title, e.film.yearText, tmdbNumber(e.film.id), day.string(from: e.watchedOn), stars(e.rating),
                         e.rewatch ? "Yes" : "", e.tags.joined(separator: ", "), e.review])
        }
        for f in library.watchedFilms where !f.isShow && !logged.contains(f.id) {
            rows.append([f.title, f.yearText, tmdbNumber(f.id), "", stars(library.rating(f.id)), "", "", ""])
        }
        return try write(rows, name: "Matinee diary \(stamp()).csv")
    }

    /// Your watchlist, films and shows, in the same format.
    static func watchlistCSV(_ library: Library) throws -> URL {
        var rows = [["Title", "Year", "tmdbID", "Type"]]
        for f in library.doc.watchlist {
            rows.append([f.title, f.yearText, tmdbNumber(f.id), f.isShow ? "TV" : "Film"])
        }
        return try write(rows, name: "Matinee watchlist \(stamp()).csv")
    }

    // MARK: Helpers

    private static func write(_ rows: [[String]], name: String) throws -> URL {
        let text = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
        let url = folder().appendingPathComponent(name)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Quotes a field when it holds a comma, a quote or a line break, as CSV readers expect.
    private static func escape(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Letterboxd rates in half stars, 0.5–5.
    private static func stars(_ score: Double?) -> String {
        guard let s = score, s > 0 else { return "" }
        let v = Score.starsShown(s)
        return v == v.rounded() ? String(Int(v)) : String(v)
    }

    /// "tmdb-603" → "603"; empty for anything else (older IMDb ids, shows).
    private static func tmdbNumber(_ id: String) -> String {
        id.hasPrefix("tmdb-") ? String(id.dropFirst(5)) : ""
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func stamp() -> String { day.string(from: .now) }

    /// A fresh folder in tmp for each export, so the share sheet shows a tidy file name.
    private static func folder() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// The system share sheet, for files made on demand.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
