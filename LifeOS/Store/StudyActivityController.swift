import Foundation
import ActivityKit

/// Keeps the study block Live Activity in step with your timetable: it appears 10 minutes before a study block,
/// shows the topic and time left during it, turns into a break between blocks, and says "done" at the end.
/// iOS only lets an app start a Live Activity while it's open, so it starts the next time LifeOS is on screen inside
/// those 10 minutes (or the next study block's lead time). Once it's up, the countdown and the switch from "starts in"
/// to "time left" run on their own; breaks and the end are updated whenever LifeOS runs, in the foreground or background.
/// A running focus session has its own Live Activity, so this one steps aside.
@MainActor
enum StudyActivityController {
    static let lead: TimeInterval = 10 * 60
    private typealias State = StudyBlockAttributes.ContentState

    static func refresh(_ store: Store) {
        let now = Date()
        let blocks = store.timeline.filter { StudyAlerts.isStudy($0) && !$0.id.hasPrefix("fs-") }
        let current = blocks.first { $0.start <= now && now < $0.end }
        let next = blocks.first { $0.start > now }
        var want: (id: String, state: State, stale: Date)?

        if FocusTimer.shared.running {
            want = nil
        } else if let c = current {
            if let until = StudyLock.until, until > now, until < c.end {
                want = (c.id, State(phase: .rest, title: c.title, start: until, end: c.end, note: "Break"), until)
            } else {
                want = (c.id, State(phase: .during, title: c.title, start: c.start, end: c.end), c.end)
            }
        } else if let n = next {
            let wait = n.start.timeIntervalSince(now)
            let justFinished = blocks.last { $0.end <= now }.map { now.timeIntervalSince($0.end) < 15 * 60 } ?? false
            if wait <= lead {
                want = (n.id, State(phase: .upcoming, title: n.title, start: n.start, end: n.end), n.start)
            } else if justFinished && wait <= 60 * 60 {
                want = (n.id, State(phase: .rest, title: n.title, start: n.start, end: n.end, note: "Break · next up"), n.start)
            }
        }
        apply(want)
    }

    private static func apply(_ want: (id: String, state: State, stale: Date)?) {
        let running = Activity<StudyBlockAttributes>.activities
        Task {
            var kept = false
            for a in running {
                if let want, a.attributes.blockID == want.id, !kept {
                    kept = true
                    if a.content.state != want.state { await a.update(ActivityContent(state: want.state, staleDate: want.stale)) }
                } else {
                    // A block that was on lingers as "done" for a few minutes; one that never started just goes.
                    var last = a.content.state
                    let wasOn = last.phase == .during || last.shown(at: Date(), stale: false) != .upcoming
                    last.phase = .ended
                    await a.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: wasOn ? .after(Date().addingTimeInterval(5 * 60)) : .immediate)
                }
            }
            guard let want, !kept, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: StudyBlockAttributes(blockID: want.id), content: ActivityContent(state: want.state, staleDate: want.stale), pushType: nil)
        }
    }

    /// Ends every study block activity straight away (a focus session took over).
    static func endAll() {
        Task { for a in Activity<StudyBlockAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
