import SwiftUI
import SwiftData
import QuickLook
import PhotosUI

/// Every field of an assignment or exam.
struct AssignmentEditor: View {
    var assignment: Assignment?
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @Query(filter: #Predicate<Chapter> { !$0.trashed }, sort: \Chapter.sort) private var chapters: [Chapter]

    @State private var title = ""
    @State private var kind: AssignmentKind = .homework
    @State private var subjectID: UUID?
    @State private var chapterIDs: Set<String> = []
    @State private var hasDue = true
    @State private var due = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date().addingTimeInterval(2 * 86400)) ?? Date()
    @State private var hours = 1.0
    @State private var priority: Priority = .medium
    @State private var status: TaskStatus = .todo
    @State private var notes = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                Picker("Type", selection: $kind) {
                    ForEach(AssignmentKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Picker("Subject", selection: $subjectID) {
                    Text("None").tag(UUID?.none)
                    ForEach(subjects) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
            let subjectChapters = chapters.filter { $0.subjectID == subjectID && subjectID != nil }
            if !subjectChapters.isEmpty {
                Section("Chapters") {
                    ForEach(subjectChapters) { c in
                        let key = c.id.lower
                        Button {
                            if chapterIDs.contains(key) { chapterIDs.remove(key) } else { chapterIDs.insert(key) }
                        } label: {
                            HStack {
                                Text(c.displayTitle).foregroundStyle(.primary)
                                Spacer()
                                if chapterIDs.contains(key) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
            Section {
                Toggle("Due date", isOn: $hasDue)
                if hasDue { DatePicker("Due", selection: $due) }
                Stepper("Estimate: \(Fmt.hours(hours))", value: $hours, in: 0.25...100, step: hours < 2 ? 0.25 : 0.5)
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }
                Picker("Status", selection: $status) {
                    ForEach(TaskStatus.allCases) { Text($0.label).tag($0) }
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
            Section("Notes") {
                TextField("Anything Instinct should know", text: $notes, axis: .vertical).lineLimit(3...10)
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .backdrop([Color(hex: subjects.first { $0.id == subjectID }?.color ?? "#8FA8FF")])
        .navigationTitle(assignment == nil ? "New assignment" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: load)
        .onChange(of: kind) { old, new in
            if assignment == nil && hours == store.defaultHours(for: old) { hours = store.defaultHours(for: new) }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let a = assignment else { return }
        title = a.title; kind = a.kind; subjectID = a.subjectID; chapterIDs = Set(a.chapterIDs)
        hasDue = a.dueAt != nil; due = a.dueAt ?? due; hours = a.estimatedHours; priority = a.priority
        status = a.status; notes = a.notes
    }

    private func save() {
        let a = assignment ?? Assignment(id: UUID())
        a.title = title.trimmingCharacters(in: .whitespaces)
        a.kind = kind
        a.subjectID = subjectID
        a.chapterIDs = Array(chapterIDs).sorted()
        a.dueAt = hasDue ? due : nil
        a.estimatedHours = hours
        a.priority = priority
        a.status = status
        a.notes = notes
        if assignment == nil { store.insert(a) } else { a.touch() }
        store.save()
        Haptics.success()
        dismiss()
    }
}

/// An assignment at a glance: progress, linked blocks and focus time, files, and the actions on it.
struct AssignmentDetail: View {
    @Bindable var assignment: Assignment
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StudyBlock> { !$0.trashed }, sort: \StudyBlock.startAt) private var blocks: [StudyBlock]
    @Query(filter: #Predicate<FocusSession> { !$0.trashed }, sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query(filter: #Predicate<FileAttachment> { !$0.trashed }) private var files: [FileAttachment]
    @State private var editing = false
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var preview: URL?

    var body: some View {
        let subject = store.subject(assignment.subjectID)
        let color = Color(hex: subject?.color ?? "#8FA8FF")
        let logged = sessions.filter { $0.assignmentID == assignment.id }
        let minutes = logged.reduce(0) { $0 + $1.minutes }
        let progress = store.progress(assignment)
        let mine = blocks.filter { $0.assignmentID == assignment.id }
        let upcoming = mine.filter { $0.status == .planned && $0.endAt > Date() }
        let attachments = files.filter { $0.assignmentID == assignment.id }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SubjectChip(subject: subject)
                        Label(assignment.kind.label, systemImage: assignment.kind.symbol).font(.caption.weight(.semibold))
                        Spacer()
                        if assignment.byInstinct { InstinctBadge() }
                    }
                    Text(assignment.title).font(.title2.weight(.bold))
                    HStack(spacing: 18) {
                        ZStack {
                            ProgressRing(progress: progress, color: color, line: 9)
                            Text("\(Int(progress * 100))%").font(.headline.monospacedDigit())
                        }
                        .frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("\(Fmt.minutes(minutes)) of \(Fmt.hours(assignment.estimatedHours))", systemImage: "timer")
                            Label(Fmt.due(assignment.dueAt), systemImage: "calendar")
                                .foregroundStyle((assignment.dueAt ?? .distantFuture) < Date() && assignment.isOpen ? Theme.bad : .primary)
                            Label("\(assignment.priority.label) priority", systemImage: assignment.priority.symbol)
                            Label(assignment.status.label, systemImage: assignment.status.symbol)
                        }
                        .font(.subheadline)
                    }
                    let chapterNames = assignment.chapterUUIDs.compactMap { store.find(Chapter.self, $0)?.shortTitle }
                    if !chapterNames.isEmpty {
                        Label(chapterNames.joined(separator: ", "), systemImage: "bookmark").font(.caption).foregroundStyle(.secondary)
                    }
                    if let r = assignment.reason, !r.isEmpty, assignment.byInstinct {
                        Label(r, systemImage: "sparkle").font(.caption).foregroundStyle(Theme.instinct)
                    }
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                FocusTimer.shared.prepare(assignment: assignment)
                                dismiss()
                                router.tab = .focus
                            } label: { Label("Focus", systemImage: "play.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(.glassProminent).tint(color)
                            Button {
                                store.setStatus(assignment, assignment.status == .done ? .todo : .done)
                            } label: { Label(assignment.status == .done ? "Reopen" : "Done", systemImage: "checkmark").frame(maxWidth: .infinity) }
                                .buttonStyle(.glass)
                        }
                        .controlSize(.large)
                    }
                }
                .glassCard(tint: color, radius: 28, padding: 18)

                if !assignment.notes.isEmpty {
                    Text(assignment.notes).font(.subheadline).glassCard(radius: 20, padding: 14)
                }

                SectionTitle("Planned", symbol: "calendar")
                if upcoming.isEmpty {
                    Text("No blocks planned yet.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                } else {
                    VStack(spacing: 8) { ForEach(upcoming) { BlockRow(block: $0) } }
                }

                SectionTitle("Files", symbol: "paperclip")
                VStack(spacing: 8) {
                    ForEach(attachments) { f in
                        HStack {
                            Image(systemName: (f.mime ?? "").hasPrefix("image") ? "photo" : (f.mime ?? "").contains("pdf") ? "doc.richtext" : "doc")
                            Text(f.name).lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(12)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                        .onTapGesture { open(f) }
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) { Files.remove(f.path); store.remove(f) }
                        }
                    }
                    HStack {
                        Button { importing = true } label: { Label("Add file", systemImage: "doc.badge.plus") }.buttonStyle(.glass)
                        PhotosPicker(selection: $photo, matching: .images) { Label("Add photo", systemImage: "photo.badge.plus") }.buttonStyle(.glass)
                    }
                }

                if !logged.isEmpty {
                    SectionTitle("Focus sessions", symbol: "timer")
                    VStack(spacing: 6) {
                        ForEach(logged.prefix(10)) { s in
                            HStack {
                                Text(Fmt.dayTime(s.startedAt)).font(.caption)
                                Spacer()
                                if let o = s.outcome { Image(systemName: o.symbol).font(.caption) }
                                Text(Fmt.minutes(s.minutes)).font(.caption.monospacedDigit())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .rect(cornerRadius: 14))
                        }
                    }
                }
                Spacer(minLength: 40)
            }
            .padding()
        }
        .backdrop([color])
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { store.remove(assignment); dismiss() }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { AssignmentEditor(assignment: assignment) }.preferredColorScheme(.dark) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result, let f = Files.importFile(url, folder: "attachments/\(assignment.id.lower)") else { return }
            attach(path: f.path, name: f.name, size: f.size, mime: f.mime)
        }
        .onChange(of: photo) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                      let path = Files.save(image: img, folder: "attachments/\(assignment.id.lower)") else { return }
                attach(path: path, name: "Photo \(Date().formatted(date: .abbreviated, time: .shortened)).jpg", size: data.count, mime: "image/jpeg")
                photo = nil
            }
        }
        .quickLookPreview($preview)
    }

    private func attach(path: String, name: String, size: Int, mime: String) {
        let f = FileAttachment(id: UUID())
        f.assignmentID = assignment.id
        f.path = path
        f.name = name
        f.size = size
        f.mime = mime
        store.insert(f)
        store.save()
    }

    private func open(_ f: FileAttachment) {
        Task {
            guard await Files.data(f.path) != nil else { store.show("Couldn't download that file", symbol: "exclamationmark.triangle"); return }
            // QuickLook wants the real file name for the right preview.
            let tmp = FileManager.default.temporaryDirectory.appending(path: f.name)
            try? FileManager.default.removeItem(at: tmp)
            try? FileManager.default.copyItem(at: Files.localURL(f.path), to: tmp)
            preview = tmp
        }
    }
}

/// A study block: when, what for, and how it went.
struct BlockEditor: View {
    var block: StudyBlock?
    var start: Date
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @Query(filter: #Predicate<Assignment> { !$0.trashed }, sort: \Assignment.dueAt) private var assignments: [Assignment]
    @Query(filter: #Predicate<Deck> { !$0.trashed }, sort: \Deck.name) private var decks: [Deck]

    @State private var startAt = Date()
    @State private var minutes = 50
    @State private var kind: BlockKind = .study
    @State private var subjectID: UUID?
    @State private var assignmentID: UUID?
    @State private var deckID: UUID?
    @State private var goal = ""
    @State private var status: BlockStatus = .planned
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        let busyClash = store.live(BusySlot.self).first { $0.startAt < startAt.addingTimeInterval(TimeInterval(minutes * 60)) && $0.endAt > startAt }
        Form {
            if let block, block.byInstinct {
                Section {
                    Label(block.reason?.isEmpty == false ? block.reason! : "Planned by Instinct", systemImage: "sparkle")
                        .foregroundStyle(Theme.instinct).font(.subheadline)
                }
                .listRowBackground(Theme.instinct.opacity(0.12))
            }
            Section {
                DatePicker("Starts", selection: $startAt)
                Stepper("Length: \(Fmt.minutes(minutes))", value: $minutes, in: 10...300, step: 5)
                if let busyClash {
                    Label("Overlaps \(busyClash.title ?? "a busy time") (\(Fmt.span(busyClash.startAt, busyClash.endAt)))", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.warn)
                }
                Picker("Kind", selection: $kind) { ForEach(BlockKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
            }
            .listRowBackground(Color.white.opacity(0.06))
            Section {
                Picker("Subject", selection: $subjectID) {
                    Text("None").tag(UUID?.none)
                    ForEach(subjects) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Assignment", selection: $assignmentID) {
                    Text("None").tag(UUID?.none)
                    ForEach(assignments.filter { $0.isOpen && (subjectID == nil || $0.subjectID == subjectID) }) { Text($0.title).tag(Optional($0.id)) }
                }
                if kind == .review {
                    Picker("Deck", selection: $deckID) {
                        Text("All due cards").tag(UUID?.none)
                        ForEach(decks) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                TextField("Goal for this block", text: $goal, axis: .vertical)
            }
            .listRowBackground(Color.white.opacity(0.06))
            if block != nil {
                Section("How it went") {
                    Picker("Status", selection: $status) { ForEach(BlockStatus.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                    TextField("Note (Instinct reads this)", text: $note, axis: .vertical)
                }
                .listRowBackground(Color.white.opacity(0.06))
                Section {
                    Button {
                        save(close: false)
                        if kind == .review { router.openReview(deck: deckID) } else if let id = block?.id { router.openFocus(block: id) }
                    } label: { Label(kind == .review ? "Start review" : "Start focus", systemImage: "play.fill") }
                    Button("Delete block", role: .destructive) {
                        if let block { store.remove(block) }
                        dismiss()
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .backdrop([Color(hex: subjects.first { $0.id == subjectID }?.color ?? "#8FA8FF")])
        .navigationTitle(block == nil ? "New block" : "Study block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save(close: true) } }
        }
        .onAppear(perform: load)
        .onChange(of: assignmentID) { _, id in
            if let a = store.find(Assignment.self, id) {
                if subjectID == nil { subjectID = a.subjectID }
                if a.kind == .test || a.kind == .exam { kind = .revision }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        startAt = start
        minutes = store.prefs.blockMinutes
        guard let b = block else { return }
        startAt = b.startAt; minutes = max(5, b.minutes); kind = b.kind; subjectID = b.subjectID; assignmentID = b.assignmentID
        deckID = b.deckID; goal = b.goal; status = b.status; note = b.outcomeNote ?? ""
    }

    private func save(close: Bool) {
        let b = block ?? StudyBlock(id: UUID())
        b.startAt = startAt
        b.endAt = startAt.addingTimeInterval(TimeInterval(minutes * 60))
        b.kind = kind
        b.subjectID = subjectID
        b.assignmentID = assignmentID
        b.deckID = kind == .review ? deckID : nil
        if let a = store.find(Assignment.self, assignmentID), b.chapterIDs.isEmpty { b.chapterIDs = a.chapterIDs }
        b.goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        b.status = status
        b.outcomeNote = note.isEmpty ? nil : note
        if block == nil { store.insert(b) } else { b.touch() }
        store.save()
        if close { dismiss() }
    }
}
