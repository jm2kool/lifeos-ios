import Foundation
import WidgetKit

/// Writes what the widgets show and asks them to redraw.
@MainActor
enum WidgetBridge {
    private static var pending: Task<Void, Never>?
    private static var lastRemote: (Date, WidgetSnapshot)?

    static func scheduleRefresh() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    static func snapshot() -> WidgetSnapshot {
        let store = Store.shared
        let now = Date()
        let upcoming = store.live(StudyBlock.self).filter { $0.status == .planned && $0.endAt > now }
            .sorted { $0.startAt < $1.startAt }.prefix(6).map { b -> WidgetSnapshot.Block in
                let s = store.subject(b.subjectID)
                let title = store.find(Assignment.self, b.assignmentID)?.title ?? (b.goal.isEmpty ? b.kind.label : b.goal)
                return .init(id: b.id.lower, title: title, subject: s?.name ?? b.kind.label, colorHex: s?.color ?? "#7C8CFF",
                             start: b.startAt, end: b.endAt, kind: b.kindRaw)
            }
        let next = store.live(Assignment.self).filter { $0.isOpen && ($0.dueAt ?? .distantPast) > now }.min { $0.dueAt! < $1.dueAt! }
        let deadline = next.map { a -> WidgetSnapshot.Deadline in
            let s = store.subject(a.subjectID)
            return .init(title: a.title, subject: s?.name ?? a.kind.label, colorHex: s?.color ?? "#7C8CFF", due: a.dueAt!, kind: a.kindRaw)
        }
        return WidgetSnapshot(upcoming: Array(upcoming), todayMinutes: store.minutes(on: now), goalMinutes: store.prefs.dailyGoalMinutes,
                              streak: store.streak, deadline: deadline, dueCards: store.dueCards().count, updated: now)
    }

    static func refresh() async {
        let s = snapshot()
        SharedStore.save(s)
        WidgetCenter.shared.reloadAllTimelines()
        // The server copy is for widgets that can't see the shared folder; it's sent at most every few minutes.
        guard Auth.shared.signedIn, let device = SharedStore.deviceKey, let body = SharedStore.encodeForServer(s) else { return }
        if let (at, prev) = lastRemote, Date().timeIntervalSince(at) < 300, prev.upcoming == s.upcoming, prev.deadline == s.deadline,
           prev.todayMinutes == s.todayMinutes { return }
        if (try? await API.rpc("widget_put", ["p_device": device, "p_data": body])) != nil { lastRemote = (Date(), s) }
    }
}
