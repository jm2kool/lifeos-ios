import Foundation
import UserNotifications

/// Local notifications for deadlines (a day and 2 hours before) and the daily card review. Study block alerts are
/// StudyAlerts'. Rebuilt whenever the plan changes; iOS keeps at most 64 waiting, so the soonest ones win.
@MainActor
final class Notifier {
    static let shared = Notifier()
    private let prefix = "lumen.plan."

    private var pending: Task<Void, Never>?

    enum Kind: String, CaseIterable, Identifiable {
        case deadlines, review
        var id: String { rawValue }
        var label: String {
            switch self {
            case .deadlines: return "Deadlines (a day and 2 hours before)"
            case .review: return "Daily card review"
            }
        }
    }

    func isOn(_ k: Kind) -> Bool { UserDefaults.standard.object(forKey: "notify." + k.rawValue) as? Bool ?? true }
    func set(_ k: Kind, _ on: Bool) { UserDefaults.standard.set(on, forKey: "notify." + k.rawValue); scheduleRefresh() }

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleRefresh() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reschedule()
        }
    }

    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let store = Store.shared
        let now = Date()
        var items: [(Date, UNNotificationRequest)] = []

        func request(_ id: String, at date: Date, title: String, body: String, info: [String: String] = [:]) {
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            c.userInfo = info
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let r = UNNotificationRequest(identifier: prefix + id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            items.append((date, r))
        }

        if isOn(.deadlines) {
            for a in store.live(Assignment.self) where a.isOpen {
                guard let due = a.dueAt, due > now else { continue }
                let subject = store.subject(a.subjectID)?.name.appending(" · ") ?? ""
                let pct = Int(store.progress(a) * 100)
                for (lead, label) in [(86400.0, "tomorrow"), (7200.0, "in 2 hours")] {
                    let at = due.addingTimeInterval(-lead)
                    guard at > now, at < now.addingTimeInterval(30 * 86400) else { continue }
                    request("due\(Int(lead)).\(a.id.lower)", at: at, title: "\(a.title) is due \(label)",
                            body: "\(subject)\(a.kind.label) · \(pct)% done", info: ["assignment": a.id.lower])
                }
            }
        }

        items.sort { $0.0 < $1.0 }
        for (_, r) in items.prefix(58) { try? await center.add(r) }

        // The daily review reminder repeats; its text uses today's count.
        center.removePendingNotificationRequests(withIdentifiers: [prefix + "review"])
        if isOn(.review), !store.live(Card.self).isEmpty {
            let c = UNMutableNotificationContent()
            let due = store.dueCards().count
            c.title = "Flashcards"
            c.body = due > 0 ? "\(due) cards are ready to review." : "A quick review keeps it all fresh."
            c.sound = .default
            c.userInfo = ["open": "review"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: Clock.components(store.prefs.reviewTime), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: prefix + "review", content: c, trigger: trigger))
        }
    }
}
