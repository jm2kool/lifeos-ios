import Foundation
import ActivityKit

/// Keeps the study block Live Activity (Lock Screen and Dynamic Island) in step with your plan: it appears 10 minutes
/// before a block, shows the goal and time left during it, turns into a break between blocks, and says "done" at the end.
/// The app starts it while it runs (in the foreground, from Background App Refresh, a push, or the "Show next study
/// block" Shortcut). With push set up, the server also starts it before a block even if Lumen hasn't run.
/// A running focus session has its own Live Activity, so this one steps aside.
@MainActor
enum StudyActivity {
    static let lead: TimeInterval = 10 * 60
    /// iOS keeps a Live Activity going for at most 8 hours.
    static let horizon: TimeInterval = 8 * 3600
    private typealias State = StudyBlockAttributes.ContentState
    private struct Want { var id: String; var state: State; var stale: Date }
    private static var pending: Task<Void, Never>?
    private static var watching = Set<String>()

    /// Started from Shortcuts: kept until its block is over even if it's further off than the usual 10 minutes.
    private static var manual: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: "la.manual") as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue.filter { $0.value > Date() }, forKey: "la.manual") }
    }

    private static func planned(now: Date) -> [StudyBlock] {
        Store.shared.live(StudyBlock.self).filter { $0.status == .planned && $0.endAt > now.addingTimeInterval(-15 * 60) }.sorted { $0.startAt < $1.startAt }
    }

    private static func state(_ b: StudyBlock, phase: StudyBlockAttributes.Phase, start: Date, end: Date, note: String = "") -> State {
        let store = Store.shared
        let s = store.subject(b.subjectID)
        let title = store.find(Assignment.self, b.assignmentID)?.title ?? (b.goal.isEmpty ? b.kind.label : b.goal)
        return State(phase: phase, title: title, goal: b.goal == title ? "" : b.goal, subject: s?.name ?? b.kind.label,
                     colorHex: s?.color ?? "#8FA8FF", kind: b.kindRaw, start: start, end: end, note: note)
    }

    private static func want(now: Date) -> Want? {
        if FocusTimer.shared.active { return nil }
        let blocks = planned(now: now)
        if let c = blocks.first(where: { $0.startAt <= now && now < $0.endAt }) {
            if let until = StudyLock.snoozedUntil, until < c.endAt {
                return Want(id: c.id.lower, state: state(c, phase: .rest, start: until, end: c.endAt, note: "Break"), stale: until)
            }
            return Want(id: c.id.lower, state: state(c, phase: .during, start: c.startAt, end: c.endAt), stale: c.endAt)
        }
        guard let n = blocks.first(where: { $0.startAt > now }) else { return nil }
        let wait = n.startAt.timeIntervalSince(now)
        let manualUntil = manual[n.id.lower]
        if wait <= lead || (manualUntil != nil && wait <= horizon) {
            return Want(id: n.id.lower, state: state(n, phase: .upcoming, start: n.startAt, end: n.endAt), stale: n.startAt)
        }
        let justFinished = Store.shared.live(StudyBlock.self).contains { $0.endAt <= now && now.timeIntervalSince($0.endAt) < 15 * 60 && $0.status != .skipped }
        if justFinished && wait <= 60 * 60 {
            return Want(id: n.id.lower, state: state(n, phase: .rest, start: n.startAt, end: n.endAt, note: "Break · next up"), stale: n.startAt)
        }
        return nil
    }

    /// Brings the activity up to date (batched, so a burst of changes is one update).
    static func refresh() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await apply(want(now: Date()))
        }
    }

    private static func apply(_ want: Want?) async {
        let now = Date()
        var kept = false
        let soon = Set(planned(now: now).filter { $0.startAt.timeIntervalSince(now) <= lead + 5 * 60 && $0.endAt > now }.map(\.id.lower))
        for a in Activity<StudyBlockAttributes>.activities {
            watch(a)
            if let want, a.attributes.blockID == want.id, !kept {
                kept = true
                if a.content.state != want.state { await a.update(ActivityContent(state: want.state, staleDate: want.stale)) }
            } else if want == nil && soon.contains(a.attributes.blockID) && !FocusTimer.shared.active {
                continue   // the server started it a little early; leave it
            } else if let until = manual[a.attributes.blockID], until > now, !FocusTimer.shared.active {
                continue
            } else {
                await finish(a)
            }
        }
        guard let want, !kept, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        request(want)
    }

    private static func request(_ want: Want) {
        let content = ActivityContent(state: want.state, staleDate: want.stale)
        let attributes = StudyBlockAttributes(blockID: want.id)
        let activity: Activity<StudyBlockAttributes>?
        if Push.shared.canUpdateLiveActivities {
            activity = (try? Activity.request(attributes: attributes, content: content, pushType: .token))
                ?? (try? Activity.request(attributes: attributes, content: content, pushType: nil))
        } else {
            activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
        if let activity { watch(activity) }
    }

    /// Sends each activity's push token to the server, so it can end or update the activity later.
    private static func watch(_ a: Activity<StudyBlockAttributes>) {
        guard !watching.contains(a.id) else { return }
        watching.insert(a.id)
        let key = a.attributes.blockID
        Task {
            for await token in a.pushTokenUpdates {
                await Push.shared.upload(token: token, kind: .liveActivity, key: key)
            }
        }
    }

    /// A block that was on lingers as "done" for a few minutes; one that never started just goes.
    private static func finish(_ a: Activity<StudyBlockAttributes>) async {
        var last = a.content.state
        let wasOn = last.shown(at: Date(), stale: false) != .upcoming
        last.phase = .ended
        await a.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: wasOn ? .after(Date().addingTimeInterval(5 * 60)) : .immediate)
    }

    static func endAll() {
        Task { for a in Activity<StudyBlockAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    /// For the Shortcuts action: the block that's on now, or the next one within 8 hours.
    static func showNext() async -> String {
        let now = Date()
        guard let b = planned(now: now).first(where: { $0.endAt > now && $0.startAt.timeIntervalSince(now) <= horizon }) else {
            return "No study block in the next 8 hours."
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities are off for Lumen. Turn them on in Settings → Lumen → Live Activities."
        }
        var m = manual
        m[b.id.lower] = b.endAt
        manual = m
        await apply(want(now: now))
        let title = state(b, phase: .upcoming, start: b.startAt, end: b.endAt).title
        return b.startAt > now ? "Showing \(title), starting at \(Fmt.time(b.startAt))." : "Showing \(title) until \(Fmt.time(b.endAt))."
    }

    /// Done or Skip from the Live Activity.
    static func mark(blockID: String, status raw: String) {
        let store = Store.shared
        guard let id = UUID(uuidString: blockID), let b = store.find(StudyBlock.self, id), let status = BlockStatus(rawValue: raw) else { return }
        b.status = status
        b.touch()
        store.save()
        Task {
            for a in Activity<StudyBlockAttributes>.activities where a.attributes.blockID == blockID {
                var last = a.content.state
                last.phase = .ended
                last.note = status == .skipped ? "Skipped" : "Done"
                await a.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
            }
            refresh()
        }
    }
}
