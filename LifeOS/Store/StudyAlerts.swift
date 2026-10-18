import Foundation
import UserNotifications

/// Reminders when a study block starts (plus an optional heads-up a few minutes before),
/// and the "study lock" that bounces you back to LifeOS during a block.
enum StudyAlerts {
    static let prefix = "study-"
    static let category = "STUDY_BLOCK"
    static let focusAction = "START_FOCUS"

    /// Timetable and study-plan blocks count; lunch, breaks and school calendar events don't.
    static func isStudy(_ b: Block) -> Bool {
        switch b.kind {
        case .study: return true
        case .timetable:
            let t = b.title.lowercased()
            let rest = ["lunch", "dinner", "breakfast", "brunch", "break", "nap", "sleep", "bed", "free", "rest", "snack",
                        "shower", "gym", "walk", "workout", "wake", "commute", "travel", "family", "chill", "off"]
            return !rest.contains { t.hasPrefix($0) }
        default: return false
        }
    }

    static func registerCategories() {
        let focus = UNNotificationAction(identifier: focusAction, title: "Start focus timer", options: [.foreground])
        let cat = UNNotificationCategory(identifier: category, actions: [focus], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    /// Replaces every pending study reminder with fresh ones for the next three days.
    @MainActor
    static func reschedule(_ store: Store) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard store.studyAlertsOn else { return }

        let now = Date(), horizon = now.addingTimeInterval(3 * 86400), lead = store.studyLead
        let blocks = store.timeline.filter { isStudy($0) && $0.start > now && $0.start < horizon }.prefix(20)
        for b in blocks {
            let span = store.time(b.start) + "–" + store.time(b.end)
            let minutes = max(1, Int(b.end.timeIntervalSince(b.start) / 60))
            let info: [String: Any] = ["title": b.title, "end": b.end.timeIntervalSince1970, "minutes": minutes]

            let start = UNMutableNotificationContent()
            start.title = "Time to study"
            start.body = "\(b.title) · \(span)"
            start.sound = .default
            start.categoryIdentifier = category
            start.threadIdentifier = "study"
            start.userInfo = info
            add(center, id: prefix + "start-" + b.id, content: start, at: b.start)

            let early = b.start.addingTimeInterval(-Double(lead) * 60)
            if lead > 0, early > now {
                let heads = UNMutableNotificationContent()
                heads.title = "\(b.title) in \(lead) min"
                heads.body = "Starts at \(store.time(b.start)). Wrap up what you're doing."
                heads.sound = .default
                heads.categoryIdentifier = category
                heads.threadIdentifier = "study"
                heads.userInfo = info
                add(center, id: prefix + "soon-" + b.id, content: heads, at: early)
            }
        }
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, content: UNMutableNotificationContent, at date: Date) {
        let wait = date.timeIntervalSinceNow
        guard wait > 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// Lets notifications show while the app is open, and handles taps on study reminders.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        guard request.identifier.hasPrefix(StudyAlerts.prefix) else { return }
        let title = request.content.userInfo["title"] as? String ?? "Study"
        let end = request.content.userInfo["end"] as? Double ?? 0
        let startFocus = response.actionIdentifier == StudyAlerts.focusAction
        await MainActor.run {
            Store.shared.tab = .study
            if startFocus {
                let left = Int((end - Date().timeIntervalSince1970) / 60)
                FocusTimer.shared.start(minutes: max(5, min(240, left)), label: title)
            }
        }
    }
}

/// A short break from the study lock.
enum StudyLock {
    private static let key = "studyLock.snoozeUntil"
    static var snoozed: Bool { (UserDefaults.standard.object(forKey: key) as? Date).map { $0 > Date() } ?? false }
    static func snooze(minutes: Int) { UserDefaults.standard.set(Date().addingTimeInterval(Double(minutes) * 60), forKey: key) }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

extension Store {
    private var studySettings: JSON { doc["settings"]["study"] }
    var studyAlertsOn: Bool { studySettings["alerts"].isNull ? true : studySettings["alerts"].bool }
    var studyLead: Int { studySettings["lead"].int ?? 5 }
    var studyLockOn: Bool { studySettings["lock"].isNull ? true : studySettings["lock"].bool }

    /// The study block happening right now, if any.
    var currentStudy: Block? {
        let n = Date()
        return timeline.first { StudyAlerts.isStudy($0) && $0.start <= n && n < $0.end }
    }
    /// The block the study lock should send you back to (none while the lock is off or on a break).
    var lockingBlock: Block? { studyLockOn && !StudyLock.snoozed ? currentStudy : nil }

    /// Changes whenever reminders need rescheduling.
    var studyAlertKey: String {
        let n = Date()
        let ids = timeline.filter { StudyAlerts.isStudy($0) && $0.start > n }.prefix(20).map { $0.id + "@\(Int($0.start.timeIntervalSince1970))" }
        return today + "|\(studyAlertsOn)|\(studyLead)|" + ids.joined(separator: ",")
    }
}
