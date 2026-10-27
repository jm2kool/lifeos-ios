import Foundation
import UIKit
import UserNotifications

/// Local notifications: the next episode of shows you're watching on the day it airs, and films you're
/// waiting for on the day they come out. Everything is worked out on the phone; no server involved.
@MainActor
enum Reminders {
    static let episodesKey = "notifyEpisodes"
    static let releasesKey = "notifyReleases"
    static var episodesOn: Bool { UserDefaults.standard.object(forKey: episodesKey) as? Bool ?? true }
    static var releasesOn: Bool { UserDefaults.standard.object(forKey: releasesKey) as? Bool ?? true }

    private static var lastRefresh = Date.distantPast
    private static var running = false

    /// Ask once, at a moment it makes sense (pinning a show, setting a reminder, turning a switch on).
    @discardableResult
    static func requestPermission() async -> Bool {
        let c = UNUserNotificationCenter.current()
        let settings = await c.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static var authorized: Bool {
        get async {
            let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            return s == .authorized || s == .provisional || s == .ephemeral
        }
    }

    /// Re-plan every reminder. Cheap to call often: it runs at most once an hour unless forced.
    static func refresh(_ library: Library, force: Bool = false, ask: Bool = false) async {
        guard !running, force || Date.now.timeIntervalSince(lastRefresh) > 3600 else { return }
        guard Catalog.hasToken else { return }
        if ask { await requestPermission() }
        guard await authorized else { return }
        running = true
        defer { running = false; lastRefresh = .now }

        var requests: [UNNotificationRequest] = []
        if episodesOn { requests += await episodeRequests(library) }
        if releasesOn { requests += await releaseRequests(library) }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("ep-") || $0.hasPrefix("rel-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        // iOS keeps at most 64 pending; the soonest matter most.
        for r in requests.sorted(by: { fireDate($0) < fireDate($1) }).prefix(60) { try? await center.add(r) }
    }

    private static func fireDate(_ r: UNNotificationRequest) -> Date {
        (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }

    /// Shows you've pinned or are partway through: the next episode, at 6pm on the day it airs.
    private static func episodeRequests(_ library: Library) async -> [UNNotificationRequest] {
        var seen = Set<String>()
        let shows = (library.currentlyWatching + library.showsInProgress).filter { seen.insert($0.id).inserted }.prefix(25)
        var out: [UNNotificationRequest] = []
        for show in shows {
            guard let d = try? await Catalog.detail(show.id), let next = d.nextEpisode, let day = next.airDate,
                  let when = at(hour: 18, on: day), when > .now else { continue }
            let c = UNMutableNotificationContent()
            c.title = show.title
            c.body = "\(next.code) “\(next.name)” is out today."
            c.sound = .default
            c.threadIdentifier = "episodes"
            c.userInfo = ["url": filmURL(show).absoluteString]
            out.append(request("ep-\(show.id)-\(next.id)", c, when))
        }
        return out
    }

    /// Films you asked to be reminded about, and unreleased films on your watchlist: 10am on release day.
    private static func releaseRequests(_ library: Library) async -> [UNNotificationRequest] {
        var dates: [String: (FilmRef, Date)] = [:]
        for r in library.reminders { dates[r.film.id] = (r.film, r.date) }
        // Only recent or future films can still be unreleased; this keeps the lookups few.
        let thisYear = Date.now.year
        let candidates = library.doc.watchlist.filter { !$0.isShow && ($0.year ?? thisYear) >= thisYear && dates[$0.id] == nil }.prefix(30)
        for f in candidates {
            if let d = try? await Catalog.detail(f.id), let date = d.releaseDate, date > .now { dates[f.id] = (f, date) }
        }
        return dates.values.compactMap { film, date in
            guard let when = at(hour: 10, on: date), when > .now else { return nil }
            let c = UNMutableNotificationContent()
            c.title = "\(film.title) is out today"
            c.body = "You wanted to know. Tap to see where it's showing or streaming."
            c.sound = .default
            c.threadIdentifier = "releases"
            c.userInfo = ["url": filmURL(film).absoluteString]
            return request("rel-\(film.id)", c, when)
        }
    }

    private static func at(hour: Int, on day: Date) -> Date? {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    private static func request(_ id: String, _ c: UNNotificationContent, _ when: Date) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        return UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    static func filmURL(_ f: FilmRef) -> URL {
        SharedStore.filmURL(SharedStore.Film(id: f.id, title: f.title, year: f.year, poster: f.poster))
    }
}

/// Shows notifications while the app is open, and opens the film when one is tapped.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let s = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: s) else { return }
        await MainActor.run { UIApplication.shared.open(url) }
    }
}
