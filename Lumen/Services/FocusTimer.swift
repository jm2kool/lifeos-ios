import Foundation
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

/// The Pomodoro timer. It keeps running with the app closed: a notification marks the end of each phase,
/// the Live Activity counts down on the Lock Screen, and the state is restored when the app comes back.
/// Focus phases flow into their break by themselves; after a break it waits for you to start the next round.
@Observable @MainActor
final class FocusTimer {
    static let shared = FocusTimer()

    enum Phase: String, Codable { case focus, short, long
        var label: String {
            switch self {
            case .focus: return "Focus"
            case .short: return "Short break"
            case .long: return "Long break"
            }
        }
        var isBreak: Bool { self != .focus }
    }

    /// What this session is for. Starting from a study block fills it in.
    struct Context: Codable, Equatable {
        var title: String = "Focus"
        var subjectID: UUID?
        var assignmentID: UUID?
        var blockID: UUID?
        var deckID: UUID?
        var goal: String = ""
    }

    /// A finished session waiting for "done / partly / not done".
    struct Finished: Codable, Identifiable, Equatable {
        var id = UUID()
        var context: Context
        var start: Date
        var end: Date
        var minutes: Int
    }

    private struct Saved: Codable {
        var context: Context
        var phase: Phase
        var phaseEnd: Date?
        var remaining: TimeInterval
        var phaseLength: TimeInterval
        var round: Int
        var sessionStart: Date?
        var banked: TimeInterval
        var active: Bool
        var awaiting: Bool
        var finished: Finished?
    }

    var context = Context()
    private(set) var phase: Phase = .focus
    /// When the current phase ends; nil while paused or waiting.
    private(set) var phaseEnd: Date?
    /// Time left while paused or waiting.
    private(set) var pausedRemaining: TimeInterval = 25 * 60
    private(set) var phaseLength: TimeInterval = 25 * 60
    private(set) var round = 1
    private(set) var sessionStart: Date?
    /// Focus time from earlier rounds in this session.
    private(set) var banked: TimeInterval = 0
    /// A session is under way (running, paused, on a break or waiting for the next round).
    private(set) var active = false
    /// After a break, waiting for you to start the next round.
    private(set) var waiting = false
    var finished: Finished? { didSet { persist() } }

    private init() { restore() }

    // MARK: Settings (from your synced preferences)

    var focusMinutes: Int { max(1, Store.shared.prefs.pomodoroFocus) }
    var shortMinutes: Int { max(1, Store.shared.prefs.pomodoroShort) }
    var longMinutes: Int { max(1, Store.shared.prefs.pomodoroLong) }
    var rounds: Int { max(1, Store.shared.prefs.pomodoroRounds) }

    // MARK: Reading

    var running: Bool { phaseEnd != nil }
    var paused: Bool { active && phaseEnd == nil && !waiting }
    func remaining(at now: Date = Date()) -> TimeInterval { phaseEnd.map { max(0, $0.timeIntervalSince(now)) } ?? pausedRemaining }
    func progress(at now: Date = Date()) -> Double { phaseLength > 0 ? min(1, max(0, 1 - remaining(at: now) / phaseLength)) : 0 }
    /// Focus time so far in this session, in seconds.
    func focused(at now: Date = Date()) -> TimeInterval { banked + (phase == .focus && active ? phaseLength - remaining(at: now) : 0) }

    // MARK: Control

    /// Fills the timer in from a block, without starting it.
    func prepare(block b: StudyBlock) {
        guard !active else { return }
        let store = Store.shared
        let a = store.find(Assignment.self, b.assignmentID)
        context = Context(title: a?.title ?? (b.goal.isEmpty ? b.kind.label : b.goal), subjectID: b.subjectID, assignmentID: b.assignmentID,
                          blockID: b.id, deckID: b.deckID, goal: b.goal)
        let left = b.endAt.timeIntervalSince(max(Date(), b.startAt))
        phaseLength = TimeInterval(focusMinutes * 60)
        if left > 5 * 60 && left < phaseLength { phaseLength = (left / 60).rounded() * 60 }
        pausedRemaining = phaseLength
        persist()
    }

    func prepare(assignment a: Assignment) {
        guard !active else { return }
        context = Context(title: a.title, subjectID: a.subjectID, assignmentID: a.id, blockID: nil, deckID: nil, goal: "")
        persist()
    }

    func start() {
        let now = Date()
        if !active {
            active = true
            sessionStart = now
            banked = 0
            round = 1
            phase = .focus
            if phaseLength <= 0 || pausedRemaining <= 0 { phaseLength = TimeInterval(focusMinutes * 60); pausedRemaining = phaseLength }
            if let b = Store.shared.find(StudyBlock.self, context.blockID), b.status == .planned, b.startAt > now {
                // Starting early: the block moves to now, keeping its length.
                let length = b.endAt.timeIntervalSince(b.startAt)
                b.startAt = now
                b.endAt = now.addingTimeInterval(length)
                b.touch()
                Store.shared.save()
            }
            FocusShield.shared.engage()
        }
        waiting = false
        phaseEnd = now.addingTimeInterval(pausedRemaining)
        Haptics.start()
        afterChange()
    }

    func togglePause() {
        guard active else { return }
        if waiting { start(); return }
        if let end = phaseEnd {
            pausedRemaining = max(0, end.timeIntervalSinceNow)
            phaseEnd = nil
        } else {
            phaseEnd = Date().addingTimeInterval(pausedRemaining)
        }
        Haptics.tap()
        afterChange()
    }

