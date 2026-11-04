import SwiftUI
import SwiftData

/// Subjects → chapters → topics, each with a status, rolled up into rings.
struct SyllabusView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @Query(filter: #Predicate<Topic> { !$0.trashed }) private var topics: [Topic]
    @Query(filter: #Predicate<FocusSession> { !$0.trashed }) private var sessions: [FocusSession]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if subjects.isEmpty {
                    EmptyCard(symbol: "books.vertical", title: "Add your subjects",
                              text: "Each subject gets a colour, its chapters and topics. Instinct can fill these in too.")
                    Button { router.sheet = .subject(nil) } label: { Label("Add a subject", systemImage: "plus") }
                        .buttonStyle(.glassProminent).controlSize(.large)
                }
                ForEach(subjects) { s in
                    NavigationLink(value: s.id) {
                        SubjectCard(subject: s, topics: topics.filter { $0.subjectID == s.id },
                                    minutes: sessions.filter { $0.subjectID == s.id }.reduce(0) { $0 + $1.minutes })
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 100)
            }
            .padding(.horizontal)
        }
        .backdrop(subjects.map { Color(hex: $0.color) })
        .navigationTitle("Syllabus")
        .navigationDestination(for: UUID.self) { id in
            if let s = store.find(StudySubject.self, id) { SubjectDetail(subject: s) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { router.sheet = .settings } label: { Image(systemName: "gearshape") } }
            ToolbarItem(placement: .topBarTrailing) { Button { router.sheet = .subject(nil) } label: { Image(systemName: "plus") } }
        }
    }
}

enum Syllabus {
    static func progress(_ topics: [Topic]) -> Double {
        guard !topics.isEmpty else { return 0 }
        return topics.reduce(0) { $0 + $1.status.progress } / Double(topics.count)
    }
}

struct SubjectCard: View {
    var subject: StudySubject
    var topics: [Topic]
    var minutes: Int

    var body: some View {
        let color = Color(hex: subject.color)
        let p = Syllabus.progress(topics)
        let mastered = topics.filter { $0.status == .mastered }.count
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(progress: p, color: color, line: 7)
                Image(systemName: subject.icon).foregroundStyle(color)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(subject.name).font(.headline)
                    if subject.byInstinct { InstinctBadge(compact: true) }
                }
                Text("\(Int(p * 100))% · \(mastered)/\(topics.count) topics mastered").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(Fmt.minutes(minutes), systemImage: "timer")
                    if let exam = subject.examAt, exam > Date() {
                        Label("Exam \(Fmt.day(exam))", systemImage: "graduationcap")
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .glassCard(tint: color, radius: 22, padding: 14, interactive: true)
    }
}

