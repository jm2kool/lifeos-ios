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
            LyricsLockScreen(state: context.state, stale: context.isStale)
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

/// The Lock Screen card: the song, then the lyrics as a short scroll — each new line slides up from below as
/// the old one moves up and fades, like the lyrics screen in the app.
struct LyricsLockScreen: View {
    let state: LyricsActivityAttributes.ContentState
    /// LINER. couldn't update for a while (iOS paused it): dim the lyrics rather than show a wrong line.
    var stale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: state.isPlaying ? "waveform" : "pause.fill").font(.system(size: 10, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text("\(state.title) · \(state.artist)".uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(1.6).lineLimit(1)
                    .id(state.title + state.artist)
                    .transition(.push(from: .bottom))
            }
            .foregroundStyle(.white.opacity(0.55))

            lines
                .id("\(state.title)|\(state.index)")
                .transition(.push(from: .bottom))
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .clipped()
                .opacity(stale ? 0.4 : 1)
            if stale {
                Text("Open \u{201C}LINER.\u{201D} to resume live lyrics").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.55), value: state.index)
        .animation(.smooth(duration: 0.55), value: state.title)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(state.previous.isEmpty ? " " : state.previous)
                .font(.system(size: 14, design: .serif)).foregroundStyle(.white.opacity(0.32)).lineLimit(1)
            Text(state.current.isEmpty ? "♪" : state.current)
                .font(.system(size: 23, weight: .semibold, design: .serif)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.7)
            Text(state.next.isEmpty ? " " : state.next)
                .font(.system(size: 14, design: .serif)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
    }
}
