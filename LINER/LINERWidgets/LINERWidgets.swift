import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LINERWidgets: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
    }
}

/// Live lyrics on the Lock Screen only: the line being sung, big and serif, with the lines either side dimmed.
/// iOS gives every Live Activity a Dynamic Island slot and has no way to opt out, so the island versions are
/// empty and clear, and the activity asks for the lowest priority so the system's own Now Playing takes the island.
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LyricsLockScreen(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { _ in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { EmptyView() }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                EmptyView()
            } minimal: {
                EmptyView()
            }
            .keylineTint(.clear)
        }
    }
}

struct LyricsLockScreen: View {
    let state: LyricsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: state.isPlaying ? "waveform" : "pause.fill").font(.system(size: 10, weight: .bold))
                Text("\(state.title) · \(state.artist)".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(1.6).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.55))
            if !state.previous.isEmpty {
                Text(state.previous).font(.system(size: 14, design: .serif)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
            }
            Text(state.current.isEmpty ? "♪" : state.current)
                .font(.system(size: 24, weight: .semibold, design: .serif)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.7)
                .contentTransition(.opacity)
            if !state.next.isEmpty {
                Text(state.next).font(.system(size: 14, design: .serif)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
