import Foundation

/// The built-in planner, used when Instinct is offline or you ask for a plan yourself.
/// It works earliest-deadline-first, weighted by priority, spreads each piece of work over the days before it's due,
/// keeps to your free windows, busy times, daily maximum, block length and breaks, and adds a short card review each day.
struct AutoPlanner {
    struct Interval: Equatable { var start: Date; var end: Date
        var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    }

    struct Task {
        var id: UUID
        var title: String
        var subjectID: UUID?
        var subjectName: String?
        var kind: String              // homework | project | test | exam | revision
        var due: Date?
        var remainingMinutes: Int
        var priority: String          // low | medium | high | urgent
        var chapterIDs: [UUID] = []
    }

    /// A regular weekly window, in minutes after midnight on that weekday (0 = Sunday).
    struct Window { var weekday: Int; var start: Int; var end: Int; var free: Bool }

    struct Prefs {
        var maxMinutesPerDay = 240
        var blockMinutes = 50
        var breakMinutes = 10
        var noStudyDays: Set<Int> = []   // 0 = Sunday … 6 = Saturday
        var earliest = 8 * 60
        var latest = 22 * 60
        var reviewMinutes = 15
    }

    struct Draft: Equatable {
        var start: Date
        var end: Date
        var kind: String              // study | revision | review | practice
        var subjectID: UUID?
        var assignmentID: UUID?
        var deckID: UUID?
        var chapterIDs: [UUID] = []
        var goal: String
        var reason: String
    }

    struct Output { var drafts: [Draft]; var warnings: [String] }

    var now: Date
    var days = 14
    var tasks: [Task]
    var windows: [Window]
    var busy: [Interval]
    /// Blocks that stay (done, yours, or ones not being replaced): planned around, and counted towards each day's limit.
    var keep: [Interval]
    var prefs: Prefs
    /// Cards due now and whether any deck exists; a daily review block is added while there's something to review.
    var reviewDeck: (id: UUID?, subjectID: UUID?, dueNow: Int, total: Int)? = nil
    var calendar: Calendar = .current

    private func weight(_ p: String) -> Double {
        switch p { case "urgent": return 3; case "high": return 2; case "low": return 0.6; default: return 1 }
    }

    // MARK: Free time

