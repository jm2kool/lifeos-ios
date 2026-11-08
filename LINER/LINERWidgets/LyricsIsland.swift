import ActivityKit
import SwiftUI
import WidgetKit

/// The Dynamic Island for live lyrics. iOS gives every Live Activity an island and won't let us opt out, so it
/// earns its place: compact, a little record and a progress ring that iOS moves by itself (no updates needed);
/// expanded, the line being sung, the next line, and the song's progress with the time left.
enum LyricsIsland {
    static func island(_ state: LyricsActivityAttributes.ContentState) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                MiniRecord(playing: state.isPlaying).frame(width: 44, height: 44).padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                TimeLeft(state: state).padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.center) {
                VStack(spacing: 1) {
                    Text(state.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(state.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.current.isEmpty ? "♪" : state.current)
                            .font(.system(size: 19, weight: .semibold, design: .serif)).lineLimit(2).minimumScaleFactor(0.7)
                        if !state.next.isEmpty {
                            Text(state.next).font(.system(size: 13, design: .serif)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                        }
                    }
                    .id("\(state.title)|\(state.index)")
                    .transition(.push(from: .bottom))
                    ProgressLine(state: state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .animation(.smooth(duration: 0.5), value: state.index)
            }
        } compactLeading: {
            MiniRecord(playing: state.isPlaying).frame(width: 22, height: 22)
        } compactTrailing: {
            ProgressRing(state: state).frame(width: 20, height: 20)
        } minimal: {
            ZStack {
                ProgressRing(state: state)
                MiniRecord(playing: state.isPlaying).padding(4)
            }
            .frame(width: 22, height: 22)
        }
        .keylineTint(.white.opacity(0.4))
    }
}

/// A tiny record: black vinyl with grooves and a cream label (a pause bar across the label when paused).
private struct MiniRecord: View {
    let playing: Bool
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.08))
            ForEach([0.86, 0.72, 0.58], id: \.self) { r in
                Circle().stroke(.white.opacity(0.13), lineWidth: 0.6).scaleEffect(r)
            }
            Circle().fill(Color(red: 0.93, green: 0.84, blue: 0.68)).scaleEffect(0.38)
            if playing {
                Circle().fill(.black).scaleEffect(0.08)
            } else {
                Image(systemName: "pause.fill").font(.system(size: 6, weight: .black)).foregroundStyle(.black)
            }
        }
        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.5))
    }
}

/// The song's progress as a ring, animated by iOS from the song's start and end.
private struct ProgressRing: View {
    let state: LyricsActivityAttributes.ContentState
    var body: some View {
        if let start = state.songStart, let end = state.songEnd, end > start {
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.circular)
                .tint(.white)
        } else {
            Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// The song's progress as a thin bar under the lyrics.
struct ProgressLine: View {
    let state: LyricsActivityAttributes.ContentState
    var body: some View {
        if let start = state.songStart, let end = state.songEnd, end > start {
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(.white)
        }
    }
}

/// Time left in the song, counting down by itself; "Paused" while paused.
private struct TimeLeft: View {
    let state: LyricsActivityAttributes.ContentState
    var body: some View {
        if let start = state.songStart, let end = state.songEnd, end > start {
            Text(timerInterval: start...end, countsDown: true)
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .multilineTextAlignment(.trailing).frame(width: 52)
                .foregroundStyle(.white.opacity(0.7))
        } else {
            Text(state.isPlaying ? "Live" : "Paused").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
    }
}
