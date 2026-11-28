import SwiftUI

/// Lyric video: one huge line at a time over the cover, each word landing as it's sung (the sung word glows in
/// the cover's accent), the next line waiting small underneath.
struct LyricVideoStage: View {
    let lyrics: Lyrics
    let colours: AlbumColours
    let clock: @MainActor () -> Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let t = clock()
            let i = lyrics.activeIndex(at: t + 0.1)
            let next = lyrics.lines[((i ?? -1) + 1)...].first { !$0.isBackground }
            let echo = lyrics.lines.first { $0.isBackground && t >= $0.time - 0.1 && t < $0.end + 0.4 }
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                if let i {
                    let line = lyrics.lines[i]
                    Group {
                        if line.words.isEmpty {
                            Text("♪").font(.serif(64, weight: .bold))
                        } else {
                            KaraokeLine(line: line, phase: .active,
                                        style: KaraokeStyle(font: .serif(size(line), weight: .bold), size: size(line),
                                                            lit: colours.accent.mix(with: .white, by: 0.35), dim: .white, fill: false),
                                        clock: clock)
                        }
                    }
                    .id(line.id)
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
                }
                if let echo {
                    Text(echo.text).font(.serif(22, weight: .semibold).italic()).foregroundStyle(.white.opacity(0.75))
                        .transition(.opacity)
                }
                Text(next?.text ?? " ").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26).padding(.bottom, 150)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: i)
            .animation(.easeInOut(duration: 0.3), value: echo?.id)
        }
    }

    /// Short lines are set bigger.
    private func size(_ line: Lyrics.Line) -> CGFloat {
        switch line.text.count { case ..<14: 58; case ..<26: 48; case ..<40: 40; default: 34 }
    }
}

/// Behind the cover: the line in giant condensed capitals behind the person on the cover (Vision lifts them
/// out, as for Living Covers), filling with colour as it's sung, like a magazine cover.
struct BehindCoverStage: View {
    let lyrics: Lyrics
    let colours: AlbumColours
    let cutout: UIImage?
    let focus: CGPoint
    let clock: @MainActor () -> Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let t = clock()
            let i = lyrics.activeIndex(at: t + 0.1)
            ZStack(alignment: .top) {
                if let i {
                    let line = shouted(lyrics.lines[i])
                    let s = size(line)
                    let lit = colours.isDark ? colours.primary.mix(with: .white, by: 0.3) : colours.primary
                    KaraokeLine(line: line, phase: .active,
                                style: KaraokeStyle(font: .system(size: s, weight: .black).width(.compressed), size: s,
                                                    lit: lit, dim: lit.opacity(0.22), alignment: .center, glow: false),
                                clock: clock)
                        .padding(.horizontal, 10)
                        .padding(.top, 130)
                        .id(line.id)
                        .transition(.asymmetric(insertion: .scale(scale: 1.15).combined(with: .opacity), removal: .opacity))
                }
                if let cutout {
                    FocusedFillImage(image: cutout, focus: focus).ignoresSafeArea().allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: i)
        }
    }

    private func shouted(_ line: Lyrics.Line) -> Lyrics.Line {
        var l = line
        l.words = line.words.map { var w = $0; w.text = w.text.uppercased(); return w }
        return l
    }

    private func size(_ line: Lyrics.Line) -> CGFloat {
        switch line.text.count { case ..<12: 120; case ..<22: 96; case ..<36: 76; default: 60 }
    }
}

#Preview {
    let lyrics = WordTiming.apply(Lyrics(lines: [Lyrics.Line(id: 0, time: 0, text: "Neon saints in the passing light"),
                                                 Lyrics.Line(id: 1, time: 4, text: "Hold this note and don't let go")]), duration: 8)
    let start = Date.now
    return ZStack {
        Color.purple.ignoresSafeArea()
        LyricVideoStage(lyrics: lyrics, colours: .black) { Date.now.timeIntervalSince(start).truncatingRemainder(dividingBy: 8) }
    }
}
