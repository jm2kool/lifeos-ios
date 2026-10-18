import Foundation
import Observation
import UserNotifications
import ActivityKit

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

    /// Makes sure the store is connected (the app may have been woken just to handle a Lock Screen button).
    func attach() { if store == nil { store = Store.shared } }

    func start(minutes m: Int, label l: String) {
        minutes = m; label = l.isEmpty ? "Focus" : l; startedAt = Date(); pausedAt = nil; spent = 0
        save(); notify()
        FocusActivityController.start(label: label, state: activityState)
    }
    func togglePause() {
        guard let s = startedAt else { return }
        if let p = pausedAt { spent += p.timeIntervalSince(s); startedAt = Date(); pausedAt = nil; notify() }
        else { pausedAt = Date(); cancelNotification() }
        save()
        FocusActivityController.update(activityState)
    }
    func stop(complete: Bool = false) {
        let mins = complete ? minutes : Int(elapsed / 60)
        let l = label
        var last = activityState; last.done = complete; last.remaining = 0
        startedAt = nil; pausedAt = nil; spent = 0; save(); cancelNotification()
        FocusActivityController.end(last, linger: complete)
        guard let store else { return }
        if mins >= 1 {
            store.act(["op": "focus.log", "date": .string(store.today), "minutes": JSON(mins), "label": .string(l)], undo: "\(mins) min of focus logged")
        } else { store.show("Session ended") }
    }
    func checkFinished() { if running && !paused && remaining <= 0 { stop(complete: true) } }

    private var activityState: FocusAttributes.ContentState {
        FocusAttributes.ContentState(endDate: endDate, paused: paused, remaining: remaining, total: Double(minutes) * 60)
    }

    private func notify() {
        cancelNotification()
        let c = UNMutableNotificationContent()
        c.title = "Focus session done"; c.body = "\(minutes) minutes of \(label). Nice work."; c.sound = .default
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "focus", content: c, trigger: t))
    }
    private func cancelNotification() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus"]) }
}

/// Starts, updates and ends the focus Live Activity (Lock Screen and Dynamic Island).
@MainActor
enum FocusActivityController {
    static func start(label: String, state: FocusAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            for a in Activity<FocusAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            _ = try? Activity.request(attributes: FocusAttributes(label: label), content: .init(state: state, staleDate: state.endDate), pushType: nil)
        }
    }
    static func update(_ state: FocusAttributes.ContentState) {
        Task {
            for a in Activity<FocusAttributes>.activities { await a.update(.init(state: state, staleDate: state.paused ? nil : state.endDate)) }
        }
    }
    /// A finished session stays on the Lock Screen for a few minutes; an ended one disappears.
    static func end(_ state: FocusAttributes.ContentState, linger: Bool) {
        Task {
            for a in Activity<FocusAttributes>.activities {
                await a.end(.init(state: state, staleDate: nil), dismissalPolicy: linger ? .after(Date().addingTimeInterval(5 * 60)) : .immediate)
            }
        }
    }
}
