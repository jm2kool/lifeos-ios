import SwiftUI

/// Scrubber with elapsed and remaining time.
struct Scrubber: View {
    @Environment(PlaybackCoordinator.self) private var player
    @State private var dragging: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = max(player.duration, 1)
            let time = dragging ?? min(player.currentTime, duration)
            VStack(spacing: 4) {
                Slider(value: Binding(get: { time }, set: { dragging = $0 }), in: 0...duration) { editing in
                    if !editing, let d = dragging { player.seek(to: d); dragging = nil }
                }
                .tint(.white)
                .accessibilityLabel("Position")
                .accessibilityValue("\(time.trackTime) of \(duration.trackTime)")
                HStack {
                    Text(time.trackTime)
                    Spacer()
                    Text("-" + max(0, duration - time).trackTime)
                }
                .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Palette.secondary)
            }
            .id(player.seekGeneration)
        }
    }
}

/// shuffle · ⏮ · ⏯ · ⏭ · repeat, on glass tinted by the artwork.
struct TransportControls: View {
    @Environment(PlaybackCoordinator.self) private var player
    let tint: Color

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                small(player.shuffle ? "shuffle.circle.fill" : "shuffle", "Shuffle", on: player.shuffle) { player.toggleShuffle() }
                small("backward.fill", "Previous") { player.previous() }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 76, height: 76)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(tint.opacity(0.25)).interactive(), in: .circle)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                small("forward.fill", "Next") { player.next() }
                small(player.repeatMode.symbol, "Repeat \(player.repeatMode.rawValue)", on: player.repeatMode != .off) { player.cycleRepeat() }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: player.isPlaying)
    }

    private func small(_ symbol: String, _ label: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color.white.opacity(0.85))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(.white.opacity(0.25)).interactive() : .regular.tint(tint.opacity(0.25)).interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}
