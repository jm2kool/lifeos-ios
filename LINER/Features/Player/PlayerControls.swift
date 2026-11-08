import SwiftUI

/// The song's progress, Apple Music style: a thin bar you can grab anywhere (it thickens under your finger and
/// moves with it, rather than jumping to where you touched), with elapsed and remaining time. After a seek it
/// holds the new position until the player catches up, so it never snaps back.
struct Scrubber: View {
    @Environment(PlaybackCoordinator.self) private var player
    /// The position while your finger is down.
    @State private var dragging: Double?
    @State private var dragStart = 0.0
    /// Where you let go, held until the player reports being there (or a few seconds pass).
    @State private var pending: (time: Double, at: Date)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let duration = max(player.duration, 1)
            let time = shown(at: context.date, duration: duration)
            VStack(spacing: 6) {
                bar(progress: time / duration, duration: duration)
                HStack {
                    Text(time.trackTime)
                    Spacer()
                    Text("-" + max(0, duration - time).trackTime)
                }
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(dragging == nil ? Palette.secondary : .white)
            }
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue("\(time.trackTime) of \(duration.trackTime)")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 15.0 : -15.0
                commit(min(max(0, time + step), duration))
            }
        }
        .sensoryFeedback(.selection, trigger: dragging == nil)
    }

    private func shown(at date: Date, duration: Double) -> Double {
        if let dragging { return dragging }
        let reported = min(player.currentTime, duration)
        if let p = pending {
            if abs(reported - p.time) < 1.5 || date.timeIntervalSince(p.at) > 3 {
                Task { @MainActor in pending = nil }
            } else {
                return p.time
            }
        }
        return reported
    }

    private func bar(progress: Double, duration: Double) -> some View {
        GeometryReader { geo in
            let active = dragging != nil
            let height: CGFloat = active ? 12 : 6
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(active ? 1 : 0.85))
                    .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.smooth(duration: 0.2), value: active)
            .animation(active ? nil : .linear(duration: 0.25), value: progress)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if dragging == nil { dragStart = shown(at: .now, duration: duration) }
                        let moved = Double(v.translation.width / max(geo.size.width, 1)) * duration
                        dragging = min(max(0, dragStart + moved), duration)
                    }
                    .onEnded { v in
                        // A tap without a drag leaves the song where it is (a seek makes a stream re-buffer).
                        if let d = dragging, abs(v.translation.width) > 2 { commit(d) }
                        dragging = nil
                    }
            )
        }
        .frame(height: 28)
    }

    private func commit(_ t: Double) {
        pending = (t, .now)
        player.seek(to: t)
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
