import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

@main
struct LumenWidgets: WidgetBundle {
    var body: some Widget {
        NextBlockWidget()
        TodayWidget()
        DeadlineWidget()
        FocusLiveActivity()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    var placeholder = false
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .sample, placeholder: true) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview { completion(SnapshotEntry(date: Date(), snapshot: .sample)); return }
        Task { completion(SnapshotEntry(date: Date(), snapshot: await Self.load() ?? WidgetSnapshot())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        Task {
            let s = await Self.load() ?? WidgetSnapshot()
            let now = Date()
            // A new entry at each block boundary, so "Up next" moves on by itself.
            var dates = [now]
            for b in s.upcoming { dates += [b.start, b.end] }
            dates = Array(Set(dates.filter { $0 >= now && $0 < now.addingTimeInterval(24 * 3600) })).sorted()
            let entries = dates.prefix(20).map { SnapshotEntry(date: $0, snapshot: s) }
            completion(Timeline(entries: entries.isEmpty ? [SnapshotEntry(date: now, snapshot: s)] : Array(entries),
                                policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    static func load() async -> WidgetSnapshot? {
        if let s = SharedStore.load() { return s }
        guard let server = SharedStore.bakedServer(), let device = await SharedStore.deviceKey else { return nil }
        return await SharedStore.fetchRemote(device: device, server: server)
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            upcoming: [.init(id: "x", title: "Projectile motion questions", subject: "Physics", colorHex: "#7C8CFF",
                             start: now.addingTimeInterval(1800), end: now.addingTimeInterval(4800), kind: "study")],
            todayMinutes: 75, goalMinutes: 120, streak: 6,
            deadline: .init(title: "Chemistry lab report", subject: "Chemistry", colorHex: "#5BE3A1", due: now.addingTimeInterval(86400 * 2), kind: "project"),
            dueCards: 24, updated: now)
    }
}

// MARK: - Up next

struct NextBlockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LumenNextBlock", provider: SnapshotProvider()) { entry in
            NextBlockView(entry: entry).containerBackground(for: .widget) { WidgetBackground(hex: entry.snapshot.next(at: entry.date)?.colorHex) }
        }
        .configurationDisplayName("Up next")
        .description("Your next study block, with a tap to start focusing.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NextBlockView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let b = entry.snapshot.next(at: entry.date)
        let color = Color(hex: b?.colorHex ?? "#8FA8FF")
        Group {
            switch family {
            case .accessoryInline:
                if let b { Text("\(b.subject) \(b.start.formatted(date: .omitted, time: .shortened))") } else { Text("No blocks planned") }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    if let b {
                        Text(b.start <= entry.date ? "NOW" : b.start.formatted(date: .omitted, time: .shortened)).font(.caption2.weight(.bold))
                        Text(b.title).font(.headline).lineLimit(1)
                        Text(b.subject).font(.caption2).lineLimit(1)
                    } else {
                        Text("Lumen").font(.caption2.weight(.bold))
                        Text("Nothing planned").font(.headline)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(b == nil ? "LUMEN" : (b!.start <= entry.date ? "NOW" : "UP NEXT")).font(.caption2.weight(.heavy)).foregroundStyle(color)
                        Spacer()
                        Image(systemName: b?.kind == "review" ? "rectangle.on.rectangle.angled" : "book").foregroundStyle(color)
                    }
                    if let b {
                        Text(b.title).font(.headline).lineLimit(family == .systemSmall ? 3 : 2)
                        Spacer(minLength: 0)
                        Text(b.subject).font(.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1)
                        HStack {
                            Text("\(b.start.formatted(date: .omitted, time: .shortened))–\(b.end.formatted(date: .omitted, time: .shortened))")
                            Spacer()
                            if b.start > entry.date { Text(b.start, style: .relative).multilineTextAlignment(.trailing) }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        if family == .systemMedium, entry.snapshot.upcoming.count > 1 {
                            let later = entry.snapshot.upcoming.filter { $0.start > b.start }.prefix(2)
                            ForEach(later) { l in
                                Text("\(l.start.formatted(date: .omitted, time: .shortened)) · \(l.title)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    } else {
                        Spacer(minLength: 0)
                        Text("Nothing planned").font(.headline)
                        Text("Instinct will fill this in.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .widgetURL(URL(string: b.map { "lumen://focus?block=\($0.id)" } ?? "lumen://planner"))
        .redacted(reason: entry.placeholder ? .placeholder : [])
    }
}

// MARK: - Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LumenToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry).containerBackground(for: .widget) { WidgetBackground(hex: "#8FA8FF") }
        }
        .configurationDisplayName("Today")
        .description("Minutes studied today, your streak and cards due.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        let stale = !Calendar.current.isDate(s.updated, inSameDayAs: entry.date)
        let minutes = stale ? 0 : s.todayMinutes
        let progress = min(1, Double(minutes) / Double(max(1, s.goalMinutes)))
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: progress) { Image(systemName: "flame") } currentValueLabel: { Text("\(minutes)") }
                    .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Text("\(minutes) min · \(s.streak)-day streak")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text("Studied today").font(.caption2.weight(.bold))
                    Text("\(minutes) of \(s.goalMinutes) min").font(.headline)
                    Text("🔥 \(s.streak) days · \(s.dueCards) cards due").font(.caption2)
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 6)
                            Circle().trim(from: 0, to: max(0.01, progress)).stroke(Color(hex: "#8FA8FF"), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 44, height: 44)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(s.streak)").font(.title2.weight(.bold))
                            Text("day streak").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("\(minutes) min").font(.title3.weight(.bold))
                    Text("of \(s.goalMinutes) min today").font(.caption).foregroundStyle(.secondary)
                    if s.dueCards > 0 { Label("\(s.dueCards) cards due", systemImage: "rectangle.on.rectangle.angled").font(.caption2) }
                }
            }
        }
        .widgetURL(URL(string: "lumen://focus"))
        .redacted(reason: entry.placeholder ? .placeholder : [])
    }
}

// MARK: - Deadline

struct DeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LumenDeadline", provider: SnapshotProvider()) { entry in
            DeadlineView(entry: entry).containerBackground(for: .widget) { WidgetBackground(hex: entry.snapshot.deadline?.colorHex) }
        }
        .configurationDisplayName("Next deadline")
        .description("The next assignment or exam that's due.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct DeadlineView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let d = entry.snapshot.deadline.flatMap { $0.due > entry.date ? $0 : nil }
        let color = Color(hex: d?.colorHex ?? "#FFB35C")
        Group {
            switch family {
            case .accessoryInline:
                if let d { Text("\(d.title) · \(d.due.formatted(.dateTime.weekday(.abbreviated)))") } else { Text("No deadlines") }
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text("DUE \(d.map { $0.due.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "")").font(.caption2.weight(.bold))
                    Text(d?.title ?? "No deadlines").font(.headline).lineLimit(1)
                    if let d { Text(d.due, style: .relative).font(.caption2) }
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("DUE").font(.caption2.weight(.heavy)).foregroundStyle(color)
                        Spacer()
                        Image(systemName: icon(d?.kind)).foregroundStyle(color)
                    }
                    if let d {
                        Text(d.title).font(.headline).lineLimit(3)
                        Spacer(minLength: 0)
                        Text(d.subject).font(.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1)
                        Text(d.due, style: .relative).font(.title3.weight(.bold))
                        Text(d.due.formatted(.dateTime.weekday(.wide).hour().minute())).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Spacer(minLength: 0)
                        Text("Nothing due").font(.headline)
                        Text("Enjoy it.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .widgetURL(URL(string: "lumen://planner"))
        .redacted(reason: entry.placeholder ? .placeholder : [])
    }

    private func icon(_ kind: String?) -> String {
        switch kind {
        case "exam": return "graduationcap"
        case "test": return "checklist"
        case "project": return "hammer"
        case "revision": return "arrow.triangle.2.circlepath"
        default: return "doc.text"
        }
    }
}

struct WidgetBackground: View {
    var hex: String?
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color(hex: hex ?? "#8FA8FF").opacity(0.45), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
        }
    }
}

// MARK: - Live Activity

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { context in
            FocusLockScreen(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let color = s.isBreak ? Color(hex: "#5BE3A1") : Color(hex: context.attributes.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.subject.isEmpty ? "Focus" : context.attributes.subject, systemImage: s.isBreak ? "cup.and.saucer.fill" : "timer")
                        .font(.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: s, stale: context.isStale).font(.title3.weight(.semibold).monospacedDigit()).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                        HStack {
                            Text("\(s.label) · round \(s.round) of \(s.rounds)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Controls(paused: s.paused)
                        }
                        Bar(state: s, color: color)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: s.isBreak ? "cup.and.saucer.fill" : (s.paused ? "pause.fill" : "timer")).foregroundStyle(color)
            } compactTrailing: {
                Countdown(state: s, stale: context.isStale).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Ring(state: s, color: color)
            }
            .keylineTint(color)
            .widgetURL(URL(string: "lumen://focus"))
        }
    }
}

