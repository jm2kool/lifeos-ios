import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Code shared by the app and its widgets: the Live Activity for a film in progress, and the
/// watchlist snapshot the home-screen widget picks from.

enum SharedStore {
    static let appGroup = "group.com.jm2kool.matinee"
    static let widgetKind = "RandomWatchlistWidget"

    struct Film: Codable, Hashable {
        var id: String
        var title: String
        var year: Int?
        var poster: URL?
    }

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("watchlist.json")
    }

    static func saveWatchlist(_ films: [Film]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(films) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadWatchlist() -> [Film] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Film].self, from: data)) ?? []
    }

    /// Opens the film's page in the app.
    static func filmURL(_ f: Film) -> URL {
        var c = URLComponents()
        c.scheme = "matinee"
        c.host = "film"
        c.path = "/" + f.id
        c.queryItems = [URLQueryItem(name: "title", value: f.title)] + (f.year.map { [URLQueryItem(name: "year", value: String($0))] } ?? [])
            + (f.poster.map { [URLQueryItem(name: "poster", value: $0.absoluteString)] } ?? [])
        return c.url!
    }
}

#if canImport(ActivityKit)
/// "Now watching" on the Lock Screen and in the Dynamic Island.
struct WatchActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var runStartedAt: Date?          // nil while on intermission
        var banked: TimeInterval         // position reached before the current run
        var runtime: TimeInterval?
        var mood: String?
        var note: String?

        var running: Bool { runStartedAt != nil }
        /// When the film would have started if you'd watched without stopping — drives the live timer.
        var virtualStart: Date { (runStartedAt ?? .now).addingTimeInterval(-banked) }
    }
    var filmID: String
    var title: String
    var year: Int?
}
#endif
