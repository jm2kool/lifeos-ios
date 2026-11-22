import SwiftUI

/// The timetable itself, a day at a time.
struct WeekView: View {
    @EnvironmentObject private var store: Store
    @State private var weekday = Calendar.current.component(.weekday, from: .now)
    @State private var week = 0
    @State private var editing: Lesson?
    @State private var copyTarget: Int?

    private var days: [Int] { Clock.mondayFirst.filter { store.timetable.schoolDays.contains($0) } }
    private var lessons: [Lesson] { store.timetable.lessons(weekday: weekday, week: week) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Day", selection: $weekday) {
                        ForEach(days, id: \.self) { Text(Clock.dayName($0, short: true)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if store.timetable.twoWeeks {
                        Picker("Week", selection: $week) {
                            Text("Week A").tag(0)
                            Text("Week B").tag(1)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section(Clock.dayName(weekday)) {
                    if lessons.isEmpty {
                        Text("No lessons yet").foregroundStyle(.secondary)
                    }
                    ForEach(lessons) { lesson in
                        Button { editing = lesson } label: { LessonRow(lesson: lesson) }
                            .tint(.primary)
                    }
                    .onDelete { offsets in
                        offsets.map { lessons[$0] }.forEach(store.delete)
                    }
                    Button {
                        editing = newLesson()
                    } label: {
                        Label("Add lesson", systemImage: "plus")
                    }
                }

                if !lessons.isEmpty {
                    Section {
                        Menu {
                            ForEach(days.filter { $0 != weekday }, id: \.self) { day in
                                Button(Clock.dayName(day)) { copyTarget = day }
                            }
                        } label: {
                            Label("Copy \(Clock.dayName(weekday)) to another day", systemImage: "doc.on.doc")
                        }
                    } footer: {
                        Text("Handy when the bell times are the same every day: copy a day, then change the subjects.")
                    }
                }
            }
            .navigationTitle("Week")
            .onAppear {
                if !days.contains(weekday), let first = days.first { weekday = first }
                week = store.timetable.weekIndex(on: .now)
            }
            .sheet(item: $editing) { lesson in
                LessonEditor(lesson: lesson, isNew: !store.timetable.lessons.contains { $0.id == lesson.id })
            }
            .confirmationDialog("Replace \(copyTarget.map { Clock.dayName($0) } ?? "")'s lessons?",
                                isPresented: Binding(get: { copyTarget != nil }, set: { if !$0 { copyTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Copy") {
                    if let target = copyTarget { store.copyDay(weekday, week: week, to: target, week: week) }
                }
            }
        }
    }

    /// A new lesson that starts when the last one ends and runs as long.
    private func newLesson() -> Lesson {
        let subject = store.timetable.subjects.first?.id ?? UUID()
        if let last = lessons.last {
            let length = max(last.end - last.start, 30)
            return Lesson(subjectID: subject, weekday: weekday, week: week, start: last.end, end: min(last.end + length, 24 * 60 - 1))
        }
        return Lesson(subjectID: subject, weekday: weekday, week: week, start: 530, end: 590)
    }
}

/// A lesson in the week list.
struct LessonRow: View {
    @EnvironmentObject private var store: Store
    let lesson: Lesson

    var body: some View {
        let subject = store.timetable.subject(lesson.subjectID)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill((subject?.colour ?? .blue).color).frame(width: 6, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(subject?.name ?? "Lesson").font(.headline)
                let room = lesson.room.isEmpty ? (subject?.room ?? "") : lesson.room
                if !room.isEmpty { Text(room).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
            Text("\(Clock.text(minutes: lesson.start))–\(Clock.text(minutes: lesson.end))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Adds or changes one lesson.
struct LessonEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var lesson: Lesson
    @State private var start: Date
    @State private var end: Date
    @State private var newSubject = ""
    let isNew: Bool

    init(lesson: Lesson, isNew: Bool) {
        _lesson = State(initialValue: lesson)
        _start = State(initialValue: Clock.date(minutes: lesson.start))
        _end = State(initialValue: Clock.date(minutes: lesson.end))
        self.isNew = isNew
    }

    private var hasSubject: Bool {
        store.timetable.subject(lesson.subjectID) != nil || !newSubject.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Start and end times already used elsewhere, so bell times only need typing once.
    private var knownTimes: [BellTime] {
        var seen = Set<BellTime>()
        return store.timetable.lessons
            .sorted { $0.start < $1.start }
            .map { BellTime(start: $0.start, end: $0.end) }
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subject") {
                    if !store.timetable.subjects.isEmpty {
                        Picker("Subject", selection: $lesson.subjectID) {
                            ForEach(store.timetable.subjects) { subject in
                                Text(subject.name).tag(subject.id)
                            }
                        }
                    }
                    TextField(store.timetable.subjects.isEmpty ? "Subject name" : "Or a new subject", text: $newSubject)
                }

                Section("Time") {
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    if !knownTimes.isEmpty {
                        Menu("Use times from another lesson") {
                            ForEach(knownTimes, id: \.self) { times in
                                Button("\(Clock.text(minutes: times.start))–\(Clock.text(minutes: times.end))") {
                                    start = Clock.date(minutes: times.start)
                                    end = Clock.date(minutes: times.end)
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Room, if not the usual one", text: $lesson.room)
                }

                if !isNew {
                    Section {
                        Button("Delete lesson", role: .destructive) {
                            store.delete(lesson)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New lesson" : "Lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!hasSubject || Clock.minutes(of: end) <= Clock.minutes(of: start))
                }
            }
        }
    }

    private func save() {
        let name = newSubject.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            let colours = SubjectColour.allCases
            let subject = Subject(name: name, colour: colours[store.timetable.subjects.count % colours.count])
            store.save(subject)
            lesson.subjectID = subject.id
        }
        lesson.start = Clock.minutes(of: start)
        lesson.end = Clock.minutes(of: end)
        store.save(lesson)
        dismiss()
    }
}

/// A lesson's start and end, for reusing bell times.
struct BellTime: Hashable {
    let start: Int
    let end: Int
}
