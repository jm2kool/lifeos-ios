import Foundation
import Observation
import UserNotifications

/// A focus session. Keeps running when the app is closed; a notification tells you when it ends.
@MainActor
@Observable
final class FocusTimer {
    static let shared = FocusTimer()
    var label = ""
    var minutes = 25
    var startedAt: Date?
    var pausedAt: Date?
    var spent: TimeInterval = 0     // time counted before the last pause
    @ObservationIgnored weak var store: Store?

    init() {
        let d = UserDefaults.standard
        if let s = d.object(forKey: "focus.start") as? Date { startedAt = s }
        if let p = d.object(forKey: "focus.paused") as? Date { pausedAt = p }
        spent = d.double(forKey: "focus.spent"); minutes = max(1, d.integer(forKey: "focus.minutes")); label = d.string(forKey: "focus.label") ?? ""
        if d.integer(forKey: "focus.minutes") == 0 { minutes = 25 }
    }
    private func save() {
        let d = UserDefaults.standard
        d.set(startedAt, forKey: "focus.start"); d.set(pausedAt, forKey: "focus.paused"); d.set(spent, forKey: "focus.spent")
        d.set(minutes, forKey: "focus.minutes"); d.set(label, forKey: "focus.label")
    }

    var running: Bool { startedAt != nil }
    var paused: Bool { pausedAt != nil }
    var elapsed: TimeInterval { guard let s = startedAt else { return 0 }; return spent + (pausedAt ?? Date()).timeIntervalSince(s) }
    var remaining: TimeInterval { max(0, Double(minutes) * 60 - elapsed) }
    var endDate: Date { Date().addingTimeInterval(remaining) }
    var progress: Double { minutes > 0 ? min(1, elapsed / (Double(minutes) * 60)) : 0 }

    func start(minutes m: Int, label l: String) {
        minutes = m; label = l.isEmpty ? "Focus" : l; startedAt = Date(); pausedAt = nil; spent = 0
        save(); notify()
    }
    func togglePause() {
        guard let s = startedAt else { return }
        if let p = pausedAt { spent += p.timeIntervalSince(s); startedAt = Date(); pausedAt = nil; notify() }
        else { pausedAt = Date(); cancelNotification() }
        save()
    }
    func stop(complete: Bool = false) {
        let mins = complete ? minutes : Int(elapsed / 60)
        let l = label
        startedAt = nil; pausedAt = nil; spent = 0; save(); cancelNotification()
        guard let store else { return }
        if mins >= 1 {
            store.act(["op": "focus.log", "date": .string(store.today), "minutes": JSON(mins), "label": .string(l)], undo: "\(mins) min of focus logged")
        } else { store.show("Session ended") }
    }
    func checkFinished() { if running && !paused && remaining <= 0 { stop(complete: true) } }

    private func notify() {
        cancelNotification()
        let c = UNMutableNotificationContent()
        c.title = "Focus session done"; c.body = "\(minutes) minutes of \(label). Nice work."; c.sound = .default
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "focus", content: c, trigger: t))
    }
    private func cancelNotification() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus"]) }
}
