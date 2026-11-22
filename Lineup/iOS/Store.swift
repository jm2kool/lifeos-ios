import Foundation
import SwiftUI

/// Holds the timetable on the phone, saves it, and passes every change on to the watch.
@MainActor
final class Store: ObservableObject {
    @Published var timetable: Timetable {
        didSet { if timetable != oldValue { changed() } }
    }

    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("timetable.json")
    private var reminderTask: Task<Void, Never>?

    init() {
        if ProcessInfo.processInfo.environment["LINEUP_SAMPLE"] == "1" {
            timetable = .example(around: .now)
        } else if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Timetable.self, from: data) {
            timetable = saved
        } else {
            timetable = Timetable()
        }
        PhoneSync.shared.onToggle = { [weak self] id, done in self?.setDone(id, done) }
        PhoneSync.shared.current = { [weak self] in self?.timetable }
        PhoneSync.shared.start(with: timetable)
    }

    private func changed() {
        if let data = try? JSONEncoder().encode(timetable) {
            try? data.write(to: url, options: .atomic)
        }
        PhoneSync.shared.push(timetable)
        scheduleReminders()
    }

    /// Books the heads-up notifications again, a moment after the last change.
    func scheduleReminders() {
        reminderTask?.cancel()
        let timetable = timetable
        reminderTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await Reminders.reschedule(timetable)
        }
    }

    // MARK: Subjects

    func save(_ subject: Subject) {
        if let i = timetable.subjects.firstIndex(where: { $0.id == subject.id }) {
            timetable.subjects[i] = subject
        } else {
            timetable.subjects.append(subject)
        }
    }

    /// Removes a subject and every lesson of it.
    func delete(_ subject: Subject) {
        var t = timetable
        t.subjects.removeAll { $0.id == subject.id }
        t.lessons.removeAll { $0.subjectID == subject.id }
        for i in t.assignments.indices where t.assignments[i].subjectID == subject.id {
            t.assignments[i].subjectID = nil
        }
        timetable = t
    }

    // MARK: Lessons

    func save(_ lesson: Lesson) {
        if let i = timetable.lessons.firstIndex(where: { $0.id == lesson.id }) {
            timetable.lessons[i] = lesson
        } else {
            timetable.lessons.append(lesson)
        }
    }

    func delete(_ lesson: Lesson) {
        timetable.lessons.removeAll { $0.id == lesson.id }
    }

    /// Replaces one day's lessons with a copy of another's.
    func copyDay(_ weekday: Int, week: Int, to target: Int, week targetWeek: Int) {
        var t = timetable
        let copies = t.lessons(weekday: weekday, week: week).map { lesson -> Lesson in
            var copy = lesson
            copy.id = UUID()
            copy.weekday = target
            copy.week = targetWeek
            return copy
        }
        t.lessons.removeAll { $0.weekday == target && (!t.twoWeeks || $0.week == targetWeek) }
        t.lessons += copies
        timetable = t
    }

    // MARK: Homework

    func save(_ assignment: Assignment) {
        if let i = timetable.assignments.firstIndex(where: { $0.id == assignment.id }) {
            timetable.assignments[i] = assignment
        } else {
            timetable.assignments.append(assignment)
        }
    }

    func delete(_ assignment: Assignment) {
        timetable.assignments.removeAll { $0.id == assignment.id }
    }

    func setDone(_ id: UUID, _ done: Bool) {
        guard let i = timetable.assignments.firstIndex(where: { $0.id == id }) else { return }
        timetable.assignments[i].done = done
    }

    func clearDone() {
        timetable.assignments.removeAll { $0.done }
    }
}
