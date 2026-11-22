import SwiftUI

/// Your subjects, with their rooms, teachers, colours and what to bring.
struct SubjectsView: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Subject?

    var body: some View {
        NavigationStack {
            List {
                if store.timetable.subjects.isEmpty {
                    ContentUnavailableView("No subjects yet", systemImage: "books.vertical",
                                           description: Text("Add each subject once, then place it in your week."))
                }
                Section {
                    ForEach(store.timetable.subjects) { subject in
                        Button { editing = subject } label: { SubjectRow(subject: subject) }
                            .tint(.primary)
                    }
                    .onDelete { offsets in
                        offsets.map { store.timetable.subjects[$0] }.forEach(store.delete)
                    }
                    .onMove { store.timetable.subjects.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    if !store.timetable.subjects.isEmpty {
                        Text("Deleting a subject also removes its lessons.")
                    }
                }
            }
            .navigationTitle("Subjects")
            .toolbar {
                if !store.timetable.subjects.isEmpty { EditButton() }
                Button {
                    let colours = SubjectColour.allCases
                    editing = Subject(name: "", colour: colours[store.timetable.subjects.count % colours.count])
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add subject")
            }
            .sheet(item: $editing) { subject in
                SubjectEditor(subject: subject, isNew: !store.timetable.subjects.contains { $0.id == subject.id })
            }
        }
    }
}

struct SubjectRow: View {
    let subject: Subject

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(subject.colour.color).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name).font(.headline)
                let detail = [subject.room, subject.teacher].filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                if !subject.bring.isEmpty {
                    Label(subject.bring.joined(separator: ", "), systemImage: "backpack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Adds or changes a subject.
struct SubjectEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var subject: Subject
    @State private var newItem = ""
    @State private var confirmDelete = false
    let isNew: Bool

    init(subject: Subject, isNew: Bool) {
        _subject = State(initialValue: subject)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Subject", text: $subject.name)
                    TextField("Usual room", text: $subject.room)
                    TextField("Teacher", text: $subject.teacher)
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(SubjectColour.allCases) { colour in
                            Circle()
                                .fill(colour.color)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if colour == subject.colour {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { subject.colour = colour }
                                .accessibilityLabel(colour.rawValue)
                                .accessibilityAddTraits(colour == subject.colour ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(Array(subject.bring.enumerated()), id: \.offset) { _, item in
                        Text(item)
                    }
                    .onDelete { subject.bring.remove(atOffsets: $0) }
                    HStack {
                        TextField("Add something to bring", text: $newItem)
                            .onSubmit(addItem)
                        Button(action: addItem) { Image(systemName: "plus.circle.fill") }
                            .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Bring to every lesson")
                } footer: {
                    Text("Books, kit and anything else. Your watch lists them the night before.")
                }

                if !isNew {
                    Section {
                        Button("Delete subject", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New subject" : subject.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        addItem()
                        subject.name = subject.name.trimmingCharacters(in: .whitespaces)
                        subject.bring = subject.bring.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        store.save(subject)
                        dismiss()
                    }
                    .disabled(subject.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(subject.name) and all its lessons?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.delete(subject)
                    dismiss()
                }
            }
        }
    }

    private func addItem() {
        let item = newItem.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return }
        subject.bring.append(item)
        newItem = ""
    }
}
