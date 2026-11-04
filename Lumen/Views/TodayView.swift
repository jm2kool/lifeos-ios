import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(SyncEngine.self) private var sync
    @Query(filter: #Predicate<StudyBlock> { !$0.trashed }, sort: \StudyBlock.startAt) private var blocks: [StudyBlock]
    @Query(filter: #Predicate<Assignment> { !$0.trashed }, sort: \Assignment.dueAt) private var assignments: [Assignment]
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @Query(filter: #Predicate<Proposal> { !$0.trashed }) private var proposals: [Proposal]
    @Query(filter: #Predicate<FocusSession> { !$0.trashed }) private var sessions: [FocusSession]

    var body: some View {
        let now = Date()
        let cal = store.calendar
        let startOfDay = cal.startOfDay(for: now)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
        let today = blocks.filter { $0.startAt < endOfDay && $0.endAt > startOfDay }
        let next = blocks.first { $0.status == .planned && $0.endAt > now }
        let needOutcome = blocks.filter { $0.needsOutcome && $0.endAt > startOfDay.addingTimeInterval(-86400) }
        let proposal = proposals.filter(\.isPending).max { $0.createdAt < $1.createdAt }
        let dueSoon = assignments.filter { $0.isOpen && ($0.dueAt ?? .distantFuture) < now.addingTimeInterval(8 * 86400) }
        let minutesToday = sessions.filter { $0.startedAt >= startOfDay }.reduce(0) { $0 + $1.minutes }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(now: now)
                if let proposal { ProposalCard(proposal: proposal) }
                if !needOutcome.isEmpty { OutcomePrompt(blocks: needOutcome) }
                if let next { NextBlockCard(block: next) } else { noBlockCard }
                statsRow(minutes: minutesToday)
                SectionTitle("Today's plan", symbol: "calendar.day.timeline.left")
                if today.isEmpty {
                    EmptyCard(symbol: "calendar.badge.plus", title: "Nothing planned today",
                              text: "Instinct plans around your schedule. You can also auto-plan from the Planner tab.")
                } else {
                    VStack(spacing: 8) { ForEach(today) { BlockRow(block: $0) } }
                }
                SectionTitle("Due soon", symbol: "flag")
                if dueSoon.isEmpty {
                    EmptyCard(symbol: "checkmark.seal", title: "All clear", text: "Nothing due in the next week. Add work with the bar below.")
                } else {
                    VStack(spacing: 8) { ForEach(dueSoon) { AssignmentRow(assignment: $0) } }
                }
                ReviewTile()
                Spacer(minLength: 90)
            }
            .padding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
        .backdrop(subjects.map { Color(hex: $0.color) })
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .settings } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { Task { await sync.sync() } } label: {
                    Image(systemName: sync.state == .syncing ? "arrow.triangle.2.circlepath" : syncSymbol)
                        .symbolEffect(.rotate, isActive: sync.state == .syncing)
                }
                .accessibilityLabel(sync.summary)
            }
        }
        .safeAreaInset(edge: .bottom) { QuickAddBar() }
        .refreshable { await sync.sync() }
    }

    private var syncSymbol: String {
        switch sync.state {
        case .offline: return "icloud.slash"
        case .needsSetup, .failed: return "exclamationmark.icloud"
        default: return Auth.shared.signedIn ? "checkmark.icloud" : "iphone"
        }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(greeting(now)).font(.title2.weight(.bold))
            if case .needsSetup(let msg) = sync.state {
                Label(msg, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warn).padding(.top, 4)
            }
        }
        .padding(.top, 4)
    }

    private func greeting(_ d: Date) -> String {
        let h = Calendar.current.component(.hour, from: d)
        let name = Auth.shared.session?.name?.split(separator: " ").first.map(String.init)
        let part = h < 5 ? "Late night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        return name.map { "\(part), \($0)" } ?? part
    }

    private var noBlockCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.instinct)
            VStack(alignment: .leading, spacing: 4) {
                Text("No blocks coming up").font(.headline)
                Text("Instinct will plan when there's work to do, or start a free focus session now.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .glassCard(tint: Theme.instinct)
        .onTapGesture { router.tab = .focus }
    }

    private func statsRow(minutes: Int) -> some View {
        let goal = max(1, store.prefs.dailyGoalMinutes)
        return HStack(spacing: 10) {
            HStack(spacing: 12) {
                ProgressRing(progress: Double(minutes) / Double(goal), color: Theme.accent, line: 6).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.minutes(minutes)).font(.headline.monospacedDigit())
                    Text("of \(Fmt.minutes(goal)) today").font(.caption).foregroundStyle(.secondary)
                }
            }
            .glassCard(radius: 20, padding: 12)
            HStack(spacing: 10) {
                Image(systemName: "flame.fill").font(.title2).foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.streak) day\(store.streak == 1 ? "" : "s")").font(.headline.monospacedDigit())
                    Text("streak").font(.caption).foregroundStyle(.secondary)
                }
            }
            .glassCard(radius: 20, padding: 12)
        }
    }
}

