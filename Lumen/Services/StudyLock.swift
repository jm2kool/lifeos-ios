import Foundation

/// The study lock, the way LifeOS does it: a Shortcuts automation runs "Study lock check" whenever you open a
/// distracting app, and during a study block (or a focus round) that brings you straight back to Lumen. Outside
/// study time nothing happens. It works with a free Apple ID; Screen Time blocking (FocusShield) needs a paid one.
@MainActor
enum StudyLock {
    private static let enabledKey = "lock.enabled"
    private static let snoozeKey = "lock.snoozeUntil"

    /// What the lock sends you back to.
    struct Session: Equatable {
        var title: String
        var goal: String
        var subjectID: UUID?
        var blockID: UUID?
        var end: Date
        var focusing: Bool
    }

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// When the current break from the lock ends, if you're on one.
    static var snoozedUntil: Date? {
        (UserDefaults.standard.object(forKey: snoozeKey) as? Date).flatMap { $0 > Date() ? $0 : nil }
    }

    static func snooze(minutes: Int) {
        UserDefaults.standard.set(Date().addingTimeInterval(Double(minutes) * 60), forKey: snoozeKey)
        StudyActivity.refresh()
    }

    static func clearSnooze() { UserDefaults.standard.removeObject(forKey: snoozeKey) }

    /// The study happening right now: a running focus round, or a planned block whose time it is.
    static func current(now: Date = Date()) -> Session? {
        let timer = FocusTimer.shared
        let store = Store.shared
        if timer.active, timer.phase == .focus, !timer.waiting {
            return Session(title: timer.context.title, goal: timer.context.goal, subjectID: timer.context.subjectID,
                           blockID: timer.context.blockID, end: now.addingTimeInterval(timer.remaining(at: now)), focusing: true)
        }
        guard let b = store.live(StudyBlock.self).first(where: { $0.status == .planned && $0.startAt <= now && now < $0.endAt }) else { return nil }
        let title = store.find(Assignment.self, b.assignmentID)?.title ?? (b.goal.isEmpty ? b.kind.label : b.goal)
        return Session(title: title, goal: b.goal, subjectID: b.subjectID, blockID: b.id, end: b.endAt, focusing: false)
    }

    /// What the lock should send you back to now: nothing while it's off or on a break.
    static var locking: Session? { enabled && snoozedUntil == nil ? current() : nil }
}
