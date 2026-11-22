import SwiftUI

/// One page per lesson, from the one on now downwards, then homework and the pack list.
/// Swipe or turn the Digital Crown to move between them, or double-tap your fingers for the next one.
struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.scenePhase) private var phase
    @State private var page: String?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let plan = DayPlan(store.timetable, now: context.date)
            let pages = Self.pages(plan, store.timetable)
            TabView(selection: $page) {
                ForEach(pages) { item in
                    pageView(item, plan: plan)
                        .tag(Optional(item.id))
                }
            }
            .tabViewStyle(.verticalPage)
            .overlay(alignment: .bottomTrailing) {
                if pages.count > 1 {
                    let atEnd = page == pages.last?.id
                    Button {
                        withAnimation { page = atEnd ? Self.focus(plan, pages) : next(after: page, in: pages) }
                    } label: {
                        Image(systemName: atEnd ? "arrow.uturn.up" : "chevron.down")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .frame(width: 40, height: 40)
                    .handGestureShortcut(.primaryAction)
                    .accessibilityLabel(atEnd ? "Back to now" : "Next")
                    .padding(.trailing, 4)
                }
            }
            .onAppear {
                guard page == nil else { return }
                // LINEUP_PAGE=homework or pack opens on that page, for the simulator screenshots.
                let start = ProcessInfo.processInfo.environment["LINEUP_PAGE"]
                page = pages.contains { $0.id == start } ? start : Self.focus(plan, pages)
            }
            .onChange(of: phase) { _, phase in
                // Each time you raise your wrist to the app, start from what's on now.
                guard phase == .active else { return }
                store.refresh()
                let plan = DayPlan(store.timetable, now: .now)
                page = Self.focus(plan, Self.pages(plan, store.timetable))
            }
        }
    }

    @ViewBuilder
    private func pageView(_ item: WatchPage, plan: DayPlan) -> some View {
        switch item {
        case .lesson(let slot):
            LessonPage(slot: slot, label: plan.label(for: slot), now: plan.now)
        case .noLessons:
            NoLessonsPage(plan: plan, timetable: store.timetable)
        case .homework:
            HomeworkPage(now: plan.now)
        case .pack:
            PackPage(plan: plan)
        }
    }

    private func next(after id: String?, in pages: [WatchPage]) -> String? {
        guard let id, let i = pages.firstIndex(where: { $0.id == id }), i + 1 < pages.count else { return pages.first?.id }
        return pages[i + 1].id
    }

    static func pages(_ plan: DayPlan, _ timetable: Timetable) -> [WatchPage] {
        var pages: [WatchPage] = plan.slots.isEmpty ? [.noLessons] : plan.slots.map { .lesson($0) }
        if !timetable.assignments.isEmpty {
            pages.append(.homework)
        }
        if !plan.packSlots.isEmpty { pages.append(.pack) }
        return pages
    }

    /// The page to open on: the lesson on now or next; once school's over, homework or packing.
    static func focus(_ plan: DayPlan, _ pages: [WatchPage]) -> String? {
        if let slot = plan.focus { return slot.id.uuidString }
        if plan.isOver {
            return pages.first { if case .homework = $0 { true } else { false } }?.id
                ?? pages.first { if case .pack = $0 { true } else { false } }?.id
                ?? pages.last?.id
        }
        return pages.first?.id
    }
}

enum WatchPage: Identifiable {
    case lesson(Slot)
    case noLessons
    case homework
    case pack

    var id: String {
        switch self {
        case .lesson(let slot): slot.id.uuidString
        case .noLessons: "none"
        case .homework: "homework"
        case .pack: "pack"
        }
    }
}

