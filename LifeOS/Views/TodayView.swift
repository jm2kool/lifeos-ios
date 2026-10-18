import SwiftUI

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant

    var body: some View {
        let _ = store.tick
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ChangesBanner()
                messages
                GeminiCard()
                stats.padding(.top, 12)
                SectionHeader(title: "Your day", action: "Timetable") { store.tab = .library }
                DayTimeline(day: store.today)
                attention
                tasks
                comingUp
                feed
                Text(store.syncStatus).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 28)
            }
            .padding(.horizontal, UI.gutter)
            .padding(.bottom, 30)
        }
        .pageBackground()
        .navigationDestination(for: LibraryPage.self) { $0.view }
        .navigationTitle(store.greeting)
        .navigationSubtitle(store.dayLabel(store.today))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.sheet = .ask("") } label: { Image(systemName: "sparkles") }.accessibilityLabel("Ask Gemini")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Settings", systemImage: "gearshape") { store.sheet = .settings }
                    Button("Activity", systemImage: "clock.arrow.circlepath") { store.sheet = .activity }
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { Task { await store.pull() } }
                } label: { Avatar(name: store.profileName) }
            }
        }
        .refreshable {
            await store.pull()
            await assistant.runPulse(force: true)
        }
    }

    // Notes your iMessage assistant or Gemini pinned
    @ViewBuilder private var messages: some View {
        ForEach(store.messages.prefix(3), id: \.self) { m in
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: "bubble.left.fill", color: .accentColor, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(m["from"].str) · \(store.ago(m["at"].double ?? 0))").font(.caption).foregroundStyle(.secondary)
                    Text(m["text"].str).font(.callout)
                    if let u = URL(string: m["url"].str), m["url"].str.hasPrefix("http") { Link("Open", destination: u).font(.callout.weight(.semibold)) }
                }
                Spacer(minLength: 0)
                Button { store.act(["op": "message.dismiss", "id": m["id"]]) } label: { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss")
            }
            .card(padding: 14).padding(.bottom, 10)
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            if let b = store.bigThing {
                let c = store.countdown(b)
                StatTile(symbol: "flag.fill", color: .red, title: "Countdown", value: c.value, unit: c.unit, sub: b.title)
            }
            StatTile(symbol: "timer", color: .orange, title: "Focus", value: "\(store.focusMinutes(store.today))", unit: "min", sub: "today")
            StatTile(symbol: "flame.fill", color: .pink, title: "Streak", value: "\(store.streak)", unit: store.streak == 1 ? "day" : "days", sub: "in a row")
        }
    }

    @ViewBuilder private var attention: some View {
        let due = store.cards.filter { let ds = store.dueState($0.due, column: $0.column); return ds == .overdue || ds == .soon }
        let replies = store.drafts.filter { d in d.isEmail && store.review(d, d.latest?.version ?? 1, "email-draft") == nil }
        if !due.isEmpty || !replies.isEmpty {
            SectionHeader(title: "Needs you")
            Divided {
                ForEach(replies) { d in
                    NavigationLink(value: LibraryPage.draft(d.id)) {
                        row(symbol: "envelope.fill", color: .blue, title: d.title, sub: "Reply drafted by \(d.latest?.by.isEmpty == false ? d.latest!.by : "Gemini"). Review and send.")
                    }.buttonStyle(.plain)
                    RowDivider()
                }
                ForEach(due) { c in
                    NavigationLink(value: LibraryPage.board) {
                        row(symbol: "exclamationmark.circle.fill", color: store.dueState(c.due) == .overdue ? .red : .orange, title: c.title, sub: store.dueText(c.due))
                    }.buttonStyle(.plain)
                    if c.id != due.last?.id { RowDivider() }
                }
            }
            .card(padding: 0)
        }
    }
    private func row(symbol: String, color: Color, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).lineLimit(2)
                Text(sub).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).contentShape(.rect)
    }

    @ViewBuilder private var tasks: some View {
        SectionHeader(title: "To do", action: "Add") { store.sheet = .addTask }
        VStack(spacing: 0) {
            if store.openTasks.isEmpty { EmptyNote(text: "All clear. Nothing left on your list.") }
            ForEach(store.openTasks) { t in
                TaskRow(task: t)
                if t.id != store.openTasks.last?.id { RowDivider(inset: 50) }
            }
        }
        .card(padding: 0)
        if !store.doneTasks.isEmpty {
            DisclosureGroup("\(store.doneTasks.count) completed") {
                VStack(spacing: 0) { ForEach(store.doneTasks) { TaskRow(task: $0) } }
            }
            .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.top, 10)
        }
    }

    @ViewBuilder private var comingUp: some View {
        let list = Array(store.upcoming.prefix(4))
        SectionHeader(title: "Coming up", action: "Calendar") { store.tab = .library }
        VStack(spacing: 0) {
            if list.isEmpty { EmptyNote(text: "Nothing on your calendar.") }
            ForEach(list) { e in
                Button { store.sheet = .event(e.id) } label: { EventRow(event: e) }.buttonStyle(.plain)
                if e.id != list.last?.id { RowDivider(inset: 66) }
            }
        }
        .card(padding: 0)
        if let c = store.events.map(\.checkedAt).max(), !c.isEmpty {
            let ch = store.checked(c)
            Text(ch.label + (ch.stale ? ". May be out of date." : "")).font(.caption).foregroundStyle(ch.stale ? .orange : .secondary).padding(.horizontal, 6).padding(.top, 8)
        }
    }

    @ViewBuilder private var feed: some View {
        let items = Array(store.feed.prefix(2))
        if !items.isEmpty {
            SectionHeader(title: "From your feed")
            VStack(spacing: 0) {
                ForEach(items) { f in
                    Button { store.sheet = .feed(f.id) } label: { FeedRow(item: f) }.buttonStyle(.plain)
                    if f.id != items.last?.id { Divider().padding(.leading, 14) }
                }
            }
            .card(padding: 0)
        }
    }
}

