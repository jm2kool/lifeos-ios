import SwiftUI

/// The player's vinyl look, after MD Vinyl: a matte turntable deck with the song as a spinning record. The
/// tonearm follows the song from the outer groove in. Pick the arm up and move it to go anywhere in the song —
/// it seeks once when you let go, so nothing stutters — or set it down off the record to pause. Tap the record
/// to pause or play; drag the record round to scratch. The line being sung is printed round the grooves.
struct PlayerVinyl: View {
    let item: QueueItem
    var side = "A"
    /// The record starts held above the deck and drops onto a plain record waiting there ("Put it on").
    var dropIn = false
    /// How long it hovers before it drops.
    var dropDelay = 0.25
    @Environment(PlaybackCoordinator.self) private var player
    @Environment(LibraryService.self) private var library
    @State private var spin = SpinState()
    @State private var arm = ArmState()
    @State private var drag: Drag?
    @State private var cover: Data?
    @State private var ticks = 0
    @State private var drops = 0
    @State private var lyrics: Lyrics?
    @State private var dropped = false
    @State private var settle = false

    private var landed: Bool { !dropIn || dropped }

    private enum Drag: Equatable {
        case arm(Double)
        case scratch(start: Double, delta: Double)
        case ignored
    }

    /// The label shows the album, or the song itself when it's on its own.
    private var record: VinylRecord {
        let album = item.song.flatMap { library.snapshot.albumOf($0) }
        return VinylRecord(id: item.coverKey, title: album?.title ?? item.title, artist: item.artist,
                           year: item.song?.releaseDate.map { Calendar.current.component(.year, from: $0) },
                           albumID: item.song?.albumID, coverData: cover, tracks: [])
    }