    /// Ends the current phase now and moves on.
    func skip() {
        guard active else { return }
        advance(at: Date(), early: true)
        afterChange()
    }

    /// Changes the length of the current phase before it starts.
    func setLength(minutes: Int) {
        guard !running else { return }
        phaseLength = TimeInterval(max(1, minutes) * 60)
        pausedRemaining = phaseLength
        persist()
    }

    /// Stops the session and asks how it went.
    func finish(askOutcome: Bool = true) {
        guard active else { return }
        let now = Date()
        let minutes = Int((focused(at: now) / 60).rounded())
        let f = Finished(context: context, start: sessionStart ?? now, end: now, minutes: minutes)
        reset()
        if askOutcome && (minutes > 0 || f.context.blockID != nil) { finished = f }
        Haptics.success()
    }

    /// Saves how it went (and reports it to Instinct through sync).
    func record(_ f: Finished, outcome: Outcome?, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Store.shared.logFocus(start: f.start, end: f.end, minutes: f.minutes, subjectID: f.context.subjectID,
                              assignmentID: f.context.assignmentID, blockID: f.context.blockID, deckID: f.context.deckID,
                              goal: f.context.goal.isEmpty ? f.context.title : f.context.goal, outcome: outcome,
                              note: trimmed.isEmpty ? nil : trimmed)
        finished = nil
        if f.minutes > 0 { Store.shared.show("\(f.minutes) min logged", symbol: "timer") }
    }

    func discard() {
        reset()
        finished = nil
    }

    private func reset() {
        active = false
        waiting = false
        phaseEnd = nil
        phase = .focus
        round = 1
        banked = 0
        sessionStart = nil
        phaseLength = TimeInterval(focusMinutes * 60)
        pausedRemaining = phaseLength
        context = Context()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["lumen.focus"])
        FocusShield.shared.release()
        FocusActivity.end()
        persist()
    }

    /// Catches up after time away: finished focus phases are banked, their breaks run on, and after a break it waits.
    func tick(now: Date = Date()) {
        guard active, let end = phaseEnd, end <= now else { return }
        advance(at: end, early: false)
        if let e2 = phaseEnd, e2 <= now { advance(at: e2, early: false) }
        afterChange()
    }

    private func advance(at moment: Date, early: Bool) {
        switch phase {
        case .focus:
            let length = early ? phaseLength - remaining(at: moment) : phaseLength
            banked += max(0, length)
            let long = round % rounds == 0
            phase = long ? .long : .short
            phaseLength = TimeInterval((long ? longMinutes : shortMinutes) * 60)
            phaseEnd = moment.addingTimeInterval(phaseLength)
            if !early { Haptics.success() }
        case .short, .long:
            round += 1
            phase = .focus
            phaseLength = TimeInterval(focusMinutes * 60)
            pausedRemaining = phaseLength
            phaseEnd = nil
            waiting = true
        }
    }

    private func afterChange() {
        persist()
        scheduleNotification()
        if active {
            FocusActivity.show(title: context.title, subject: Store.shared.subject(context.subjectID)?.name ?? "",
                               colorHex: Store.shared.subject(context.subjectID)?.color ?? "#7C8CFF", state: activityState)
        }
    }

    var activityState: FocusAttributes.ContentState {
        FocusAttributes.ContentState(phase: phase.rawValue, endDate: phaseEnd ?? Date().addingTimeInterval(pausedRemaining),
                                     paused: phaseEnd == nil, remaining: remaining(), total: phaseLength, round: round, rounds: rounds)
    }

    private func scheduleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["lumen.focus"])
        guard let end = phaseEnd, end > Date() else { return }
        let c = UNMutableNotificationContent()
        switch phase {
        case .focus:
            let long = round % rounds == 0
            c.title = "Round \(round) done"
            c.body = "Nice work on \(context.title). Take a \(long ? longMinutes : shortMinutes)-minute break."
        case .short, .long:
            c.title = "Break's over"
            c.body = "Open Lumen to start round \(round + 1) of \(context.title)."
        }
        c.sound = .default
        c.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: "lumen.focus", content: c, trigger: trigger))
    }

    // MARK: Saving across launches

    private func persist() {
        let s = Saved(context: context, phase: phase, phaseEnd: phaseEnd, remaining: pausedRemaining, phaseLength: phaseLength,
                      round: round, sessionStart: sessionStart, banked: banked, active: active, awaiting: waiting, finished: finished)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "focus.state") }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: "focus.state"), let s = try? JSONDecoder().decode(Saved.self, from: data) else {
            phaseLength = 25 * 60
            pausedRemaining = phaseLength
            return
        }
        context = s.context
        phase = s.phase
        phaseEnd = s.phaseEnd
        pausedRemaining = s.remaining
        phaseLength = s.phaseLength
        round = s.round
        sessionStart = s.sessionStart
        banked = s.banked
        active = s.active
        waiting = s.awaiting
        finished = s.finished
    }
}

/// Starts, updates and ends the focus Live Activity.
@MainActor
enum FocusActivity {
    static func show(title: String, subject: String, colorHex: String, state: FocusAttributes.ContentState) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: state.paused ? nil : state.endDate.addingTimeInterval(60))
        Task {
            if let current = Activity<FocusAttributes>.activities.first {
                await current.update(content)
            } else {
                _ = try? Activity.request(attributes: FocusAttributes(title: title, subject: subject, colorHex: colorHex), content: content, pushType: nil)
            }
        }
        #endif
    }

    static func end() {
        #if canImport(ActivityKit)
        Task {
            for a in Activity<FocusAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }
}
