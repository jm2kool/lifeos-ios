import Foundation
import SwiftUI

// The timetable model shared by the iPhone and Apple Watch apps. Everything lives on the devices;
// the phone sends a copy to the watch over WatchConnectivity, so no internet connection is needed.

/// A colour a subject is shown in.
enum SubjectColour: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        }
    }
}

/// A subject you take, with where it usually is and what to bring to it.
struct Subject: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var room: String = ""
    var teacher: String = ""
    var colour: SubjectColour = .blue
    var bring: [String] = []
}

/// One slot in the timetable: a subject on a weekday, between two times.
struct Lesson: Identifiable, Codable, Hashable {
    var id = UUID()
    var subjectID: UUID
    /// The weekday as `Calendar` counts them: 1 is Sunday, 2 is Monday … 7 is Saturday.
    var weekday: Int
    /// 0 for Week A, 1 for Week B. Ignored unless the timetable runs over two weeks.
    var week: Int = 0
    /// Minutes after midnight.
    var start: Int
    var end: Int
    /// A room for just this lesson, when it isn't the subject's usual one.
    var room: String = ""
}

/// A piece of homework, or anything else that has to be handed in.
struct Assignment: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var subjectID: UUID?
    var due: Date
    var done = false
}

/// Everything the apps know: subjects, lessons and homework.
struct Timetable: Codable, Equatable {
    var subjects: [Subject] = []
    var lessons: [Lesson] = []
    var assignments: [Assignment] = []
    /// The weekdays school runs on (`Calendar` numbering).
    var schoolDays: [Int] = [2, 3, 4, 5, 6]
    var twoWeeks = false
    /// The start of any week that is a Week A.
    var weekAStart: Date = Timetable.startOfWeek(.now)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subjects = try c.decodeIfPresent([Subject].self, forKey: .subjects) ?? []
        lessons = try c.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
        assignments = try c.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
        schoolDays = try c.decodeIfPresent([Int].self, forKey: .schoolDays) ?? [2, 3, 4, 5, 6]
        twoWeeks = try c.decodeIfPresent(Bool.self, forKey: .twoWeeks) ?? false
        weekAStart = try c.decodeIfPresent(Date.self, forKey: .weekAStart) ?? Timetable.startOfWeek(.now)
    }

    var isEmpty: Bool { lessons.isEmpty && subjects.isEmpty && assignments.isEmpty }

    func subject(_ id: UUID?) -> Subject? {
        guard let id else { return nil }
        return subjects.first { $0.id == id }
    }

    static func startOfWeek(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    /// 0 if the date falls in a Week A, 1 for a Week B.
    func weekIndex(on date: Date) -> Int {
        guard twoWeeks else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Self.startOfWeek(weekAStart), to: Self.startOfWeek(date)).day ?? 0
        let weeks = Int((Double(days) / 7).rounded())
        return ((weeks % 2) + 2) % 2
    }

    /// The lessons for one weekday of the timetable, in order.
    func lessons(weekday: Int, week: Int) -> [Lesson] {
        lessons
            .filter { $0.weekday == weekday && (!twoWeeks || $0.week == week) }
            .sorted { $0.start < $1.start }
    }

    /// The lessons on a real date, with their times on that day.
    func slots(on date: Date) -> [Slot] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return lessons(weekday: cal.component(.weekday, from: date), week: weekIndex(on: date)).map { lesson in
            Slot(lesson: lesson,
                 subject: subject(lesson.subjectID),
                 start: cal.date(byAdding: .minute, value: lesson.start, to: day) ?? day,
                 end: cal.date(byAdding: .minute, value: lesson.end, to: day) ?? day)
        }
    }

    /// The next day after `date` that has lessons.
    func nextSchoolDay(after date: Date) -> Date? {
        let cal = Calendar.current
        var day = cal.startOfDay(for: date)
        for _ in 0..<21 {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
            if !slots(on: day).isEmpty { return day }
        }
        return nil
    }

    /// When a subject is next taught after a moment, for "due next lesson".
    func nextLesson(of subjectID: UUID, after date: Date) -> Date? {
        let cal = Calendar.current
        var day = cal.startOfDay(for: date)
        for _ in 0..<21 {
            if let slot = slots(on: day).first(where: { $0.lesson.subjectID == subjectID && $0.start > date }) {
                return slot.start
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }

    /// Homework still to do, soonest first.
    var openAssignments: [Assignment] {
        assignments.filter { !$0.done }.sorted { $0.due < $1.due }
    }

    /// Homework due on a given day that isn't done yet.
    func due(on day: Date) -> [Assignment] {
        openAssignments.filter { Calendar.current.isDate($0.due, inSameDayAs: day) }
    }
}

/// A lesson placed on a real day.
struct Slot: Identifiable, Hashable {
    let lesson: Lesson
    let subject: Subject?
    let start: Date
    let end: Date

    var id: UUID { lesson.id }
    var name: String { subject?.name ?? "Lesson" }
    var room: String { lesson.room.isEmpty ? (subject?.room ?? "") : lesson.room }
    var teacher: String { subject?.teacher ?? "" }
    var colour: Color { (subject?.colour ?? .blue).color }
    var bring: [String] { subject?.bring ?? [] }

    func isNow(_ now: Date) -> Bool { start <= now && now < end }

    /// How far through the lesson we are, from 0 to 1.
    func progress(_ now: Date) -> Double {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / length, 0), 1)
    }
}

