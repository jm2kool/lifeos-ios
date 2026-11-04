import SwiftUI
import SwiftData

struct PlannerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case schedule = "Schedule", assignments = "Assignments", activity = "Activity"
        var id: String { rawValue }
    }

    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @State private var day = Calendar.current.startOfDay(for: Date())

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            Picker("View", selection: $router.plannerMode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            switch router.plannerMode {
            case .schedule: ScheduleView(day: $day)
            case .assignments: AssignmentsList()
            case .activity: ActivityFeed()
            }
        }
        .backdrop(subjects.map { Color(hex: $0.color) })
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.sheet = .settings } label: { Image(systemName: "gearshape") }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    let p = store.makeAutoPlan(days: 7)
                    Haptics.tap()
                    router.sheet = .proposal(p.id)
                } label: { Image(systemName: "wand.and.stars") }
                .accessibilityLabel("Auto-plan the week")
                Menu {
                    Button("Study block", systemImage: "calendar.badge.plus") { router.sheet = .newBlock(defaultStart()) }
                    Button("Assignment", systemImage: "doc.badge.plus") { router.sheet = .newAssignment }
                } label: { Image(systemName: "plus") }
            }
        }
    }

    private func defaultStart() -> Date {
        let cal = Calendar.current
        let base = cal.isDateInToday(day) ? Date() : Clock.date(store.prefs.earliestTime, on: day)
        return AutoPlanner.roundUp(base, minutes: 15, calendar: cal)
    }
}

// MARK: - Schedule

struct ScheduleView: View {
    @Binding var day: Date
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<StudyBlock> { !$0.trashed }, sort: \StudyBlock.startAt) private var blocks: [StudyBlock]
    @Query(filter: #Predicate<BusySlot> { !$0.trashed }) private var busy: [BusySlot]
    @Query(filter: #Predicate<AvailabilityWindow> { !$0.trashed }) private var windows: [AvailabilityWindow]
    private let hourHeight: CGFloat = 64

    var body: some View {
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: day)!
        let dayBlocks = blocks.filter { $0.startAt < dayEnd && $0.endAt > day }
        let dayBusy = busy.filter { $0.startAt < dayEnd && $0.endAt > day }
        let weekday = cal.component(.weekday, from: day) - 1
        let dayWindows = windows.filter { $0.weekday == weekday }
        let prefs = store.prefs
        let firstHour = max(0, min(Clock.minutes(prefs.earliestTime) / 60, dayBlocks.map { cal.component(.hour, from: max($0.startAt, day)) }.min() ?? 23) - 1)
        let lastHour = min(24, max(Clock.minutes(prefs.latestTime) / 60 + 1, (dayBlocks.map { cal.component(.hour, from: min($0.endAt, dayEnd.addingTimeInterval(-1))) }.max() ?? 0) + 2))
        let noStudy = prefs.noStudyDays.contains(weekday)

        VStack(spacing: 10) {
            WeekStrip(day: $day, blocks: blocks)
            if noStudy {
                Label("A no-study day — nothing gets planned here.", systemImage: "moon.zzz").font(.caption).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourGrid(first: firstHour, last: lastHour)
                        ForEach(dayWindows) { w in
                            let top = y(minutes: w.startMinutes, first: firstHour)
                            let h = y(minutes: w.endMinutes, first: firstHour) - top
                            RoundedRectangle(cornerRadius: 10)
                                .fill(w.isFree ? Theme.good.opacity(0.06) : Color.white.opacity(0.07))
                                .overlay(alignment: .topTrailing) {
                                    Text(w.label ?? (w.isFree ? "Free" : "Busy")).font(.caption2).foregroundStyle(.secondary).padding(6)
                                }
                                .frame(height: max(0, h))
                                .padding(.leading, 52)
                                .offset(y: top)
                        }
                        ForEach(dayBusy) { b in
                            let top = y(date: max(b.startAt, day), first: firstHour)
                            let h = y(date: min(b.endAt, dayEnd), first: firstHour) - top
                            BusyBand(title: b.title ?? (b.source == "calendar" ? "Busy (calendar)" : "Busy"))
                                .frame(height: max(14, h))
                                .padding(.leading, 52)
                                .offset(y: top)
                        }
                        ForEach(dayBlocks) { b in
                            let top = y(date: max(b.startAt, day), first: firstHour)
                            let h = y(date: min(b.endAt, dayEnd), first: firstHour) - top
                            TimelineBlock(block: b)
                                .frame(height: max(30, h - 2))
                                .padding(.leading, 60)
                                .padding(.trailing, 4)
                                .offset(y: top + 1)
                        }
                        if cal.isDateInToday(day) {
                            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                                NowLine().offset(y: y(date: ctx.date, first: firstHour) - 4)
                            }
                        }
                    }
                    .frame(height: CGFloat(lastHour - firstHour) * hourHeight + 20, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { p in
                        let minutes = Int(p.y / hourHeight * 60) + firstHour * 60
                        let rounded = (minutes / 15) * 15
                        router.sheet = .newBlock(day.addingTimeInterval(TimeInterval(rounded * 60)))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                    .id("grid")
                }
                .onAppear { proxy.scrollTo("grid", anchor: .top) }
            }
        }
    }

    private func y(minutes: Int, first: Int) -> CGFloat { CGFloat(minutes - first * 60) / 60 * hourHeight }
    private func y(date: Date, first: Int) -> CGFloat {
        let m = Calendar.current.dateComponents([.hour, .minute], from: day, to: date)
        return y(minutes: (m.hour ?? 0) * 60 + (m.minute ?? 0), first: first)
    }

    private func hourGrid(first: Int, last: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(first..<last, id: \.self) { h in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:00", h)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.top, 6)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }
}

struct WeekStrip: View {
    @Binding var day: Date
    var blocks: [StudyBlock]

    var body: some View {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        return HStack(spacing: 6) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left") }.buttonStyle(.glass).buttonBorderShape(.circle)
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { d in
                        let selected = cal.isDate(d, inSameDayAs: day)
                        let minutes = blocks.filter { cal.isDate($0.startAt, inSameDayAs: d) && $0.status != .skipped }.reduce(0) { $0 + $1.minutes }
                        Button {
                            withAnimation(.snappy) { day = d }
                            Haptics.select()
                        } label: {
                            VStack(spacing: 3) {
                                Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                                Text(d.formatted(.dateTime.day())).font(.subheadline.weight(selected ? .bold : .regular))
                                Capsule().fill(minutes > 0 ? Theme.accent : Color.clear).frame(width: min(22, CGFloat(minutes) / 10 + 4), height: 3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(Theme.accent.opacity(0.45)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 14))
                        .overlay {
                            if cal.isDateInToday(d) && !selected { RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.6), lineWidth: 1) }
                        }
                    }
                }
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right") }.buttonStyle(.glass).buttonBorderShape(.circle)
        }
        .padding(.horizontal)
    }

    private func shift(_ days: Int) {
        withAnimation(.snappy) { day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day }
    }
}