private struct FocusLockScreen: View {
    let attributes: FocusAttributes
    let state: FocusAttributes.ContentState
    let stale: Bool
    var body: some View {
        let color = state.isBreak ? Color(hex: "#5BE3A1") : Color(hex: attributes.colorHex)
        HStack(spacing: 14) {
            Ring(state: state, color: color).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Countdown(state: state, stale: stale).font(.title2.weight(.bold).monospacedDigit())
                Text("\(state.label) · round \(state.round)/\(state.rounds)\(attributes.subject.isEmpty ? "" : " · \(attributes.subject)")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Controls(paused: state.paused)
        }
        .padding(16)
    }
}

private struct Countdown: View {
    let state: FocusAttributes.ContentState
    let stale: Bool
    var body: some View {
        if stale && !state.paused { Text(state.isBreak ? "Break over" : "Round done") }
        else if state.paused { Text(Duration.seconds(state.remaining).formatted(.time(pattern: .minuteSecond))) }
        else { Text(timerInterval: Date()...max(Date(), state.endDate), countsDown: true) }
    }
}

private struct Bar: View {
    let state: FocusAttributes.ContentState
    let color: Color
    var body: some View {
        Group {
            if state.paused { ProgressView(value: state.progress) }
            else {
                ProgressView(timerInterval: state.startDate...max(state.startDate.addingTimeInterval(1), state.endDate), countsDown: false) {
                    EmptyView()
                } currentValueLabel: { EmptyView() }
            }
        }
        .tint(color)
    }
}

private struct Ring: View {
    let state: FocusAttributes.ContentState
    let color: Color
    var body: some View {
        Group {
            if state.paused {
                ProgressView(value: state.progress) { Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold)) }
            } else {
                ProgressView(timerInterval: state.startDate...max(state.startDate.addingTimeInterval(1), state.endDate), countsDown: false) {
                    Image(systemName: state.isBreak ? "cup.and.saucer.fill" : "timer").font(.system(size: 9, weight: .bold))
                } currentValueLabel: { EmptyView() }
            }
        }
        .progressViewStyle(.circular)
        .tint(color)
    }
}

private struct Controls: View {
    let paused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleFocusIntent()) { Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 34, height: 34) }
                .buttonStyle(.plain).background(.white.opacity(0.18), in: .circle)
                .accessibilityLabel(paused ? "Resume" : "Pause")
            Button(intent: EndFocusIntent()) { Image(systemName: "stop.fill").frame(width: 34, height: 34) }
                .buttonStyle(.plain).background(.white.opacity(0.18), in: .circle)
                .accessibilityLabel("End")
        }
        .font(.system(size: 14, weight: .bold))
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x8FA8FF
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}
