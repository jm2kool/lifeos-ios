import SwiftUI

/// The turntable (SPEC §6.16): the record slides out of its sleeve onto a matte black platter, the tonearm swings in,
/// the needle drops (pop + crackle) and playback starts. Spins at 33⅓ rpm; drag the record to scratch-scrub; lift the
/// arm to pause; swipe up on the record to flip to Side B.
struct TurntableView: View {
    let record: VinylRecord
    /// When set, an ⓘ button shows the album page instead.
    var onInfo: (() -> Void)?
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var spin = SpinState()
    @State private var armDown = false
    @State private var landed = false
    @State private var side = "A"
    @State private var flipped = 0.0
    @State private var scrubbing: Double?
    @State private var lastSeek = Date.distantPast

    private var isThisPlaying: Bool { player.isPlaying && record.tracks.contains { $0.id == player.current?.id } }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width - 40, 380)
            ZStack {
                Color(white: 0.03).ignoresSafeArea()
                VStack(spacing: 28) {
                    header
                    ZStack(alignment: .topTrailing) {
                        platter(size: size)
                        Tonearm(down: armDown, length: size * 0.72)
                            .frame(width: size * 0.4, height: size * 0.95)
                            .offset(x: size * 0.18, y: -size * 0.08)
                            .gesture(DragGesture(minimumDistance: 4).onEnded { v in setArm(down: v.translation.width < 0) })
                            .onTapGesture { setArm(down: !armDown) }
                            .accessibilityLabel(armDown ? "Lift the tonearm" : "Drop the needle")
                            .accessibilityAddTraits(.isButton)
                    }
                    .frame(width: size, height: size)
                    controls
                }
                .padding(20)
            }
        }
        .task { await dropTheNeedle() }
        .onDisappear { VinylSounds.shared.stopCrackle() }
        .statusBarHidden()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.serif(26)).lineLimit(1)
                Text("\(record.artist) · Side \(side)").linerLabel(size: 10)
            }
            Spacer()
            if let onInfo {
                GlassCircleButton(systemImage: "info", label: "Album page", size: 42, action: onInfo).padding(.trailing, 6)
            }
            GlassCircleButton(systemImage: onInfo == nil ? "xmark" : "chevron.down", label: "Close turntable", size: 42) { dismiss() }
        }
    }

    private func platter(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.09)).shadow(color: .black, radius: 30, y: 16)
            TimelineView(.animation) { ctx in
                let angle = spin.angle(at: ctx.date, playing: isThisPlaying && scrubbing == nil) + (scrubbing ?? 0)
                RecordDisc(record: record, side: side)
                    .rotationEffect(.radians(angle))
                    .overlay(RecordSheen())
                    .padding(size * 0.03)
            }
            .rotation3DEffect(.degrees(flipped), axis: (x: 1, y: 0, z: 0))
            .offset(y: landed ? 0 : -size * 1.3)
            .scaleEffect(landed ? 1 : 0.7)
            .gesture(scratch(size: size))
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
                if v.translation.height < -120 && abs(v.translation.width) < 60 { flip() }
            })
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                GlassCircleButton(systemImage: "backward.fill", label: "Previous") { player.previous() }
                GlassCircleButton(systemImage: isThisPlaying ? "pause.fill" : "play.fill", label: isThisPlaying ? "Pause" : "Play", size: 64) {
                    setArm(down: !isThisPlaying)
                }
                GlassCircleButton(systemImage: "forward.fill", label: "Next") { player.next() }
                GlassCircleButton(systemImage: "arrow.up.and.down.text.horizontal", label: "Flip to Side \(side == "A" ? "B" : "A")") { flip() }
            }
        }
    }

    // MARK: Actions

    /// The song starts the moment the turntable opens; the record landing, the arm and the pop happen alongside it.
    private func dropTheNeedle() async {
        startPlaying()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { landed = true }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.2)) { armDown = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func setArm(down: Bool) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { armDown = down }
        UIImpactFeedbackGenerator(style: down ? .medium : .light).impactOccurred()
        if down { startPlaying() } else {
            VinylSounds.shared.stopCrackle()
            player.pause()
        }
    }

    /// Plays (or resumes) this record at once, with the needle drop sound on top.
    private func startPlaying() {
        if record.tracks.contains(where: { $0.id == player.current?.id }) {
            if !player.isPlaying { player.resume() }
        } else {
            player.play(record.tracks, startAt: side == "A" ? 0 : record.tracks.count / 2)
        }
        VinylSounds.shared.needleDrop()
    }

    /// Side B: the second half of the tracklist.
    private func flip() {
        guard record.tracks.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.6)) { flipped += 180 }
        side = side == "A" ? "B" : "A"
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        player.play(record.tracks, startAt: side == "A" ? 0 : record.tracks.count / 2)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { armDown = true }
    }

    /// Angular drag → seek. One turn at 33⅓ rpm is 1.8 s of music; a light rubber band past the ends.
    private func scratch(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let c = CGPoint(x: size / 2, y: size / 2)
                let a0 = atan2(v.startLocation.y - c.y, v.startLocation.x - c.x)
                let a1 = atan2(v.location.y - c.y, v.location.x - c.x)
                var d = Double(a1 - a0)
                if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
                scrubbing = d
                if Date.now.timeIntervalSince(lastSeek) > 0.2 {
                    lastSeek = .now
                    let t = player.currentTime + d / (2 * .pi) * 1.8 * 4
                    let banded = t < 0 ? t * 0.3 : (t > player.duration ? player.duration + (t - player.duration) * 0.3 : t)
                    player.seek(to: banded)
                }
            }
            .onEnded { _ in
                spin.carry(scrubbing ?? 0)
                scrubbing = nil
                UISelectionFeedbackGenerator().selectionChanged()
            }
    }
}

/// Keeps the record's angle continuous while it speeds up to 33⅓ rpm and eases to a stop.
/// A plain class (not observed): the TimelineView reads it every frame.
@MainActor
final class SpinState {
    static let full = 2 * Double.pi * (100.0 / 3.0) / 60.0   // rad/s at 33⅓ rpm ≈ 0.556 rev/s
    private var angle = 0.0
    private var speed = 0.0
    private var last: Date?

    func angle(at date: Date, playing: Bool) -> Double {
        let dt = min(0.1, last.map { date.timeIntervalSince($0) } ?? 0)
        last = date
        let target = playing ? Self.full : 0
        speed += (target - speed) * min(1, dt * (playing ? 2.5 : 1.4))
        angle += speed * dt
        return angle
    }

    func carry(_ delta: Double) { angle += delta }
}