struct TimelineBlock: View {
    @Bindable var block: StudyBlock
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let s = store.subject(block.subjectID)
        let color = Color(hex: s?.color ?? "#8FA8FF")
        let title = store.find(Assignment.self, block.assignmentID)?.title ?? (block.goal.isEmpty ? block.kind.label : block.goal)
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: block.kind.symbol).font(.caption2)
                    Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if block.byInstinct { InstinctBadge(compact: true) }
                    if block.status != .planned { Image(systemName: block.status.symbol).font(.caption2) }
                }
                Text(Fmt.span(block.startAt, block.endAt) + (s.map { " · \($0.name)" } ?? "")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(color.opacity(block.status == .planned ? 0.35 : 0.15)).interactive(), in: .rect(cornerRadius: 12))
        .opacity(block.status == .skipped || block.status == .missed ? 0.5 : 1)
        .onTapGesture { router.sheet = .block(block.id) }
    }
}

struct BusyBand: View {
    var title: String
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .overlay(alignment: .topLeading) {
                Label(title, systemImage: "lock").font(.caption2).foregroundStyle(.secondary).padding(6).lineLimit(1)
            }
    }
}

struct NowLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.bad).frame(width: 8, height: 8).padding(.leading, 48)
            Rectangle().fill(Theme.bad).frame(height: 1.5)
        }
        .shadow(color: Theme.bad, radius: 3)
        .allowsHitTesting(false)
    }
}

// MARK: - Assignments

struct AssignmentsList: View {
    @Environment(Store.self) private var store
    @Query(filter: #Predicate<Assignment> { !$0.trashed }, sort: \Assignment.dueAt) private var assignments: [Assignment]
    @Query(filter: #Predicate<StudySubject> { !$0.trashed }, sort: \StudySubject.sort) private var subjects: [StudySubject]
    @State private var subjectFilter: UUID?
    @State private var showDone = false

    var body: some View {
        let now = Date()
        let weekEnd = now.addingTimeInterval(7 * 86400)
        let list = assignments.filter { subjectFilter == nil || $0.subjectID == subjectFilter }
        let open = list.filter { $0.status != .done }
        let groups: [Group] = [
            Group(title: "Overdue", items: open.filter { ($0.dueAt ?? .distantFuture) < now }),
            Group(title: "This week", items: open.filter { ($0.dueAt ?? .distantFuture) >= now && ($0.dueAt ?? .distantFuture) < weekEnd }),
            Group(title: "Later", items: open.filter { $0.dueAt != nil && $0.dueAt! >= weekEnd }),
            Group(title: "No due date", items: open.filter { $0.dueAt == nil }),
        ].filter { !$0.items.isEmpty }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            filterChip("All", color: Theme.accent, selected: subjectFilter == nil) { subjectFilter = nil }
                            ForEach(subjects) { s in
                                filterChip(s.name, color: Color(hex: s.color), selected: subjectFilter == s.id) { subjectFilter = s.id }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                if groups.isEmpty && !showDone {
                    EmptyCard(symbol: "tray", title: "No open assignments", text: "Add one from Today's quick-add bar or the + button.")
                }
                ForEach(groups) { g in
                    SectionTitle(g.title)
                    VStack(spacing: 8) { ForEach(g.items) { AssignmentRow(assignment: $0) } }
                }
                let done = list.filter { $0.status == .done }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                if !done.isEmpty {
                    Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                        Label("\(showDone ? "Hide" : "Show") \(done.count) done", systemImage: showDone ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 6)
                    if showDone { VStack(spacing: 8) { ForEach(done.prefix(50)) { AssignmentRow(assignment: $0) } } }
                }
                Spacer(minLength: 100)
            }
            .padding(.horizontal)
        }
    }

    struct Group: Identifiable {
        var title: String
        var items: [Assignment]
        var id: String { title }
    }

    private func filterChip(_ title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() }; Haptics.select() }) {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(color.opacity(0.5)).interactive() : .regular.interactive(), in: .capsule)
    }
}