// MARK: - Next block

struct NextBlockCard: View {
    @Bindable var block: StudyBlock
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Namespace private var ns

    var body: some View {
        let subject = store.subject(block.subjectID)
        let color = Color(hex: subject?.color ?? "#8FA8FF")
        let assignment = store.find(Assignment.self, block.assignmentID)
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(block.isNow ? "NOW" : "UP NEXT").font(.caption.weight(.heavy)).foregroundStyle(color)
                    Spacer()
                    if block.byInstinct { InstinctBadge() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(assignment?.title ?? (block.goal.isEmpty ? block.kind.label : block.goal))
                        .font(.title3.weight(.bold)).lineLimit(2)
                    if !block.goal.isEmpty, assignment != nil {
                        Label(block.goal, systemImage: "target").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                HStack(spacing: 8) {
                    SubjectChip(subject: subject)
                    Label(Fmt.span(block.startAt, block.endAt), systemImage: block.kind.symbol)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(startsIn(ctx.date)).font(.caption.weight(.semibold)).foregroundStyle(color)
                }
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            Haptics.start()
                            if block.kind == .review { router.openReview(deck: block.deckID) } else { router.openFocus(block: block.id) }
                        } label: {
                            Label(block.kind == .review ? "Start review" : "Start focus", systemImage: block.kind == .review ? "play.rectangle.on.rectangle" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(color)
                        .glassEffectID("start", in: ns)
                        Menu {
                            Button("Done", systemImage: "checkmark") { store.setOutcome(block, .done) }
                            Button("Skip", systemImage: "forward.end") { store.setOutcome(block, .skipped) }
                            Button("Edit", systemImage: "pencil") { router.sheet = .block(block.id) }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("more", in: ns)
                    }
                    .controlSize(.large)
                }
            }
        }
        .glassCard(tint: color, radius: 28, padding: 18)
        .contentShape(Rectangle())
        .onTapGesture { router.sheet = .block(block.id) }
    }

    private func startsIn(_ now: Date) -> String {
        if block.isNow {
            let left = Int(block.endAt.timeIntervalSince(now) / 60)
            return "\(left) min left"
        }
        let m = Int(block.startAt.timeIntervalSince(now) / 60)
        if m < 60 { return "in \(max(1, m)) min" }
        if Calendar.current.isDateInToday(block.startAt) { return "in \(m / 60) h \(m % 60) min" }
        return Fmt.day(block.startAt)
    }
}

// MARK: - Rows

struct BlockRow: View {
    @Bindable var block: StudyBlock
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let subject = store.subject(block.subjectID)
        let color = Color(hex: subject?.color ?? "#8FA8FF")
        let title = store.find(Assignment.self, block.assignmentID)?.title ?? (block.goal.isEmpty ? block.kind.label : block.goal)
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.time(block.startAt)).font(.subheadline.weight(.semibold).monospacedDigit())
                Text(Fmt.time(block.endAt)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 58, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).shadow(color: color, radius: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if block.byInstinct { InstinctBadge(compact: true) }
                }
                Text([subject?.name, block.kind.label, block.assignmentID != nil && !block.goal.isEmpty ? block.goal : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: block.needsOutcome ? "questionmark.circle" : block.status.symbol)
                .foregroundStyle(statusColor)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .opacity(block.status == .skipped || block.status == .missed ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { router.sheet = .block(block.id) }
        .contextMenu {
            Button("Start focus", systemImage: "play.fill") { router.openFocus(block: block.id) }
            Button("Mark done", systemImage: "checkmark") { store.setOutcome(block, .done) }
            Button("Skip", systemImage: "forward.end") { store.setOutcome(block, .skipped) }
            Button("Delete", systemImage: "trash", role: .destructive) { store.remove(block) }
        }
    }

    private var statusColor: Color {
        switch block.status {
        case .done: return Theme.good
        case .partial: return Theme.warn
        case .missed: return Theme.bad
        default: return block.needsOutcome ? Theme.warn : .secondary
        }
    }
}