// MARK: Gemini's brief on Today
struct GeminiCard: View {
    @Environment(Store.self) private var store
    @Environment(Assistant.self) private var assistant
    @State private var expanded = false

    var body: some View {
        let p = store.pulse
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("Gemini").font(.subheadline.weight(.semibold))
                if let at = p["at"].double { Text("· " + store.ago(at)).font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                if assistant.pulsing { ProgressView().controlSize(.small) }
                else {
                    Button { Task { await assistant.runPulse(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Refresh")
                }
            }
            if let brief = p["brief"].string, !brief.isEmpty {
                Text(brief).font(.callout).lineLimit(expanded ? nil : 3).fixedSize(horizontal: false, vertical: true)
                    .contentShape(.rect).onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
                if let f = p["focus"].string, !f.isEmpty {
                    let t = store.target(for: f, hint: p["focusTarget"])
                    Button { if let t { store.open(t) } else { store.sheet = .ask(f) } } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("Do next").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                            Text(f).font(.footnote.weight(.medium)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                let rows = suggestions(p)
                if !rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                            let t = store.target(for: r.text, hint: r.hint)
                            Button { if let t { store.open(t) } else { store.sheet = .ask(r.text) } } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: icon(t?["page"].str ?? "")).font(.footnote).foregroundStyle(.tint).frame(width: 18)
                                    Text(r.text).font(.footnote).foregroundStyle(.primary).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 9).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            if i < rows.count - 1 { Divider().padding(.leading, 28) }
                        }
                    }
                }
                if !p["changes"].array.isEmpty {
                    let n = p["changes"].array.count
                    HStack(spacing: 6) {
                        Text("Gemini made \(n) change\(n == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Details") { store.sheet = .activity }.font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(.tint)
                        if let u = UUID(uuidString: p["undo"].str), let e = store.undoStack.first(where: { $0.id == u }) {
                            Button("Undo") {
                                store.undoStack.removeAll { $0.id == u }
                                store.act(e.ops, quiet: true)
                                var q = store.pulse; q["changes"] = []; q["undo"] = .null
                                store.act(["op": "content.set", "path": "pulse", "value": q], quiet: true)
                            }.font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(.tint)
                        }
                    }
                }
            } else if assistant.available {
                Text("Let Gemini read your schedule, inbox and deadlines and tell you what matters today. It refreshes on its own every couple of hours.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Plan my day") { Task { await assistant.runPulse(force: true) } }.buttonStyle(.glassProminent)
            } else {
                Text("Add your Gemini key in Settings and this card fills itself in every hour or two: your priorities, reply drafts and what to do next.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Settings") { store.sheet = .settings }.buttonStyle(.glass)
            }
        }
        .card()
    }
    private struct Suggestion { let text: String; let hint: JSON }
    /// Up to two highlights that say something different from "Do next".
    private func suggestions(_ p: JSON) -> [Suggestion] {
        let focusText = p["focus"].str
        var out: [Suggestion] = []
        for h in p["highlights"].array where !h["text"].str.isEmpty && !Reducer.alike(h["text"].str, focusText) {
            if out.count >= 2 { break }
            out.append(Suggestion(text: h["text"].str, hint: ["page": h["page"], "id": h["id"]]))
        }
        return out
    }
    private func icon(_ page: String) -> String {
        switch page {
        case "draft", "drafts": return "doc.text"
        case "inbox", "email": return "tray"
        case "calendar", "event": return "calendar"
        case "board", "card": return "rectangle.split.3x1"
        case "study": return "book.closed"
        case "timetable": return "clock"
        default: return "sparkles"
        }
    }
}

