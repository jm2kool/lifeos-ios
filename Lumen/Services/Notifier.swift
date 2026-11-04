import Foundation
import UserNotifications

/// Local notifications: block start, a 10-minute warning, deadlines (24 h and 2 h before) and the daily review.
/// They're rebuilt whenever the plan changes, from you or from Instinct. iOS keeps at most 64 waiting, so the
/// soonest ones win.
@MainActor
final class Notifier: NSObject {
    static let shared = Notifier()
    static let blockCategory = "lumen.block"
    static let startFocusAction = "lumen.startFocus"
    private let prefix = "lumen.plan."

    private var pending: Task<Void, Never>?

    enum Kind: String, CaseIterable, Identifiable {
        case blockStart, warning, deadlines, review
        var id: String { rawValue }
        var label: String {
            switch self {
            case .blockStart: return "When a block starts"
            case .warning: return "10 minutes before a block"
            case .deadlines: return "Deadlines (a day and 2 hours before)"
            case .review: return "Daily card review"
            }
        }
    }

    func isOn(_ k: Kind) -> Bool { UserDefaults.standard.object(forKey: "notify." + k.rawValue) as? Bool ?? true }
    func set(_ k: Kind, _ on: Bool) { UserDefaults.standard.set(on, forKey: "notify." + k.rawValue); scheduleRefresh() }

    func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startFocusAction, title: "Start focus", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "timer"))
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.blockCategory, actions: [start], intentIdentifiers: [])])
    }

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
        let horizon = now.addingTimeInterval(8 * 86400)
        var items: [(Date, UNNotificationRequest)] = []

        func request(_ id: String, at date: Date, title: String, body: String, category: String? = nil, info: [String: String] = [:]) {
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            if let category { c.categoryIdentifier = category }
            c.userInfo = info
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let r = UNNotificationRequest(identifier: prefix + id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            items.append((date, r))
        }

        for b in store.live(StudyBlock.self) where b.status == .planned && b.startAt > now && b.startAt < horizon {
            let subject = store.subject(b.subjectID)?.name
            let what = [subject, b.goal.isEmpty ? b.kind.label : b.goal].compactMap { $0 }.joined(separator: " · ")
            let span = "\(Fmt.time(b.startAt))–\(Fmt.time(b.endAt))"
            if isOn(.blockStart) {
                request("start.\(b.id.lower)", at: b.startAt, title: "Time to study", body: "\(what) · \(span)",
                        category: Self.blockCategory, info: ["block": b.id.lower])
            }
            let warn = b.startAt.addingTimeInterval(-600)
            if isOn(.warning), warn > now {
                request("warn.\(b.id.lower)", at: warn, title: "In 10 minutes", body: what, category: Self.blockCategory, info: ["block": b.id.lower])
            }
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

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let block = info["block"] as? String
        let assignment = info["assignment"] as? String
        let open = info["open"] as? String
        Task { @MainActor in
            if let open, open.hasPrefix("lumen://"), let url = URL(string: open) {
                Router.shared.handle(url)   // pushes from the server say where to go
            } else if let block, let id = UUID(uuidString: block) {
                Router.shared.openFocus(block: id)
            } else if let assignment, let id = UUID(uuidString: assignment) {
                Router.shared.openAssignment(id)
            } else if open == "review" {
                Router.shared.openReview()
            }
            completionHandler()
        }
    }
}