struct AssignmentRow: View {
    @Bindable var assignment: Assignment
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let subject = store.subject(assignment.subjectID)
        let color = Color(hex: subject?.color ?? "#8FA8FF")
        let progress = store.progress(assignment)
        HStack(spacing: 12) {
            Button {
                store.setStatus(assignment, assignment.status == .done ? .todo : .done)
            } label: {
                Image(systemName: assignment.status.symbol).font(.title3).foregroundStyle(assignment.status == .done ? Theme.good : color)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: assignment.status == .done)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: assignment.kind.symbol).font(.caption).foregroundStyle(color)
                    Text(assignment.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .strikethrough(assignment.status == .done)
                    if assignment.byInstinct { InstinctBadge(compact: true) }
                    if assignment.priority == .high || assignment.priority == .urgent {
                        Image(systemName: assignment.priority.symbol).font(.caption.weight(.bold)).foregroundStyle(Theme.warn)
                    }
                }
                HStack(spacing: 6) {
                    Text(Fmt.due(assignment.dueAt))
                        .foregroundStyle((assignment.dueAt ?? .distantFuture) < Date() && assignment.isOpen ? Theme.bad : .secondary)
                    Text("·").foregroundStyle(.secondary)
                    Text("\(Int(progress * 100))% of \(Fmt.hours(assignment.estimatedHours))").foregroundStyle(.secondary)
                }
                .font(.caption)
                ProgressBar(progress: progress, color: color)
            }
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture { router.sheet = .assignment(assignment.id) }
    }
}

/// Blocks whose time has passed without an outcome: one tap says how they went.
struct OutcomePrompt: View {
    var blocks: [StudyBlock]
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How did these go?", systemImage: "questionmark.bubble").font(.headline)
            ForEach(blocks.prefix(4)) { b in
                let title = store.find(Assignment.self, b.assignmentID)?.title ?? (b.goal.isEmpty ? b.kind.label : b.goal)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(title) · \(Fmt.span(b.startAt, b.endAt))").font(.subheadline).lineLimit(1)
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach([BlockStatus.done, .partial, .missed, .skipped]) { s in
                                Button(s.label) { withAnimation(.snappy) { store.setOutcome(b, s) }; Haptics.tap() }
                                    .buttonStyle(.glass).controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .glassCard(tint: Theme.warn)
    }
}

struct ReviewTile: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Card> { !$0.trashed }) private var cards: [Card]

    var body: some View {
        let due = cards.isEmpty ? 0 : store.dueCards().count
        if !cards.isEmpty {
            Button { router.openReview() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.on.rectangle.angled.fill").font(.title2).foregroundStyle(Theme.instinct)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(due == 0 ? "No cards due" : "\(due) cards due").font(.headline)
                        Text(due == 0 ? "Come back later — spacing is the point." : "A few minutes now saves hours later.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if due > 0 { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                }
                .glassCard(tint: Theme.instinct, interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(due == 0)
        }
    }
}

// MARK: - Quick add

/// "physics worksheet ch 3 due fri 2h" → an assignment, with what was understood shown as it's typed.
struct QuickAddBar: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @State private var text = ""
    @FocusState private var focused: Bool
    @Namespace private var ns

    var body: some View {
        let parsed = parse()
        VStack(spacing: 8) {
            if focused && !text.isEmpty, let p = parsed { chips(p).transition(.move(edge: .bottom).combined(with: .opacity)) }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                        TextField("physics worksheet ch 3 due fri 2h", text: $text)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(add)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("field", in: ns)
                    if focused && !text.isEmpty {
                        Button(action: add) { Image(systemName: "arrow.up").font(.headline).frame(width: 24, height: 24) }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.circle)
                            .glassEffectID("send", in: ns)
                    } else if !focused {
                        Button { router.sheet = .newAssignment } label: { Image(systemName: "square.and.pencil").frame(width: 24, height: 24) }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .glassEffectID("send", in: ns)
                            .accessibilityLabel("New assignment with all fields")
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.spring(duration: 0.35), value: focused)
        .animation(.spring(duration: 0.35), value: text.isEmpty)
        .onChange(of: router.focusQuickAdd) { _, go in if go { focused = true; router.focusQuickAdd = false } }
    }

    private func parse() -> QuickAddParser.Result? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return QuickAddParser(subjects: subjects.map { .init(id: $0.id, name: $0.name) }, calendar: store.calendar).parse(text)
    }

    private func chips(_ p: QuickAddParser.Result) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(p.title, "text.cursor")
                chip(p.kind.capitalized, AssignmentKind(rawValue: p.kind)?.symbol ?? "doc")
                if let s = p.subjectName { chip(s, "books.vertical", tint: subjects.first { $0.id == p.subjectID }.map { Color(hex: $0.color) }) }
                if !p.chapters.isEmpty { chip("Ch " + p.chapters.map(String.init).joined(separator: ", "), "bookmark") }
                if let d = p.due { chip(Fmt.dayTime(d), "calendar") }
                if let h = p.hours { chip(Fmt.hours(h), "hourglass") }
                if let pr = p.priority { chip(pr.capitalized, "exclamationmark") }
            }
            .padding(.horizontal, 4)
        }
    }

    private func chip(_ text: String, _ symbol: String, tint: Color? = nil) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(Theme.glass(tint: tint ?? Theme.accent), in: .capsule)
    }

    private func add() {
        guard let p = parse() else { return }
        let a = store.addAssignment(from: p)
        text = ""
        focused = false
        Haptics.success()
        store.show("Added \(a.title)", symbol: "plus.circle.fill")
    }
}
