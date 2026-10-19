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
    var sessionID: String?          // the study session this focus run is logged as (content.sessions)
    @ObservationIgnored weak var store: Store?

    init() {
        let d = UserDefaults.standard
        if let s = d.object(forKey: "focus.start") as? Date { startedAt = s }
        if let p = d.object(forKey: "focus.paused") as? Date { pausedAt = p }
        spent = d.double(forKey: "focus.spent"); sessionID = d.string(forKey: "focus.session"); minutes = max(1, d.integer(forKey: "focus.minutes")); label = d.string(forKey: "focus.label") ?? ""
        if d.integer(forKey: "focus.minutes") == 0 { minutes = 25 }
    }
    private func save() {
        let d = UserDefaults.standard
        d.set(startedAt, forKey: "focus.start"); d.set(pausedAt, forKey: "focus.paused"); d.set(spent, forKey: "focus.spent")
        d.set(minutes, forKey: "focus.minutes"); d.set(label, forKey: "focus.label"); d.set(sessionID, forKey: "focus.session")
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
        attach()
        // Starting focus counts as a study block: it shows in Study and the timeline, and the study lock covers it.
        if let store {
            let id = "fs-" + UUID().uuidString.prefix(8).lowercased()
            let start = startedAt ?? Date()
            if store.act(Self.session(id: id, title: label, start: start, end: start.addingTimeInterval(Double(m) * 60), status: "running", store: store), quiet: true) { sessionID = id }
        }
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
        let l = label, sid = sessionID
        var last = activityState; last.done = complete; last.remaining = 0
        startedAt = nil; pausedAt = nil; spent = 0; sessionID = nil; save(); cancelNotification()
        FocusActivityController.end(last, linger: complete)
        attach()
        guard let store else { return }
        // The study session ends now (or keeps its planned end when it ran to the end).
        var ops: [JSON] = []
        if let sid, mins >= 1 {
            var v: JSON = ["id": .string(sid), "status": .string(complete ? "done" : "ended"), "minutes": JSON(mins)]
            if !complete { v["end"] = .string(Self.hhmm(Date(), store: store)) }
            ops.append(["op": "content.upsert", "path": "sessions", "value": v])
        }
        if mins >= 1 {
            ops.append(["op": "focus.log", "date": .string(store.today), "minutes": JSON(mins), "label": .string(l)])
            store.act(ops, undo: "\(mins) min of study logged")
        } else {
            if let sid { store.act(["op": "content.remove", "path": "sessions", "id": .string(sid)], quiet: true) }
            store.show("Session ended")
        }
    }

    /// A focus run as a study session: {id, date, start, end, title, status, minutes} under content.sessions.
    static func session(id: String, title: String, start: Date, end: Date, status: String, store: Store) -> JSON {
        let v: JSON = ["id": .string(id), "date": .string(store.dayKey(start)), "start": .string(hhmm(start, store: store)), "end": .string(hhmm(max(end, start.addingTimeInterval(60)), store: store)),
                       "title": .string(title), "status": .string(status), "at": .now]
        return ["op": "content.upsert", "path": "sessions", "value": v]
    }
    static func hhmm(_ d: Date, store: Store) -> String {
        let f = DateFormatter(); f.calendar = store.cal; f.timeZone = store.tz; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"
        return f.string(from: d)
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