struct SubjectDetail: View {
    @Bindable var subject: StudySubject
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Chapter> { !$0.trashed }, sort: \Chapter.sort) private var allChapters: [Chapter]
    @Query(filter: #Predicate<Topic> { !$0.trashed }, sort: \Topic.sort) private var allTopics: [Topic]
    @Query(filter: #Predicate<Assignment> { !$0.trashed }) private var assignments: [Assignment]
    @Query(filter: #Predicate<Deck> { !$0.trashed }) private var decks: [Deck]
    @Query(filter: #Predicate<FocusSession> { !$0.trashed }) private var sessions: [FocusSession]
    @Query(filter: #Predicate<StudyBlock> { !$0.trashed }) private var blocks: [StudyBlock]
    @State private var expanded: Set<UUID> = []
    @State private var addingChapter = false
    @State private var chapterTitle = ""
    @State private var chapterNumber = ""
    @State private var topicDraft: [UUID: String] = [:]

    var body: some View {
        let color = Color(hex: subject.color)
        let chapters = allChapters.filter { $0.subjectID == subject.id }.sorted { ($0.number ?? 999, $0.sort) < ($1.number ?? 999, $1.sort) }
        let topics = allTopics.filter { $0.subjectID == subject.id }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ZStack {
                        ProgressRing(progress: Syllabus.progress(topics), color: color, line: 10)
                        Text("\(Int(Syllabus.progress(topics) * 100))%").font(.title3.weight(.bold).monospacedDigit())
                    }
                    .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(TopicStatus.allCases) { st in
                            let n = topics.filter { $0.status == st }.count
                            Label("\(n) \(st.label.lowercased())", systemImage: st.symbol).font(.caption)
                                .foregroundStyle(st == .mastered ? Theme.good : .secondary)
                        }
                    }
                }
                .glassCard(tint: color, radius: 26, padding: 16)

                ForEach(chapters) { ch in chapterCard(ch, topics: topics.filter { $0.chapterID == ch.id }, color: color) }

                if addingChapter {
                    HStack {
                        TextField("No.", text: $chapterNumber).keyboardType(.numberPad).frame(width: 44)
                        TextField("Chapter title", text: $chapterTitle).submitLabel(.done).onSubmit(addChapter)
                        Button("Add", action: addChapter).buttonStyle(.glassProminent)
                    }
                    .glassCard(radius: 18, padding: 12)
                } else {
                    Button { withAnimation(.snappy) { addingChapter = true; chapterNumber = "\((chapters.compactMap(\.number).max() ?? 0) + 1)" } } label: {
                        Label("Add chapter", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                }
                Spacer(minLength: 100)
            }
            .padding(.horizontal)
        }
        .backdrop([color])
        .navigationTitle(subject.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .subject(subject.id) } label: { Image(systemName: "pencil") }
            }
        }
    }

    private func chapterCard(_ ch: Chapter, topics: [Topic], color: Color) -> some View {
        let open = expanded.contains(ch.id)
        let chapterKey = ch.id.lower
        let linked = assignments.filter { $0.chapterIDs.contains(chapterKey) }
        let linkedDecks = decks.filter { $0.chapterID == ch.id }
        let linkedIDs = Set(linked.map(\.id))
        let blockIDs = Set(blocks.filter { $0.chapterIDs.contains(chapterKey) }.map(\.id))
        let minutes = sessions.filter { ($0.assignmentID.map(linkedIDs.contains) ?? false) || ($0.blockID.map(blockIDs.contains) ?? false) }
            .reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { if open { expanded.remove(ch.id) } else { expanded.insert(ch.id) } }
            } label: {
                HStack(spacing: 12) {
                    ProgressRing(progress: Syllabus.progress(topics), color: color, line: 4).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ch.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                            if ch.byInstinct { InstinctBadge(compact: true) }
                        }
                        Text("\(topics.count) topics · \(linked.count) assignments · \(linkedDecks.count) decks · \(Fmt.minutes(minutes))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if open {
                ForEach(topics) { t in TopicRow(topic: t) }
                HStack {
                    TextField("Add topics (one per line or comma-separated)", text: Binding(get: { topicDraft[ch.id] ?? "" }, set: { topicDraft[ch.id] = $0 }), axis: .vertical)
                        .font(.subheadline)
                    Button { addTopics(to: ch) } label: { Image(systemName: "plus.circle.fill") }
                        .disabled((topicDraft[ch.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                if !linked.isEmpty || !linkedDecks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(linked) { a in
                            Button { router.sheet = .assignment(a.id) } label: { Label(a.title, systemImage: a.kind.symbol).font(.caption) }.buttonStyle(.plain)
                        }
                        ForEach(linkedDecks) { d in
                            Button { router.openReview(deck: d.id) } label: { Label(d.name, systemImage: "rectangle.stack").font(.caption) }.buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Delete chapter", role: .destructive) {
                        for t in topics { t.trashed = true; t.touch() }
                        store.remove(ch)
                    }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.bad)
                }
            }
        }
        .glassCard(radius: 20, padding: 14)
    }

    private func addChapter() {
        let title = chapterTitle.trimmingCharacters(in: .whitespaces)
        let number = Int(chapterNumber)
        guard !title.isEmpty || number != nil else { return }
        let c = Chapter(id: UUID())
        c.subjectID = subject.id
        c.number = number
        c.title = title
        c.sort = number ?? 999
        store.insert(c)
        store.save()
        chapterTitle = ""
        withAnimation(.snappy) { addingChapter = false; expanded.insert(c.id) }
    }

    private func addTopics(to ch: Chapter) {
        let raw = topicDraft[ch.id] ?? ""
        let names = raw.components(separatedBy: CharacterSet(charactersIn: "\n,;")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let existing = allTopics.filter { $0.chapterID == ch.id }.count
        for (i, n) in names.enumerated() {
            let t = Topic(id: UUID())
            t.subjectID = subject.id
            t.chapterID = ch.id
            t.title = n
            t.sort = existing + i
            store.insert(t)
        }
        store.save()
        topicDraft[ch.id] = ""
        Haptics.success()
    }
}

struct TopicRow: View {
    @Bindable var topic: Topic
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { topic.status = topic.status.next; topic.touch(); store.save() }
                Haptics.select()
            } label: {
                Image(systemName: topic.status.symbol).font(.title3).foregroundStyle(color).contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Status: \(topic.status.label). Tap to change.")
            Text(topic.title).font(.subheadline)
            if topic.byInstinct { InstinctBadge(compact: true) }
            Spacer()
            Menu {
                ForEach(TopicStatus.allCases) { s in
                    Button(s.label, systemImage: s.symbol) { topic.status = s; topic.touch(); store.save() }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { store.remove(topic) }
            } label: {
                Text(topic.status.label).font(.caption2.weight(.semibold)).foregroundStyle(color)
            }
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch topic.status {
        case .notStarted: return .secondary
        case .learning: return Theme.warn
        case .revised: return Theme.accent
        case .mastered: return Theme.good
        }
    }
}

struct SubjectEditor: View {
    var subject: StudySubject?
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = Theme.subjectPalette[0]
    @State private var icon = "book.closed"
    @State private var hasExam = false
    @State private var exam = Date().addingTimeInterval(30 * 86400)
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Subject name", text: $name)
                Toggle("Exam date", isOn: $hasExam)
                if hasExam { DatePicker("Exam", selection: $exam) }
            }
            .listRowBackground(Color.white.opacity(0.06))
            Section("Colour") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(Theme.subjectPalette, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                            .overlay { if hex == color { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.black) } }
                            .onTapGesture { color = hex; Haptics.select() }
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.white.opacity(0.06))
            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(Theme.subjectIcons, id: \.self) { s in
                        Image(systemName: s).font(.title3).frame(width: 36, height: 36)
                            .foregroundStyle(s == icon ? Color(hex: color) : .secondary)
                            .glassEffect(s == icon ? .regular.tint(Color(hex: color).opacity(0.4)) : .regular, in: .circle)
                            .onTapGesture { icon = s; Haptics.select() }
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.white.opacity(0.06))
            if let subject {
                Section {
                    Button("Delete subject", role: .destructive) {
                        store.remove(subject)
                        dismiss()
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .backdrop([Color(hex: color)])
        .navigationTitle(subject == nil ? "New subject" : "Edit subject")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let s = subject ?? StudySubject(id: UUID())
                    s.name = name.trimmingCharacters(in: .whitespaces)
                    s.color = color
                    s.icon = icon
                    s.examAt = hasExam ? exam : nil
                    if subject == nil { s.sort = store.subjects.count; store.insert(s) } else { s.touch() }
                    store.save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let s = subject {
                name = s.name; color = s.color; icon = s.icon
                if let e = s.examAt { hasExam = true; exam = e }
            } else {
                color = Theme.subjectPalette[store.subjects.count % Theme.subjectPalette.count]
            }
        }
    }
}