// MARK: Structured-style timeline of the day
struct DayTimeline: View {
    @Environment(Store.self) private var store
    let day: String

    var body: some View {
        let blocks = store.blocks(on: day)
        let now = Date()
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing planned \(day == store.today ? "today" : "this day")").font(.body.weight(.medium))
                    if let next = store.now.next {
                        Text("Next up: \(next.title), \(store.relDay(next.day).lowercased()) at \(store.time(next.start))").font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Add a block") { store.sheet = .addBlock }.buttonStyle(.glass)
                        Button("Plan with Gemini") { store.sheet = .ask("Plan the rest of my day into timetable blocks.") }.buttonStyle(.glass)
                    }.padding(.top, 4)
                }
                .padding(16)
            }
            ForEach(Array(blocks.enumerated()), id: \.element.id) { i, b in
                if day == store.today, now >= (i == 0 ? .distantPast : blocks[i - 1].end), now < b.start, i == 0 || now >= blocks[i - 1].start {
                    nowLine
                }
                let gap = i > 0 ? b.start.timeIntervalSince(blocks[i - 1].end) : 0
                if gap >= 45 * 60 {
                    Text("Free · \(store.duration(gap))").font(.caption).foregroundStyle(.tertiary).padding(.leading, 78).padding(.vertical, 4)
                }
                BlockRow(block: b, state: b.end <= now ? .past : (b.start <= now ? .now : .later))
            }
            if day == store.today, let last = blocks.last, now >= last.end { nowLine }
        }
        .padding(.vertical, blocks.isEmpty ? 0 : 8)
        .card(padding: 0)
    }
    private var nowLine: some View {
        HStack(spacing: 6) {
            Text(store.time(Date())).font(.caption2.weight(.bold)).foregroundStyle(.red).frame(width: 64, alignment: .trailing)
            Circle().fill(.red).frame(width: 7, height: 7)
            Rectangle().fill(.red).frame(height: 1.5)
        }
        .padding(.trailing, 14).padding(.vertical, 2)
    }
}

