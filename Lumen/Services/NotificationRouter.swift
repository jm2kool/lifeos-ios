import Foundation
import UserNotifications

/// Shows notifications while Lumen is open, and handles taps: a study block alert opens the Focus tab ready for that
/// block, and its "Start focus" button also starts the timer for the time left in the block.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        let info = response.notification.request.content.userInfo
        guard id.hasPrefix(StudyAlerts.prefix) else {
            // Lumen's other notifications (deadlines, the daily review, pushes) say where to go in their own way.
            let open = info["open"] as? String
            let assignment = (info["assignment"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                if let open, let url = URL(string: open.hasPrefix("lumen://") ? open : "lumen://\(open)") { Router.shared.handle(url) }
                else if let assignment { Router.shared.openAssignment(assignment) }
                completionHandler()
            }
            return
        }
        let block = (info["block"] as? String).flatMap(UUID.init(uuidString:))
        let end = (info["end"] as? Double).map(Date.init(timeIntervalSince1970:))
        let start = response.actionIdentifier == StudyAlerts.startFocusAction
        Task { @MainActor in
            if let block { Router.shared.openFocus(block: block) } else { Router.shared.tab = .focus }
            if start, let end, !FocusTimer.shared.active {
                let left = Int((end.timeIntervalSinceNow / 60).rounded())
                FocusTimer.shared.setLength(minutes: min(240, max(5, left)))
                FocusTimer.shared.start()
            }
            completionHandler()
        }
    }
}
