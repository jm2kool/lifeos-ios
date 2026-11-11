import SwiftUI

/// Recalibrating a song's lyrics by ear, with the music playing. Two tools: Earlier / Later moves every line at
/// once (for lyrics that are all a bit late or early), and the big button stamps the highlighted line the moment
/// you hear it start, then moves on to the next. You don't have to do every line: the ones in between are carried
/// along, so a tap near the start and one near the end also fixes lyrics that drift. Tap any line to jump there.
struct LyricsCalibrator: View {
    let item: QueueItem
    /// The lyrics as the file has them (corrections are worked out from these).
    let lyrics: Lyrics
    let onDone: () -> Void
    @Environment(PlaybackCoordinator.self) private var player
    @State private var timing = LyricTiming()
    @State private var target = 0
    @State private var undo: [LyricTiming] = []
    @State private var taps = 0

    /// People tap a touch after they hear the word.
    private static let reaction = 0.08

    var body: some View {
        VStack(spacing: 0) {
            Text("Tap the button the moment the highlighted line starts. A few lines are enough.")
                .font(.footnote).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 8)
            lines
            controls
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .onAppear {
            timing = LyricTimings.shared.timing(for: item.id)
            let now = lyrics.retimed(timing).activeIndex(at: player.currentTime) ?? -1
            target = nextLine(after: now) ?? 0
        }
    }

    // MARK: Pieces

    private var lines: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    let sung = lyrics.retimed(timing).activeIndex(at: player.currentTime)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(lyrics.lines) { line in row(line, sung: sung == line.id).id(line.id) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 16)
                }
            }
            .onChange(of: target) { _, now in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { proxy.scrollTo(now, anchor: UnitPoint(x: 0.5, y: 0.4)) }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(60))
                proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.4))
            }
        }
    }

    private func row(_ line: Lyrics.Line, sung: Bool) -> some View {
        let on = line.id == target, set = timing.isAnchored(line.time)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: set ? "checkmark.circle.fill" : (sung ? "waveform" : "circle"))
                .font(.system(size: 13)).foregroundStyle(.white.opacity(set || sung ? 0.9 : 0.25)).frame(width: 18)
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(.serif(on ? 24 : 19, weight: on ? .semibold : .regular))
                .foregroundStyle(.white.opacity(on ? 1 : (sung ? 0.75 : 0.45)))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(timing.map(line.time).trackTime).font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.label)
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(on ? 0.14 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { choose(line) }
        .animation(.easeOut(duration: 0.18), value: on)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint("Double-tap to play from just before this line and time it")
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                small("Earlier", "minus") { nudge(-0.25) }
                Text(shiftLabel).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .frame(maxWidth: .infinity).contentTransition(.numericText())
                small("Later", "plus") { nudge(0.25) }
            }
            Button(action: stamp) {
                Label("This line starts now", systemImage: "hand.tap.fill").font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.linerPrimary).buttonBorderShape(.capsule)
            .disabled(!lyrics.lines.indices.contains(target))
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") { if let last = undo.popLast() { apply(last, remember: false) } }
                    .disabled(undo.isEmpty)
                Spacer()
                Button("Start Over", systemImage: "arrow.counterclockwise") { apply(LyricTiming()) }.disabled(timing.isEmpty)
                Spacer()
                Button("Done", systemImage: "checkmark", action: onDone).fontWeight(.semibold)
            }
            .font(.system(size: 14)).buttonStyle(.plain).labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func small(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.white.opacity(0.12), in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Whole song \(title.lowercased())")
    }

    private var shiftLabel: String {
        if abs(timing.shift) < 0.01 { return "Whole song: as it is" }
        return "Whole song: \(abs(timing.shift).formatted(.number.precision(.fractionLength(2)))) s \(timing.shift > 0 ? "later" : "earlier")"
    }

    // MARK: Actions

    private func apply(_ new: LyricTiming, remember: Bool = true) {
        if remember { undo.append(timing) }
        timing = new
        LyricTimings.shared.set(new, for: item.id)
    }

    private func nudge(_ seconds: Double) {
        var t = timing
        t.shift = ((t.shift + seconds) * 100).rounded() / 100
        apply(t)
    }

    /// The highlighted line starts now; the next one is up.
    private func stamp() {
        guard lyrics.lines.indices.contains(target) else { return }
        var t = timing
        t.anchor(from: lyrics.lines[target].time, to: player.currentTime - Self.reaction)
        apply(t)
        taps += 1
        if let next = nextLine(after: target) { target = next }
    }

    /// Plays from a few seconds before the line, so you can hear it come in.
    private func choose(_ line: Lyrics.Line) {
        target = line.id
        player.seek(to: max(0, timing.map(line.time) - 3))
        if !player.isPlaying { player.resume() }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// The next line with words in it.
    private func nextLine(after index: Int) -> Int? {
        lyrics.lines.indices.first { $0 > index && !lyrics.lines[$0].text.isEmpty }
    }
}

#Preview {
    LyricsCalibrator(item: .library(PreviewData.snapshot.songs[0]),
                     lyrics: Lyrics(lines: LRCParser.parse("[00:05.00]First line\n[00:09.00]Second line\n[00:14.00]Third line"), plain: nil), onDone: {})
        .background(.black).environment(PreviewData.player).preferredColorScheme(.dark)
}