struct BlockRow: View {
    @Environment(Store.self) private var store
    enum Phase { case past, now, later }
    let block: Block
    let state: Phase
    var color: Color {
        switch block.kind { case .calendar: return .red; case .study: return .indigo; case .timetable: return .blue; case .rest: return .gray }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.time(block.start)).font(.footnote.weight(.semibold).monospacedDigit())
                Text(store.time(block.end)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 64, alignment: .trailing)
            Capsule().fill(color.gradient).frame(width: 4).frame(minHeight: 36)
                .overlay(alignment: .top) { if state == .now { Circle().fill(color).frame(width: 10, height: 10).offset(y: -2) } }
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title).font(.body.weight(state == .now ? .semibold : .regular)).strikethrough(state == .past && block.kind != .calendar, color: .secondary)
                Text(kindLabel + " · " + store.duration(block.end.timeIntervalSince(block.start))).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if state == .now { Pill(text: "Now", color: color) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .opacity(state == .past ? 0.5 : 1)
        .background(state == .now ? color.opacity(0.08) : .clear)
    }
    private var kindLabel: String {
        switch block.kind { case .calendar: return "Calendar"; case .study: return "Study"; case .timetable: return "Timetable"; case .rest: return "Break" }
    }
}

struct TaskRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    var body: some View {
        let done = store.isDone(task.id)
        HStack(alignment: .top, spacing: 12) {
            CheckCircle(done: done) {
                store.act(["op": "task.done", "id": .string(task.id), "done": .bool(!done), "title": .string(task.title)], undo: done ? nil : "Completed “\(task.title)”")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.body).strikethrough(done, color: .secondary).foregroundStyle(done ? .secondary : .primary)
                if !task.note.isEmpty { Text(task.note).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 6) {
                    if let due = task.due { Pill(text: store.dueText(due), color: due < store.today ? .red : .secondary, icon: "calendar") }
                    if store.changedBy(task.changedBy) != nil { ChangedByTag(by: task.changedBy) }
                    else if !task.src.isEmpty && task.src != "You" { Text(task.src).font(.caption).foregroundStyle(.tertiary) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(.rect)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { EditBuffer.shared.task = task; store.sheet = .addTask }
            Button("Move to Board", systemImage: "rectangle.split.3x1") {
                let ops: [JSON] = [["op": "board.add", "title": .string(task.title), "note": .string(task.note), "due": JSON(task.due)], ["op": "task.remove", "id": .string(task.id)]]
                store.act(ops, undo: "Moved to Board")
            }
            Button("Send to \(store.assistantName)", systemImage: "message") { store.sheet = .delegate("From LifeOS (task \(task.id)):\n\(task.title)\n\(task.note)\n\nWhat I want done: ") }
            Button("Ask Gemini", systemImage: "sparkles") { store.sheet = .ask("Help me with this task: \(task.title)") }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { store.act(["op": "task.remove", "id": .string(task.id), "title": .string(task.title)], undo: "Task deleted") }
        }
    }
}

struct EventRow: View {
    @Environment(Store.self) private var store
    let event: Event
    var body: some View {
        let d = store.day(event)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(store.date(d, minutes: 720).formatted(.dateTime.month(.abbreviated))).font(.caption2.weight(.bold)).foregroundStyle(.red).textCase(.uppercase)
                Text(store.date(d, minutes: 720).formatted(.dateTime.day())).font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.medium)).lineLimit(2)
                Text(store.relDay(d) + (event.timed ? ", " + store.time(store.start(event)) + (event.end != nil ? "–" + store.time(store.end(event)) : "") : ", all day"))
                    .font(.footnote).foregroundStyle(.secondary)
                ChangedByTag(by: event.changedBy)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11).contentShape(.rect)
    }
}

struct FeedRow: View {
    let item: FeedItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol(item.icon)).font(.caption.weight(.bold)).foregroundStyle(Color.token(item.colorToken))
                Text(item.category).font(.caption.weight(.semibold)).foregroundStyle(Color.token(item.colorToken))
                Text(item.when).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if item.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary) }
            }
            Text(item.title).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
            Text(item.desc).font(.footnote).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
    }
}

/// Lets a context menu hand an item to an edit sheet.
@MainActor
final class EditBuffer {
    static let shared = EditBuffer()
    var task: TaskItem?
    var card: Card?
    var saved: SavedItem?
}
