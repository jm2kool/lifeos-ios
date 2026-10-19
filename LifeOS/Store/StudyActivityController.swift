import Foundation
import ActivityKit

/// Keeps the study block Live Activity in step with your timetable: it appears 10 minutes before a study block,
/// shows the topic and time left during it, turns into a break between blocks, and says "done" at the end.
/// iOS lets the app start a Live Activity while it's open, or from a Shortcuts action (StudyBlockActivityIntent), which
/// runs without opening LifeOS. Once it's up, the countdown and the switch from "starts in" to "time left" run on their
/// own; breaks and the end are updated whenever LifeOS runs, in the foreground or background.
/// A running focus session has its own Live Activity, so this one steps aside.
@MainActor
enum StudyActivityController {
    static let lead: TimeInterval = 10 * 60
    /// iOS keeps a Live Activity active for at most 8 hours, so a block further off than this can't be shown yet.
    static let horizon: TimeInterval = 8 * 3600
    private typealias State = StudyBlockAttributes.ContentState
    private typealias Want = (id: String, state: State, stale: Date)

    /// The study blocks the activity can show: timetable and study plan, not focus sessions (they have their own).
    static func blocks(_ store: Store) -> [Block] {
        store.timeline.filter { StudyAlerts.isStudy($0) && !$0.id.hasPrefix("fs-") }
    }

    static func refresh(_ store: Store) {
        let now = Date()
        let blocks = blocks(store)
        let current = blocks.first { $0.start <= now && now < $0.end }
        let next = blocks.first { $0.start > now }
        var want: Want?

        if FocusTimer.shared.running {
            want = nil
        } else if let c = current {
            let id = StudyBlockAttributes.id(title: c.title, start: c.start)
            if let until = StudyLock.until, until > now, until < c.end {
                want = (id, State(phase: .rest, title: c.title, start: until, end: c.end, note: "Break"), until)
            } else {
                want = (id, State(phase: .during, title: c.title, start: c.start, end: c.end), c.end)
            }
        } else if let n = next {
            let id = StudyBlockAttributes.id(title: n.title, start: n.start)
            let wait = n.start.timeIntervalSince(now)
            let justFinished = blocks.last { $0.end <= now }.map { now.timeIntervalSince($0.end) < 15 * 60 } ?? false
            if wait <= lead {
                want = (id, State(phase: .upcoming, title: n.title, start: n.start, end: n.end), n.start)
            } else if justFinished && wait <= 60 * 60 {
                want = (id, State(phase: .rest, title: n.title, start: n.start, end: n.end, note: "Break · next up"), n.start)
            }
        }
        Task { await apply(want) }
    }

    private static func apply(_ want: Want?) async {
        let now = Date()
        var kept = false
        for a in Activity<StudyBlockAttributes>.activities {
            if let want, a.attributes.blockID == want.id, !kept {
                kept = true
                if a.content.state != want.state { await a.update(ActivityContent(state: want.state, staleDate: want.stale)) }
            } else if a.attributes.manual == true && now < a.content.state.end.addingTimeInterval(5 * 60) {
                continue   // started from Shortcuts: stays until a few minutes after its own end
            } else {
                await finish(a)
            }
        }
        guard let want, !kept, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(attributes: StudyBlockAttributes(blockID: want.id), content: ActivityContent(state: want.state, staleDate: want.stale), pushType: nil)
    }

    /// A block that was on lingers as "done" for a few minutes; one that never started just goes.
    private static func finish(_ a: Activity<StudyBlockAttributes>) async {
        var last = a.content.state
        let wasOn = last.phase == .during || last.shown(at: Date(), stale: false) != .upcoming
        last.phase = .ended
        await a.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: wasOn ? .after(Date().addingTimeInterval(5 * 60)) : .immediate)
    }

    /// Ends every study block activity straight away (a focus session took over).
    static func endAll() {
        Task { for a in Activity<StudyBlockAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    struct Problem: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Shows one block now: "starts in" before it, time left during it. The same block (same name and start) is updated,
    /// never shown twice. After its end, a matching activity is closed. Returns what was done, in a sentence.
    /// Used by the Shortcuts actions, which run this without opening LifeOS (pushType stays nil: no server, no paid account).
    @discardableResult
    static func show(title raw: String, start: Date, end: Date, note: String = "", manual: Bool) async throws -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw Problem(message: "Give the block a name.") }
        guard end > start else { throw Problem(message: "The block has to end after it starts.") }
        let now = Date()
        let id = StudyBlockAttributes.id(title: title, start: start)
        let existing = Activity<StudyBlockAttributes>.activities.first { $0.attributes.blockID == id }

        if now >= end {
            if let existing { await finish(existing); return "\(title) is over, so its Live Activity is closing." }
            return "\(title) already ended, so there's nothing to show."
        }
        guard start.timeIntervalSince(now) <= horizon else {
            throw Problem(message: "\(title) is more than 8 hours away. iOS only keeps a Live Activity up for 8 hours, so run this closer to the start.")
        }
        let upcoming = now < start
        let state = State(phase: upcoming ? .upcoming : .during, title: title, start: start, end: end, note: note)
        let content = ActivityContent(state: state, staleDate: upcoming ? start : end)
        let when = upcoming ? "starts \(start.formatted(date: .omitted, time: .shortened))" : "on until \(end.formatted(date: .omitted, time: .shortened))"

        if let existing {
            await existing.update(content)
            return "Updated \(title): \(when)."
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw Problem(message: "Live Activities are off for LifeOS. Turn them on in Settings › LifeOS › Live Activities.")
        }
        // Only one study block at a time on the Lock Screen: close the others (unless they're still on).
        for a in Activity<StudyBlockAttributes>.activities where a.content.state.shown(at: now, stale: false) != .during { await finish(a) }
        do {
            _ = try Activity.request(attributes: StudyBlockAttributes(blockID: id, manual: manual), content: content, pushType: nil)
        } catch {
            throw Problem(message: "iOS didn't start the Live Activity: \(error.localizedDescription)")
        }
        return "Showing \(title) on your Lock Screen: \(when)."
    }

    /// The block "Show next study block" should show: the one on now, or the next one today or tomorrow.
    static func nextBlock(_ store: Store) -> Block? {
        let now = Date()
        return blocks(store).first { $0.end > now && $0.start.timeIntervalSince(now) <= horizon }
    }
}