    /// The free time on one day after windows, limits, busy times and kept blocks.
    func freeTime(on day: Date) -> [Interval] {
        let start = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: start) - 1
        if prefs.noStudyDays.contains(weekday) { return [] }
        func at(_ minutes: Int) -> Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }

        let freeWindows = windows.filter { $0.free }
        var free: [Interval]
        if freeWindows.isEmpty {
            free = [Interval(start: at(prefs.earliest), end: at(prefs.latest))]
        } else {
            free = freeWindows.filter { $0.weekday == weekday }.map { Interval(start: at(max($0.start, prefs.earliest)), end: at(min($0.end, prefs.latest))) }
        }
        free = free.filter { $0.end > $0.start }
        var blocked = windows.filter { !$0.free && $0.weekday == weekday }.map { Interval(start: at($0.start), end: at($0.end)) }
        let pad = TimeInterval(prefs.breakMinutes * 60)
        blocked += busy
        blocked += keep.map { Interval(start: $0.start.addingTimeInterval(-pad), end: $0.end.addingTimeInterval(pad)) }
        // Nothing in the past: today starts at the next quarter hour.
        let soon = Self.roundUp(now.addingTimeInterval(5 * 60), minutes: 15, calendar: calendar)
        blocked.append(Interval(start: start, end: max(start, soon)))
        return Self.subtract(free.sorted { $0.start < $1.start }, blocked)
    }

    static func subtract(_ base: [Interval], _ minus: [Interval]) -> [Interval] {
        var out = base
        for m in minus where m.end > m.start {
            var next: [Interval] = []
            for b in out {
                if m.end <= b.start || m.start >= b.end { next.append(b); continue }
                if m.start > b.start { next.append(Interval(start: b.start, end: m.start)) }
                if m.end < b.end { next.append(Interval(start: m.end, end: b.end)) }
            }
            out = next
        }
        return out.filter { $0.end.timeIntervalSince($0.start) >= 60 }.sorted { $0.start < $1.start }
    }

    static func roundUp(_ d: Date, minutes: Int, calendar: Calendar) -> Date {
        let step = TimeInterval(minutes * 60)
        let start = calendar.startOfDay(for: d)
        return start.addingTimeInterval((d.timeIntervalSince(start) / step).rounded(.up) * step)
    }

    // MARK: Planning

    func plan() -> Output {
        var drafts: [Draft] = []
        var warnings: [String] = []
        var left: [UUID: Int] = [:]
        for t in tasks where t.remainingMinutes > 0 { left[t.id] = t.remainingMinutes }
        let today = calendar.startOfDay(for: now)
        let minBlock = 20

        for offset in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            var free = freeTime(on: day)
            if free.isEmpty { continue }
            let kept = keep.filter { $0.start >= day && $0.start < dayEnd }.reduce(0) { $0 + $1.minutes }
            var budget = prefs.maxMinutesPerDay - kept
            if budget < minBlock { continue }

            // A short review of due cards, in the evening.
            if let deck = reviewDeck, deck.total > 0, (offset > 0 || deck.dueNow > 0), budget >= prefs.reviewMinutes {
                let length = offset == 0 ? min(30, max(prefs.reviewMinutes, deck.dueNow / 2)) : prefs.reviewMinutes
                if let i = free.lastIndex(where: { $0.minutes >= length }) {
                    let end = free[i].end
                    let start = end.addingTimeInterval(-TimeInterval(length * 60))
                    drafts.append(Draft(start: start, end: end, kind: "review", subjectID: deck.subjectID, assignmentID: nil, deckID: deck.id,
                                        goal: offset == 0 ? "Review \(deck.dueNow) due cards" : "Daily card review",
                                        reason: "Spaced repetition works best a little every day."))
                    budget -= length
                    free = Self.subtract(free, [Interval(start: start.addingTimeInterval(-TimeInterval(prefs.breakMinutes * 60)), end: end)])
                }
            }

            // Each task's fair share today: what's left spread over the study days before it's due.
            var share: [UUID: Int] = [:]
            var urgent: Set<UUID> = []
            for t in tasks {
                guard let rem = left[t.id], rem > 0 else { continue }
                let due = t.due ?? calendar.date(byAdding: .day, value: days, to: today)!
                if due <= day { share[t.id] = rem; urgent.insert(t.id); continue }
                let studyDays = max(1, studyDaysBetween(day, due))
                // Tests and exams get their revision finished a day early.
                let spread = (t.kind == "test" || t.kind == "exam") ? max(1, studyDays - 1) : studyDays
                share[t.id] = Int((Double(rem) / Double(spread)).rounded(.up))
                if due.timeIntervalSince(day) < 2 * 86400 { urgent.insert(t.id) }
            }
            var givenToday: [UUID: Int] = [:]

            var slotIndex = 0
            while slotIndex < free.count && budget >= minBlock {
                let slot = free[slotIndex]
                var cursor = slot.start
                while slot.end.timeIntervalSince(cursor) >= TimeInterval(minBlock * 60) && budget >= minBlock {
                    let available = min(Int(slot.end.timeIntervalSince(cursor) / 60), budget, prefs.blockMinutes)
                    let candidates = tasks.filter { t in
                        guard let rem = left[t.id], rem > 0 else { return false }
                        if let due = t.due, due <= cursor.addingTimeInterval(TimeInterval(minBlock * 60)) { return false }
                        let used = givenToday[t.id] ?? 0
                        return used < (share[t.id] ?? 0) || urgent.contains(t.id)
                    }
                    guard let pick = candidates.max(by: { score($0, at: cursor, left: left) < score($1, at: cursor, left: left) }) else { break }
                    let rem = left[pick.id] ?? 0
                    var length = min(available, Self.roundTo5(max(minBlock, rem)))
                    if let due = pick.due { length = min(length, Int(due.timeIntervalSince(cursor) / 60)) }
                    if length < minBlock { break }
                    let end = cursor.addingTimeInterval(TimeInterval(length * 60))
                    let isRevision = pick.kind == "test" || pick.kind == "exam" || pick.kind == "revision"
                    drafts.append(Draft(start: cursor, end: end, kind: isRevision ? "revision" : "study", subjectID: pick.subjectID,
                                        assignmentID: pick.id, deckID: nil, chapterIDs: pick.chapterIDs,
                                        goal: goal(for: pick, minutes: length, remaining: rem),
                                        reason: reason(for: pick, remaining: rem)))
                    left[pick.id] = max(0, rem - length)
                    givenToday[pick.id, default: 0] += length
                    budget -= length
                    cursor = end.addingTimeInterval(TimeInterval(prefs.breakMinutes * 60))
                }
                slotIndex += 1
            }
        }

        for t in tasks {
            if let rem = left[t.id], rem >= 15 {
                let h = Double(rem) / 60
                let when = t.due.map { " before it's due " + Self.dayName($0, calendar: calendar) } ?? ""
                warnings.append("\(t.title): \(String(format: h >= 1 ? "%.1f h" : "%.0f min", h >= 1 ? h : Double(rem))) didn't fit\(when). Free up time or move the deadline.")
            }
        }
        return Output(drafts: drafts.sorted { $0.start < $1.start }, warnings: warnings)
    }

    private func score(_ t: Task, at time: Date, left: [UUID: Int]) -> Double {
        let rem = Double(left[t.id] ?? 0)
        let hoursLeft = max(1, (t.due ?? time.addingTimeInterval(TimeInterval(days) * 86400)).timeIntervalSince(time) / 3600)
        // Pressure: how much of the time before the deadline this work needs, times how much it matters.
        return weight(t.priority) * (rem / 60 + 0.5) / hoursLeft * 100 + (t.due == nil ? 0 : 0.01)
    }

    private func studyDaysBetween(_ from: Date, _ due: Date) -> Int {
        var n = 0
        var d = calendar.startOfDay(for: from)
        while d < due && n < 60 {
            let weekday = calendar.component(.weekday, from: d) - 1
            if !prefs.noStudyDays.contains(weekday) { n += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return n
    }

    private func goal(for t: Task, minutes: Int, remaining: Int) -> String {
        switch t.kind {
        case "test", "exam": return "Revise for \(t.title)"
        case "revision": return t.title
        case "project": return remaining <= minutes ? "Finish \(t.title)" : "Work on \(t.title)"
        default: return remaining <= minutes ? "Finish \(t.title)" : "\(t.title) — \(minutes) min"
        }
    }

    private func reason(for t: Task, remaining: Int) -> String {
        let h = Double(remaining) / 60
        let left = h >= 1 ? String(format: "%.1f h left", h) : "\(remaining) min left"
        guard let due = t.due else { return "\(left), no deadline." }
        return "Due \(Self.dayName(due, calendar: calendar)), \(left)\(t.priority == "high" || t.priority == "urgent" ? ", \(t.priority) priority" : "")."
    }

    static func roundTo5(_ m: Int) -> Int { Int((Double(m) / 5).rounded(.up)) * 5 }

    static func dayName(_ d: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }
}
