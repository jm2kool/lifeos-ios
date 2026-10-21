import Foundation
import ActivityKit
import WidgetKit

/// Keeps the "now watching" Live Activity (Lock Screen + Dynamic Island) in step with Intermission mode.
@MainActor
enum NowWatchingActivity {
    static func sync(_ sessions: [WatchSession]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // The running film, else the one you paused most recently (shown as "Intermission").
        let current = sessions.first(where: \.running)
            ?? sessions.max { ($0.lastStop?.when ?? $0.started) < ($1.lastStop?.when ?? $1.started) }
        let live = Activity<WatchActivityAttributes>.activities
        for a in live where a.attributes.filmID != current?.film.id {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        guard let s = current else { return }
        let state = WatchActivityAttributes.ContentState(runStartedAt: s.runStartedAt, banked: s.banked, runtime: s.runtime,
                                                         mood: s.lastStop?.mood, note: s.lastStop?.note)
        // A paused film fades from the Lock Screen after a few hours.
        let content = ActivityContent(state: state, staleDate: s.running ? nil : Date.now.addingTimeInterval(4 * 3600))
        if let a = live.first(where: { $0.attributes.filmID == s.film.id }) {
            Task { await a.update(content) }
        } else {
            let attrs = WatchActivityAttributes(filmID: s.film.id, title: s.film.title, year: s.film.year)
            _ = try? Activity.request(attributes: attrs, content: content, pushType: nil)
        }
    }
}

/// The watchlist snapshot the home-screen widget picks from.
@MainActor
enum WatchlistWidget {
    private static var last: [SharedStore.Film] = []

    static func publish(_ films: [FilmRef]) {
        let out = films.map { SharedStore.Film(id: $0.id, title: $0.title, year: $0.year, poster: $0.poster) }
        guard out != last else { return }
        last = out
        SharedStore.saveWatchlist(out)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
    }
}
