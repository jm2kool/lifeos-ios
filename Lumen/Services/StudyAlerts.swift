import Foundation
import UserNotifications

/// Local notifications for study blocks, scheduled on the iPhone from your plan: "starts now" at each block's start,
/// and an optional heads-up a few minutes before. Every id starts with `prefix`, so this only ever clears its own.
enum StudyAlerts {
    static let prefix = "study-"
    static let category = "STUDY_BLOCK_CATEGORY"
    static let startFocusAction = "START_FOCUS"

    static func registerCategories() {
        let start = UNNotificationAction(identifier: startFocusAction, title: "Start focus", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [start], intentIdentifiers: [], options: []),
        ])
    }

    @MainActor static func reschedule(_ store: Store) async {
        let center = UNUserNotificationCenter.current()
        let mine = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: mine)
        guard store.studyAlertsOn else { return }

        let lead = store.studyAlertLead
        for b in store.upcomingAlertBlocks {
            let title = store.alertTitle(b)
            let minutes = b.minutes
            let info: [String: Any] = ["title": title, "end": b.endAt.timeIntervalSince1970, "minutes": minutes, "block": b.id.lower]
            let subject = store.subject(b.subjectID)?.name

            let start = UNMutableNotificationContent()
            start.title = "\(title) starts now"
            start.body = [subject, Fmt.span(b.startAt, b.endAt), b.goal == title ? nil : b.goal].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            start.sound = .default
            start.categoryIdentifier = category
            start.threadIdentifier = "study-blocks"
            start.userInfo = info
            add(center: center, id: prefix + "start-" + b.id.lower, content: start, at: b.startAt)

            let soon = b.startAt.addingTimeInterval(-Double(lead) * 60)
            if lead > 0, soon > Date() {
                let heads = UNMutableNotificationContent()
                heads.title = "\(title) in \(lead) min"
                heads.body = [subject, "\(minutes) min"].compactMap { $0 }.joined(separator: " · ")
                heads.sound = .default
                heads.categoryIdentifier = category
                heads.threadIdentifier = "study-blocks"
                heads.userInfo = info
                add(center: center, id: prefix + "soon-" + b.id.lower, content: heads, at: soon)
            }
        }
    }

    private static func add(center: UNUserNotificationCenter, id: String, content: UNNotificationContent, at date: Date) {
        let wait = date.timeIntervalSinceNow
        guard wait >= 1 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
