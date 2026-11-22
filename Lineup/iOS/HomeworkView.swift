import SwiftUI

/// Homework, grouped by when it's due.
struct HomeworkView: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Assignment?

    private var groups: [DueGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let open = store.timetable.openAssignments
        func days(_ a: Assignment) -> Int { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: a.due)).day ?? 0 }
        let all = [
            DueGroup(title: "Overdue", items: open.filter { days($0) < 0 }),
            DueGroup(title: "Today", items: open.filter { days($0) == 0 }),
            DueGroup(title: "Tomorrow", items: open.filter { days($0) == 1 }),
            DueGroup(title: "This week", items: open.filter { (2..<7).contains(days($0)) }),
            DueGroup(title: "Later", items: open.filter { days($0) >= 7 }),
        ]
        return all.filter { !$0.items.isEmpty }
    }

    private var done: [Assignment] {
        store.timetable.assignments.filter(\.done).sorted { $0.due > $1.due }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.timetable.openAssignments.isEmpty {
                    ContentUnavailableView("Nothing to do", systemImage: "checkmark.circle",
                                           description: Text("Add homework with +. Tick it off here or on your watch."))
                }
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.items) { assignment in
                            AssignmentRow(assignment: assignment)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = assignment }
                        }
                        .onDelete { offsets in offsets.map { group.items[$0] }.forEach(store.delete) }
                    }
                }
                if !done.isEmpty {
                    Section {
                        ForEach(done) { AssignmentRow(assignment: $0) }
                            .onDelete { offsets in offsets.map { done[$0] }.forEach(store.delete) }
                    } header: {
                        HStack {
                            Text("Done")
                            Spacer()
                            Button("Clear") { store.clearDone() }.font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Homework")
            .toolbar {
                Button { editing = newAssignment() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add homework")
            }
            .sheet(item: $editing) { assignment in
                AssignmentEditor(assignment: assignment,
                                 isNew: !store.timetable.assignments.contains { $0.id == assignment.id })
            }
        }
    }

    private func newAssignment() -> Assignment {
        let cal = Calendar.current
        // Guess the subject: the lesson on now, or the one that just finished.
        let now = Date.now
        let slots = store.timetable.slots(on: now)
        let guess = (slots.first { $0.isNow(now) } ?? slots.last { $0.end <= now })?.lesson.subjectID
        let due = guess.flatMap { store.timetable.nextLesson(of: $0, after: now) }
            ?? cal.date(byAdding: .day, value: 1, to: now) ?? now
        return Assignment(title: "", subjectID: guess, due: cal.startOfDay(for: due))
    }
}

/// Homework due around the same time.
struct DueGroup: Identifiable {
    let title: String
    let items: [Assignment]
    var id: String { title }
}

/// A piece of homework with a tick box.
struct AssignmentRow: View {
    @EnvironmentObject private var store: Store
    let assignment: Assignment

    var body: some View {
        let subject = store.timetable.subject(assignment.subjectID)
        HStack(spacing: 12) {
            Button {
                store.setDone(assignment.id, !assignment.done)
            } label: {
                Image(systemName: assignment.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(assignment.done ? .green : (subject?.colour.color ?? .secondary))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.title.isEmpty ? "Homework" : assignment.title)
                    .strikethrough(assignment.done)
                    .foregroundStyle(assignment.done ? .secondary : .primary)
                Text([subject?.name, "Due \(Clock.relativeDay(assignment.due).lowercasedIfRelative)"]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(!assignment.done && Clock.isOverdue(assignment.due) ? .red : .secondary)
            }
        }
    }
}

/// Adds or changes a piece of homework.
struct AssignmentEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var assignment: Assignment
    let isNew: Bool

    init(assignment: Assignment, isNew: Bool) {
        _assignment = State(initialValue: assignment)
        self.isNew = isNew
    }

    private var nextLesson: Date? {
        assignment.subjectID.flatMap { store.timetable.nextLesson(of: $0, after: .now) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's the homework?", text: $assignment.title, axis: .vertical)
                    Picker("Subject", selection: $assignment.subjectID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.timetable.subjects) { subject in
                            Text(subject.name).tag(Optional(subject.id))
                        }
                    }
                }
                Section("Due") {
                    DatePicker("Due", selection: $assignment.due, displayedComponents: .date)
                    HStack {
                        if let nextLesson {
                            Button("Next lesson") { assignment.due = Calendar.current.startOfDay(for: nextLesson) }
                        }
                        Button("Tomorrow") { assignment.due = day(1) }
                        Button("In a week") { assignment.due = day(7) }
                    }
                    .buttonStyle(.bordered)
                }
                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) {
                            store.delete(assignment)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New homework" : "Homework")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: assignment.subjectID) { _, _ in
                if isNew, let nextLesson { assignment.due = Calendar.current.startOfDay(for: nextLesson) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        assignment.title = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.save(assignment)
                        dismiss()
                    }
                    .disabled(assignment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func day(_ offset: Int) -> Date {
        let cal = Calendar.current
        return cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: .now) ?? .now)
    }
}