/// A lesson, big enough to read at a glance.
struct LessonPage: View {
    let slot: Slot
    let label: String
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(slot.colour)
                Spacer()
                Text(Clock.range(slot.start, slot.end))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(slot.name)
                .font(.title2.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if !slot.room.isEmpty {
                Label(slot.room, systemImage: "mappin.and.ellipse")
                    .font(.headline)
                    .lineLimit(1)
            }
            if !slot.teacher.isEmpty {
                Text(slot.teacher).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer(minLength: 2)

            if slot.isNow(now) {
                ProgressView(value: slot.progress(now)).tint(slot.colour)
                Text("Ends in \(Text(timerInterval: now...slot.end, countsDown: true))")
                    .font(.footnote.monospacedDigit())
            } else if slot.start > now {
                Text("In \(Text(slot.start, style: .relative))")
                    .font(.footnote)
            } else {
                Text("Finished").font(.footnote).foregroundStyle(.secondary)
            }
            if !slot.bring.isEmpty {
                Text("Bring: \(slot.bring.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.trailing, 40)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .opacity(slot.end <= now ? 0.6 : 1)
        .containerBackground(LinearGradient(colors: [slot.colour.opacity(0.55), .black], startPoint: .top, endPoint: .bottom),
                             for: .tabView)
    }
}

/// A day off, or no timetable yet.
struct NoLessonsPage: View {
    let plan: DayPlan
    let timetable: Timetable

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if timetable.lessons.isEmpty {
                Image(systemName: "iphone").font(.title2)
                Text("No timetable yet").font(.headline)
                Text("Add your lessons in Lineup on your iPhone and they'll appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No lessons today").font(.title3.bold())
                if let day = timetable.nextSchoolDay(after: plan.now), let first = timetable.slots(on: day).first {
                    Text(Clock.relativeDay(day, now: plan.now)).font(.caption2.weight(.heavy)).foregroundStyle(first.colour)
                    Text(first.name).font(.headline)
                    Text([Clock.time(first.start), first.room].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .containerBackground(Color.indigo.gradient.opacity(0.5), for: .tabView)
    }
}

/// Homework still to do. Tap one to tick it off; the phone hears about it next time it's in range.
struct HomeworkPage: View {
    @EnvironmentObject private var store: WatchStore
    let now: Date

    private var items: [Assignment] {
        store.timetable.assignments
            .filter { !$0.done || store.ticked.contains($0.id) }
            .sorted { $0.due < $1.due }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Homework").font(.headline)
                if items.isEmpty {
                    Text("All done.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(items) { assignment in
                    let subject = store.timetable.subject(assignment.subjectID)
                    Button { store.toggle(assignment) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: assignment.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(assignment.done ? .green : (subject?.colour.color ?? .white))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(assignment.title)
                                    .font(.footnote.weight(.semibold))
                                    .strikethrough(assignment.done)
                                    .lineLimit(3)
                                Text([subject?.name, Clock.relativeDay(assignment.due, now: now)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(!assignment.done && Clock.isOverdue(assignment.due, now: now) ? .red : .secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 44)
        }
        .containerBackground(Color.green.gradient.opacity(0.35), for: .tabView)
    }
}

/// What to put in your bag for the next school day, with a tick for each thing.
struct PackPage: View {
    @EnvironmentObject private var store: WatchStore
    let plan: DayPlan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.packTitle).font(.headline)
                if let day = plan.packDay {
                    ForEach(plan.packGroups) { group in
                        Text(group.subject.name)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(group.subject.colour.color)
                            .padding(.top, 2)
                        ForEach(group.items, id: \.self) { item in
                            let key = store.packKey(day: day, subject: group.subject.id, item: item)
                            let done = store.packed.contains(key)
                            Button { store.togglePacked(key) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(done ? .green : .secondary)
                                    Text(item).font(.footnote).strikethrough(done)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !plan.handIn.isEmpty {
                        Text("HAND IN").font(.caption2.weight(.heavy)).foregroundStyle(.orange).padding(.top, 2)
                        ForEach(plan.handIn) { assignment in
                            Label(assignment.title, systemImage: "tray.and.arrow.up").font(.footnote)
                        }
                    }
                    if plan.packGroups.allSatisfy({ $0.items.isEmpty }) {
                        Text("Add things to bring to each subject in the iPhone app and they'll be listed here.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 44)
        }
        .containerBackground(Color.orange.gradient.opacity(0.35), for: .tabView)
    }
}
