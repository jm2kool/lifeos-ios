import Foundation
import SwiftData
import UserNotifications

/// Test data for recaps and stats (SPEC §10): two weeks of made-up plays for real library songs, clearly marked
/// so it can be removed. Settings → Diagnostics.
@MainActor
enum DebugSeeder {
    static func seed(_ snapshot: LibrarySnapshot) {
        let context = Store.shared.context
        let pool = Array(snapshot.songs.shuffled().prefix(80))
        guard !pool.isEmpty else { return }
        let now = Date.now
        // Start the recording two weeks back, so the seeded weeks count.
        let start = now.addingTimeInterval(-15 * 86_400)
        if (SnapshotService.shared.baselineDate ?? now) > start { UserDefaults.standard.set(start, forKey: "recaps.baseline") }
        var counts = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, max(0, $0.playCount - 60)) })
        for s in pool {
            let row = PlaySnapshot(date: start, persistentID: s.id, playCount: counts[s.id] ?? 0)
            row.seeded = true
            context.insert(row)
        }
        for day in 1...14 {
            let date = start.addingTimeInterval(Double(day) * 86_400)
            for s in pool.shuffled().prefix(Int.random(in: 8...25)) {
                counts[s.id, default: 0] += Int.random(in: 1...4)
                let row = PlaySnapshot(date: date, persistentID: s.id, playCount: counts[s.id] ?? 0)
                row.seeded = true
                context.insert(row)
            }
        }
        Store.shared.save()
    }

    static func remove() {
        let context = Store.shared.context
        try? context.delete(model: PlaySnapshot.self, where: #Predicate { $0.seeded })
        try? context.delete(model: PlayEvent.self, where: #Predicate { $0.seeded })
        Store.shared.save()
    }
}

/// "Your week in music is ready" on Monday mornings (optional).
enum RecapNotifications {
    static let id = "liner.weekly-recap"

    static func setEnabled(_ on: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard on else { return false }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Your week in music is ready"
        content.body = "Open \(AppBrand.name) for last week's recap."
        var when = DateComponents()
        when.weekday = 2
        when.hour = 9
        when.minute = 3
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        return true
    }
}
