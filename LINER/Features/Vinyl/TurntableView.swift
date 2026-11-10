import SwiftUI

/// The turntable (SPEC §6.16), opened by "Put it on" in the crate: the record lands on the deck and plays at
/// once, with the needle drop sound alongside. The deck is the same as the player's vinyl look: the arm follows
/// the song, pick it up to move through it or set it down off the record to pause; tap the record to pause or
/// play, drag it to scratch; swipe up on it (or the flip button) for the next side (your own sides when you've
/// arranged them). Tap the label in the middle for the setlist.
struct TurntableView: View {
    let record: VinylRecord
    /// The record drops onto a plain record waiting on the deck ("Put it on" from the crate or a sleeve).
    var dropIn = false
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var landed = false
    /// The side you last turned to (the label follows the song as it plays on into the next side).
    @State private var sideIndex = 0
    @State private var flipped = 0.0
    @State private var picking = false

    private var sides: [VinylSide] { record.sideList }
    /// The side of the song playing, or the one you turned to.
    private var side: String {
        if let mine, let i = record.tracks.firstIndex(where: { $0.id == mine.id }), let s = sides.first(where: { $0.range.contains(i) }) { return s.name }
        return sides.indices.contains(sideIndex) ? sides[sideIndex].name : "A"
    }
    private var nextSide: String { sides.isEmpty ? "A" : sides[(currentSideIndex + 1) % sides.count].name }
    private var currentSideIndex: Int { sides.firstIndex { $0.name == side } ?? 0 }

    private var mine: QueueItem? { player.current.flatMap { c in record.tracks.contains { $0.id == c.id } ? c : nil } }

    var body: some View {
        ZStack {
            Color(white: 0.03).ignoresSafeArea()
            VStack(spacing: 24) {
                header
                Spacer(minLength: 0)
                deck
                    .rotation3DEffect(.degrees(flipped), axis: (x: 1, y: 0, z: 0))
                    .scaleEffect(landed ? 1 : 0.86)
                    .opacity(landed ? 1 : 0)
                    // Outside the flip, so the setlist always reads the right way up.
                    .overlay { setlist }
                    .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
                        if !picking, v.translation.height < -120, abs(v.translation.width) < 60 { flip() }
                    })
                Spacer(minLength: 0)
                controls
            }
            .padding(20)
        }
        .task { startPlaying(sound: false) }
        .onDisappear { VinylSounds.shared.stopCrackle() }
        .statusBarHidden()
        .keepsScreenAwake()
    }

    @ViewBuilder private var deck: some View {
        if let item = mine {
            PlayerVinyl(item: item, side: side, dropIn: dropIn, dropDelay: 0.45, onLabelTap: { picking = true }).frame(maxWidth: 440)
        } else {
            RecordDisc(record: record, side: side).padding(40).frame(maxWidth: 440)
        }
    }

    @ViewBuilder private var setlist: some View {
        if picking {
            ZStack {
                Color.black.opacity(0.001).onTapGesture { picking = false }
                SetlistCard(record: record, currentID: player.current?.id, pick: { i in
                    picking = false
                    SetlistPlay.play(record, at: i, player: player)
                }, close: { picking = false })
                .frame(maxWidth: 400).padding(18)
            }
            .transition(.outOfTheLabel)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.serif(26)).lineLimit(1)
                Text("\(mine?.title ?? record.artist) · Side \(side)").linerLabel(size: 10).lineLimit(1)
            }
            Spacer()
            GlassCircleButton(systemImage: "xmark", label: "Close turntable", size: 42) { dismiss() }
        }
    }

    private var controls: some View {
        let playing = player.isPlaying && mine != nil
        return GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                GlassCircleButton(systemImage: "backward.fill", label: "Previous") { player.previous() }
                GlassCircleButton(systemImage: playing ? "pause.fill" : "play.fill", label: playing ? "Pause" : "Play", size: 64) {
                    if playing { player.pause(); VinylSounds.shared.stopCrackle() } else { startPlaying() }
                }
                GlassCircleButton(systemImage: "forward.fill", label: "Next") { player.next() }
                GlassCircleButton(systemImage: "arrow.up.and.down.text.horizontal", label: "Turn to Side \(nextSide)") { flip() }
            }
        }
    }

    // MARK: Actions

    /// Plays (or resumes) this record at once; the record lands and the pop plays alongside, never before it.
    private func startPlaying(sound: Bool = true) {
        let already = mine != nil
        if already {
            if !player.isPlaying { player.resume() }
        } else {
            player.play(record.tracks, startAt: sides.indices.contains(sideIndex) ? sides[sideIndex].range.lowerBound : 0, openPlayer: false)
        }
        // From the crate the music and the pop have already started; don't play the pop twice.
        // With the drop-in, the needle sound comes when the record lands instead.
        if (sound || !already) && !dropIn { VinylSounds.shared.needleDrop() }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { landed = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// The next side (back to Side A after the last).
    private func flip() {
        guard sides.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.6)) { flipped += 180 }
        sideIndex = (currentSideIndex + 1) % sides.count
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        player.play(record.tracks, startAt: sides[sideIndex].range.lowerBound, openPlayer: false)
        VinylSounds.shared.needleDrop()
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

#Preview {
    TurntableView(record: .album(PreviewData.snapshot.albums[0], PreviewData.snapshot))
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