    var body: some View {
        GeometryReader { geo in
            let deck = DeckGeometry(size: min(geo.size.width, geo.size.height))
            TimelineView(.animation) { ctx in
                deckFrame(deck, at: ctx.date)
            }
            .frame(width: deck.size, height: deck.size)
            .contentShape(Rectangle())
            .gesture(dragGesture(deck))
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                guard deck.isOnRecord(tap.location) else { return }
                player.togglePlayPause()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: ticks)
        .sensoryFeedback(.impact(weight: .medium), trigger: drops)
        .onChange(of: player.isPlaying) { _, playing in if playing { arm.parked = false } }
        .onChange(of: item.id) { arm.sample(0) }
        .task { await drop() }
        .task(id: item.id) {
            if case .local(let t) = item, let url = t.coverURL { cover = try? Data(contentsOf: url) } else { cover = nil }
            lyrics = nil
            let found = await LyricsStore.lyrics(for: item)
            lyrics = found?.isSynced == true ? found : nil
        }
        .accessibilityElement()
        .accessibilityLabel("Turntable: \(item.title)")
        .accessibilityHint("Double-tap to play or pause.")
        .accessibilityAction(named: player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
    }

    // MARK: Drawing

    private func deckFrame(_ d: DeckGeometry, at date: Date) -> some View {
        let duration = max(player.duration, 1)
        let time = arm.time(at: date, player: player)
        let scratch: Double = if case .scratch(_, let delta) = drag { delta } else { 0 }
        let angle = spin.angle(at: date, playing: player.isPlaying && !isScratching && landed) + scratch
        let armAngle: Double = {
            if case .arm(let a) = drag { arm.set(a); return a }
            return arm.angle(at: date, target: arm.parked ? d.rest : d.angle(progress: time / duration))
        }()
        let lifted = isHoldingArm || arm.parked || !player.isPlaying
        return ZStack {
            plinth(d)
            Canvas { ctx, _ in TonearmDrawing.platter(&ctx, deck: d, spin: angle) }
            if dropIn {
                RecordDisc(record: record, side: side, plain: true)
                    .frame(width: d.radius * 2, height: d.radius * 2)
                    .position(d.center)
            }
            RecordDisc(record: record, side: side)
                .frame(width: d.radius * 2, height: d.radius * 2)
                .rotationEffect(.radians(angle))
                .overlay(RecordSheen())
                .scaleEffect(landed ? (settle ? 0.975 : 1) : 1.2)
                .shadow(color: .black.opacity(0.75), radius: landed ? 4 : 26, y: landed ? 2 : 22)
                .animation(.easeIn(duration: 0.22), value: dropped)
                .animation(.spring(response: 0.18, dampingFraction: 0.45), value: settle)
                .position(d.center)
            if let lyrics {
                let i = lyrics.activeIndex(at: time + 0.25) ?? -1
                RecordLyrics(current: lyrics.lines.indices.contains(i) ? lyrics.lines[i].text : "",
                             next: lyrics.lines.indices.contains(i + 1) ? lyrics.lines[i + 1].text : "",
                             index: i, radius: d.radius)
                    .position(d.center)
                    .allowsHitTesting(false)
            }
            Canvas { ctx, _ in TonearmDrawing.draw(&ctx, deck: d, angle: armAngle, lifted: lifted) }
                .allowsHitTesting(false)
            readout(d, duration: duration, armAngle: armAngle, time: time)
        }
    }

    /// Held above the plain record for a moment, then dropped: a little squash, a bounce, the needle sound.
    private func drop() async {
        guard dropIn, !dropped else { return }
        try? await Task.sleep(for: .seconds(dropDelay))
        dropped = true
        try? await Task.sleep(for: .milliseconds(220))
        settle = true
        drops += 1
        VinylSounds.shared.needleDrop()
        try? await Task.sleep(for: .milliseconds(120))
        settle = false
    }

    private func plinth(_ d: DeckGeometry) -> some View {
        RoundedRectangle(cornerRadius: d.size * 0.06, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.1), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: d.size * 0.06, style: .continuous).stroke(.white.opacity(0.07)))
            .shadow(color: .black.opacity(0.7), radius: 30, y: 18)
    }

    /// Bottom right of the deck: the speed and a light that glows while it plays; while you hold the arm or
    /// scratch, where in the song you'd land.
    private func readout(_ d: DeckGeometry, duration: Double, armAngle: Double, time: Double) -> some View {
        let preview: Double? = switch drag {
        case .arm(let a): d.progress(a) < 0 ? nil : min(1, d.progress(a)) * duration
        case .scratch(let start, let delta): min(duration, max(0, start + Self.seconds(forTurn: delta)))
        default: nil
        }
        return VStack(alignment: .trailing, spacing: 6) {
            if let preview {
                Text(preview.trackTime).font(.system(size: d.size * 0.05, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .glassEffect(.regular, in: Capsule())
            } else if isHoldingArm {
                Text("Lift to pause").font(.system(size: d.size * 0.035, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4).glassEffect(.regular, in: Capsule())
            }
            HStack(spacing: 6) {
                Circle().fill(player.isPlaying ? Color.white : Color.white.opacity(0.15))
                    .frame(width: d.size * 0.018, height: d.size * 0.018)
                    .shadow(color: .white.opacity(player.isPlaying ? 0.8 : 0), radius: 4)
                Text("33⅓").font(.system(size: d.size * 0.032, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(d.size * 0.05)
        .frame(width: d.size, height: d.size, alignment: .bottomTrailing)
        .allowsHitTesting(false)
    }

    // MARK: Gestures

    private var isHoldingArm: Bool { if case .arm = drag { true } else { false } }
    private var isScratching: Bool { if case .scratch = drag { true } else { false } }

    /// A drag that starts on the arm moves the arm; one that starts on the record scratches.
    private func dragGesture(_ d: DeckGeometry) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if drag == nil {
                    let current = arm.angle ?? d.rest
                    if d.distanceToArm(v.startLocation, angle: current) < d.size * 0.07 {
                        drag = .arm(current)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } else if d.isOnRecord(v.startLocation) {
                        drag = .scratch(start: player.currentTime, delta: 0)
                    } else {
                        drag = .ignored
                    }
                }
                switch drag {
                case .arm(let old):
                    let a = d.armAngle(towards: v.location)
                    // A tick every twentieth of the song, so you can feel your way through it.
                    if Int(d.progress(a) * 20) != Int(d.progress(old) * 20) { ticks += 1 }
                    drag = .arm(a)
                case .scratch(let start, _):
                    let a0 = atan2(v.startLocation.y - d.center.y, v.startLocation.x - d.center.x)
                    let a1 = atan2(v.location.y - d.center.y, v.location.x - d.center.x)
                    var delta = Double(a1 - a0)
                    if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
                    drag = .scratch(start: start, delta: delta)
                default: break
                }
            }
            .onEnded { _ in
                switch drag {
                case .arm(let a): setDown(a, deck: d)
                case .scratch(let start, let delta):
                    let t = start + Self.seconds(forTurn: delta)
                    player.seek(to: t)
                    arm.sample(t)
                    spin.carry(delta)
                    UISelectionFeedbackGenerator().selectionChanged()
                default: break
                }
                drag = nil
            }
    }

    /// Letting go of the arm: off the record, it rests and the music pauses; on it, the song jumps there.
    private func setDown(_ a: Double, deck d: DeckGeometry) {
        arm.set(a)
        let p = d.progress(a)
        if p < -0.02 {
            arm.parked = true
            player.pause()
            VinylSounds.shared.stopCrackle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        let t = min(1, max(0, p)) * player.duration
        player.seek(to: t)
        arm.sample(t)
        arm.parked = false
        if !player.isPlaying { player.resume() }
        VinylSounds.shared.needleDrop()
        drops += 1
    }

    /// One turn is 1.8 s at 33⅓ rpm, sped up ×4 so a scratch covers real distance.
    private static func seconds(forTurn radians: Double) -> Double { radians / (2 * .pi) * 1.8 * 4 }
}

#Preview {
    PlayerVinyl(item: .library(PreviewData.snapshot.songs[0]))
        .padding().background(.black)
        .environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark)
}
