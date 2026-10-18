import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

@main
struct LifeOSWidgets: WidgetBundle {
    var body: some Widget { FocusLiveActivity() }
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