/// What to pack for one subject.
struct PackGroup: Identifiable {
    let subject: Subject
    let items: [String]
    var id: UUID { subject.id }
}

/// The day at a moment: the lesson on now, what's next, and what to pack.
struct DayPlan {
    let now: Date
    /// Today's lessons, in order.
    let slots: [Slot]
    let current: Slot?
    let upcoming: [Slot]
    /// The school day to pack for: today before school starts, otherwise the next school day.
    let packDay: Date?
    let packSlots: [Slot]
    let handIn: [Assignment]

    init(_ timetable: Timetable, now: Date) {
        self.now = now
        let today = timetable.slots(on: now)
        slots = today
        current = today.first { $0.isNow(now) }
        upcoming = today.filter { $0.start > now }
        let day: Date?
        if let first = today.first, now < first.start {
            day = Calendar.current.startOfDay(for: now)
        } else {
            day = timetable.nextSchoolDay(after: now)
        }
        packDay = day
        packSlots = day.map { timetable.slots(on: $0) } ?? []
        handIn = day.map { timetable.due(on: $0) } ?? []
    }

    /// The lesson to open on: the one on now, otherwise the next one.
    var focus: Slot? { current ?? upcoming.first }

    var isOver: Bool { !slots.isEmpty && focus == nil }

    /// The subjects for the pack day, once each, with what to bring.
    var packGroups: [PackGroup] {
        var seen = Set<UUID>()
        return packSlots.compactMap { slot in
            guard let subject = slot.subject, seen.insert(subject.id).inserted else { return nil }
            return PackGroup(subject: subject, items: subject.bring)
        }
    }

    /// A word for a lesson's place in the day.
    func label(for slot: Slot) -> String {
        if slot.isNow(now) { return "NOW" }
        if slot.end <= now { return "DONE" }
        if slot.id == upcoming.first?.id { return current == nil && slot.id == slots.first?.id ? "FIRST" : "NEXT" }
        return "LATER"
    }

    var packTitle: String {
        guard let packDay else { return "Pack" }
        return "Pack for \(Clock.relativeDay(packDay, now: now).lowercasedIfRelative)"
    }
}

/// Times and days written the way the apps show them.
enum Clock {
    /// Weekdays with Monday first.
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func range(_ start: Date, _ end: Date) -> String { "\(time(start))–\(time(end))" }

