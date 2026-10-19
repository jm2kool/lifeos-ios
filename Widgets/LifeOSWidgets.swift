import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

@main
struct LifeOSWidgets: WidgetBundle {
    var body: some Widget { FocusLiveActivity(); StudyBlockLiveActivity() }
}

/// The focus session on the Lock Screen and in the Dynamic Island.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusAttributes.self) { context in
            LockScreenFocus(label: context.attributes.label, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state, finished = s.done || context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.label, systemImage: "timer").font(.caption.weight(.semibold)).lineLimit(1).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: s, finished: finished).font(.title3.weight(.semibold).monospacedDigit()).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Bar(state: s, finished: finished)
                        if !finished { Controls(paused: s.paused) }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: finished ? "checkmark" : s.paused ? "pause.fill" : "timer").foregroundStyle(.tint)
            } compactTrailing: {
                Countdown(state: s, finished: finished).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Ring(state: s, finished: finished)
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct LockScreenFocus: View {
    let label: String, state: FocusAttributes.ContentState, stale: Bool
    var body: some View {
        let finished = state.done || stale
        HStack(spacing: 14) {
            Ring(state: state, finished: finished).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold)).lineLimit(1)
                Countdown(state: state, finished: finished).font(.title2.weight(.bold).monospacedDigit())
                Text(finished ? "Session done" : state.paused ? "Paused" : "Focusing").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !finished { Controls(paused: state.paused) }
        }
        .padding(16)
    }
}

private struct Countdown: View {
    let state: FocusAttributes.ContentState, finished: Bool
    var body: some View {
        if finished { Text("Done") }
        else if state.paused { Text(Duration.seconds(state.remaining).formatted(.time(pattern: .minuteSecond))) }
        else { Text(timerInterval: Date()...max(Date(), state.endDate), countsDown: true) }
    }
}

private struct Bar: View {
    let state: FocusAttributes.ContentState, finished: Bool
    var body: some View {
        if finished || state.paused { ProgressView(value: finished ? 1 : state.progress) }
        else { ProgressView(timerInterval: state.startDate...max(state.startDate.addingTimeInterval(1), state.endDate), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() } }
    }
}

private struct Ring: View {
    let state: FocusAttributes.ContentState, finished: Bool
    var body: some View {
        Group {
            if finished || state.paused {
                ProgressView(value: finished ? 1 : state.progress) { Image(systemName: finished ? "checkmark" : "pause.fill").font(.system(size: 9, weight: .bold)) }
            } else {
                ProgressView(timerInterval: state.startDate...max(state.startDate.addingTimeInterval(1), state.endDate), countsDown: false) {
                    Image(systemName: "timer").font(.system(size: 9, weight: .bold))
                } currentValueLabel: { EmptyView() }
            }
        }
        .progressViewStyle(.circular)
        .tint(.accentColor)
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

/// A study block on the Lock Screen and in the Dynamic Island: before it starts, while it's on, and at the break after.
struct StudyBlockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyBlockAttributes.self) { context in
            StudyLockScreen(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state, phase = s.shown(at: Date(), stale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(StudyText.heading(phase), systemImage: StudyText.symbol(phase)).font(.caption.weight(.semibold)).lineLimit(1).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StudyClock(state: s, phase: phase).font(.title3.weight(.semibold).monospacedDigit()).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.title).font(.headline).lineLimit(1)
                        StudyBar(state: s, phase: phase)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: StudyText.symbol(phase)).foregroundStyle(.tint)
            } compactTrailing: {
                StudyClock(state: s, phase: phase).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Image(systemName: StudyText.symbol(phase)).foregroundStyle(.tint)
            }
            .keylineTint(.accentColor)
        }
    }
}

private enum StudyText {
    static func heading(_ p: StudyBlockAttributes.Phase) -> String {
        switch p { case .upcoming: "Study block soon"; case .during: "Studying"; case .rest: "Break"; case .ended: "Block done" }
    }
    static func symbol(_ p: StudyBlockAttributes.Phase) -> String {
        switch p { case .upcoming: "book.closed"; case .during: "book"; case .rest: "cup.and.saucer"; case .ended: "checkmark" }
    }
}

private struct StudyLockScreen: View {
    let state: StudyBlockAttributes.ContentState, stale: Bool
    var body: some View {
        let phase = state.shown(at: Date(), stale: stale)
        HStack(spacing: 14) {
            Image(systemName: StudyText.symbol(phase)).font(.title2).foregroundStyle(.tint).frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                switch phase {
                case .upcoming:
                    Text(state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 4) { Text("starts in"); Text(timerInterval: Date()...max(Date(), state.start), countsDown: true).monospacedDigit() }
                        .font(.title3.weight(.bold))
                    Text(state.start.formatted(date: .omitted, time: .shortened) + "–" + state.end.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                case .during:
                    Text(state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 4) { Text(timerInterval: Date()...max(Date(), state.end), countsDown: true).monospacedDigit(); Text("left") }
                        .font(.title3.weight(.bold))
                    StudyBar(state: state, phase: phase)
                case .rest:
                    Text(state.note.isEmpty ? "Break" : state.note).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 4) { Text(state.title).lineLimit(1); Text("in"); Text(timerInterval: Date()...max(Date(), state.start), countsDown: true).monospacedDigit() }
                        .font(.title3.weight(.bold))
                case .ended:
                    Text(state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("Block done").font(.title3.weight(.bold))
                    Text("Nice work.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct StudyClock: View {
    let state: StudyBlockAttributes.ContentState, phase: StudyBlockAttributes.Phase
    var body: some View {
        switch phase {
        case .upcoming, .rest: Text(timerInterval: Date()...max(Date(), state.start), countsDown: true)
        case .during: Text(timerInterval: Date()...max(Date(), state.end), countsDown: true)
        case .ended: Text("Done")
        }
    }
}

private struct StudyBar: View {
    let state: StudyBlockAttributes.ContentState, phase: StudyBlockAttributes.Phase
    var body: some View {
        if phase == .during {
            ProgressView(timerInterval: state.start...max(state.start.addingTimeInterval(1), state.end), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(.accentColor)
        } else {
            ProgressView(value: phase == .ended ? 1 : 0).tint(.accentColor)
        }
    }
}
