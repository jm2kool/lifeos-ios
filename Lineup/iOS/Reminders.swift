import Foundation
import UserNotifications

/// Optional heads-up notifications a few minutes before each lesson. They're booked on the phone,
/// so they need no connection, and they show on the watch whenever the phone is locked.
enum Reminders {
    static let onKey = "remindersOn"
    static let leadKey = "reminderLead"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }

    /// Minutes before the lesson.
    static var lead: Int {
        let value = UserDefaults.standard.integer(forKey: leadKey)
        return value == 0 ? 2 : value
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Books the next two weeks of lessons (iOS keeps at most 64 waiting, so this stops at 60).
    static func reschedule(_ timetable: Timetable) async {
        let centre = UNUserNotificationCenter.current()
        let pending = await centre.pendingNotificationRequests()
        centre.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("lesson-") })
        guard isOn else { return }

        let cal = Calendar.current
        let now = Date()
        let lead = lead
        var booked = 0
        for offset in 0..<14 {
            guard booked < 60, let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { break }
            for slot in timetable.slots(on: day) {
                let fire = slot.start.addingTimeInterval(TimeInterval(-lead * 60))
                guard fire > now, booked < 60 else { continue }
                let content = UNMutableNotificationContent()
                content.title = slot.room.isEmpty ? slot.name : "\(slot.name) · \(slot.room)"
                content.body = "Starts at \(Clock.time(slot.start))"
                    + (slot.bring.isEmpty ? "" : ". Bring: \(slot.bring.joined(separator: ", "))")
                content.sound = .default
                let when = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(identifier: "lesson-\(slot.id.uuidString)-\(offset)",
                                                    content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
                try? await centre.add(request)
                booked += 1
            }
        }
    }
}