    static func date(minutes: Int, on day: Date = .now) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .minute, value: minutes, to: cal.startOfDay(for: day)) ?? day
    }

    static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func text(minutes: Int) -> String { time(date(minutes: minutes)) }

    static func dayName(_ weekday: Int, short: Bool = false) -> String {
        let names = short ? Calendar.current.shortWeekdaySymbols : Calendar.current.weekdaySymbols
        return names[((weekday - 1) % 7 + 7) % 7]
    }

    /// "Today", "Tomorrow", a weekday this week, or a date further out.
    static func relativeDay(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2..<7: return dayName(cal.component(.weekday, from: date))
        default: return date.formatted(.dateTime.weekday(.abbreviated).day().month())
        }
    }

    static func isOverdue(_ date: Date, now: Date = .now) -> Bool {
        date < Calendar.current.startOfDay(for: now)
    }
}

extension String {
    /// "Today" and "Tomorrow" read better in lower case mid-sentence; weekday names keep their capital.
    var lowercasedIfRelative: String {
        ["Today", "Tomorrow", "Yesterday"].contains(self) ? lowercased() : self
    }
}

/// Keys for the messages the phone and watch send each other.
enum SyncKey {
    static let timetable = "timetable"
    static let toggle = "toggle"
    static let done = "done"
    static let request = "request"
    static let sent = "sent"
}

extension Timetable {
    /// A made-up school week, so there's something to look at straight away.
    /// With `around`, every day's lessons are shifted so a lesson is on at that moment (for screenshots).
    static func example(around now: Date? = nil) -> Timetable {
        let maths = Subject(name: "Maths", room: "B12", teacher: "Mr Shah", colour: .blue, bring: ["Calculator", "Maths textbook"])
        let english = Subject(name: "English", room: "A4", teacher: "Ms Clarke", colour: .purple, bring: ["Macbeth"])
        let science = Subject(name: "Science", room: "Lab 2", teacher: "Dr Okafor", colour: .green, bring: ["Goggles", "Lab book"])
        let history = Subject(name: "History", room: "C3", teacher: "Mr Evans", colour: .orange, bring: ["History folder"])
        let pe = Subject(name: "PE", room: "Sports hall", teacher: "Ms Patel", colour: .red, bring: ["PE kit", "Trainers"])
        let french = Subject(name: "French", room: "A7", teacher: "Mme Dubois", colour: .pink, bring: ["French dictionary"])
        let art = Subject(name: "Art", room: "Studio", teacher: "Mr Lee", colour: .yellow, bring: ["Sketchbook"])
        let computing = Subject(name: "Computing", room: "ICT 1", teacher: "Ms Kim", colour: .teal)

        let periods = [(530, 590), (590, 650), (670, 730), (780, 840), (840, 900)]
        let days: [Int: [Subject]] = [
            2: [maths, english, science, history, pe],
            3: [french, maths, art, english, computing],
            4: [science, science, maths, pe, history],
            5: [english, french, maths, computing, art],
            6: [history, maths, english, science, french],
        ]

        var shift = 0
        var weekdays = Array(days.keys)
        if let now {
            // Put "now" twenty minutes into the second lesson, and give every day of the week lessons.
            shift = Clock.minutes(of: now) - (periods[1].0 + 20)
            weekdays = Array(1...7)
        }

        var t = Timetable()
        t.subjects = [maths, english, science, history, pe, french, art, computing]
        if now != nil { t.schoolDays = Array(1...7) }
        for weekday in weekdays {
            let subjects = days[weekday] ?? days[((weekday + 5) % 5) + 2] ?? []
            for (i, period) in periods.enumerated() where i < subjects.count {
                let start = period.0 + shift, end = period.1 + shift
                guard start >= 0, end < 24 * 60 else { continue }
                t.lessons.append(Lesson(subjectID: subjects[i].id, weekday: weekday, start: start, end: end))
            }
        }

        let base = now ?? .now
        let cal = Calendar.current
        func day(_ offset: Int) -> Date { cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: base) ?? base) }
        t.assignments = [
            Assignment(title: "Algebra worksheet", subjectID: maths.id,
                       due: t.nextLesson(of: maths.id, after: day(1)).map { cal.startOfDay(for: $0) } ?? day(1)),
            Assignment(title: "Essay plan", subjectID: english.id, due: day(2)),
            Assignment(title: "Revise for the forces test", subjectID: science.id, due: day(4)),
        ]
        return t
    }
}