// MARK: - Activity

/// Everything Instinct and the planners did, newest first, each batch undoable in one tap.
struct ActivityFeed: View {
    @Environment(Store.self) private var store
    @Query(filter: #Predicate<ActivityItem> { !$0.trashed }, sort: \ActivityItem.at, order: .reverse) private var items: [ActivityItem]

    var body: some View {
        let groups = grouped(Array(items.prefix(400)))
        ScrollView {
            VStack(spacing: 10) {
                if groups.isEmpty {
                    EmptyCard(symbol: "sparkles", title: "Nothing yet",
                              text: "When Instinct adds, moves or deletes something, it shows up here with its reason and an Undo.")
                }
                ForEach(groups) { g in ActivityGroupCard(items: g.items) }
                Spacer(minLength: 100)
            }
            .padding(.horizontal)
        }
    }

    struct Batch: Identifiable {
        var id: UUID
        var items: [ActivityItem]
    }

    private func grouped(_ list: [ActivityItem]) -> [Batch] {
        var order: [UUID] = []
        var map: [UUID: [ActivityItem]] = [:]
        for i in list {
            let key = i.batchID ?? i.id
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(i)
        }
        return order.map { Batch(id: $0, items: map[$0] ?? []) }
    }
}

struct ActivityGroupCard: View {
    var items: [ActivityItem]
    @Environment(Store.self) private var store
    @State private var expanded = false

    var body: some View {
        let first = items[0]
        let actor = Actor(rawValue: first.actor) ?? .instinct
        let undone = items.allSatisfy { $0.undoneAt != nil }
        let reason = items.compactMap(\.reason).first { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if actor == .instinct { InstinctBadge() } else { Label(actor.label, systemImage: actor == .auto ? "wand.and.stars" : "person").font(.caption.weight(.semibold)) }
                Text(first.at.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if undone {
                    Label("Undone", systemImage: "arrow.uturn.backward").font(.caption).foregroundStyle(.secondary)
                } else if let batch = first.batchID {
                    Button("Undo") { store.undo(batch: batch) }.buttonStyle(.glass).controlSize(.small)
                } else {
                    Button("Undo") { store.undo(first) }.buttonStyle(.glass).controlSize(.small)
                }
            }
            Text(headline).font(.subheadline.weight(.semibold))
            if let reason { Text(reason).font(.caption).foregroundStyle(Theme.instinct) }
            let shown = expanded ? items : Array(items.prefix(4))
            ForEach(shown) { i in
                Label(i.summary.isEmpty ? "\(i.action.capitalized) \(i.entity ?? "")" : i.summary, systemImage: symbol(i.action))
                    .font(.caption).foregroundStyle(i.undoneAt == nil ? .primary : .secondary)
                    .strikethrough(i.undoneAt != nil)
            }
            if items.count > 4 {
                Button(expanded ? "Show less" : "Show all \(items.count)") { withAnimation(.snappy) { expanded.toggle() } }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
        }
        .glassCard(tint: actor == .instinct ? Theme.instinct : nil, radius: 20, padding: 14)
        .opacity(undone ? 0.6 : 1)
    }

    private var headline: String {
        let created = items.filter { $0.action == "created" }.count
        let deleted = items.filter { $0.action == "deleted" }.count
        let updated = items.filter { $0.action == "updated" }.count
        var parts: [String] = []
        if created > 0 { parts.append("added \(created)") }
        if updated > 0 { parts.append("changed \(updated)") }
        if deleted > 0 { parts.append("removed \(deleted)") }
        let things = Set(items.compactMap(\.entity)).count == 1 ? noun(items[0].entity, plural: items.count != 1) : "items"
        return parts.isEmpty ? (items[0].summary) : (parts.joined(separator: ", ").capitalizedFirst + " " + things)
    }

    private func noun(_ entity: String?, plural: Bool) -> String {
        let n: String
        switch entity {
        case "blocks": n = "block"
        case "assignments": n = "assignment"
        case "cards": n = "card"
        case "decks": n = "deck"
        case "topics": n = "topic"
        case "chapters": n = "chapter"
        case "subjects": n = "subject"
        default: n = "item"
        }
        return plural ? n + "s" : n
    }

    private func symbol(_ action: String) -> String {
        switch action {
        case "created": return "plus.circle"
        case "deleted": return "minus.circle"
        case "updated": return "pencil.circle"
        default: return "circle"
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
