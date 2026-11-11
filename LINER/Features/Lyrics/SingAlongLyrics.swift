import SwiftUI

/// The synced lyrics, sung along like Apple Music: each word of the line being sung fills with light as it's
/// sung and lifts a little, long notes glow, other lines step back (softly blurred), and instrumental gaps show
/// three dots that fill until the singing starts again. Scroll to look around; it comes back to the line being
/// sung a moment after you let go. Tap a line to jump there; hold it to save or share.
struct SingAlongLyrics: View {
    let lyrics: Lyrics
    var onSave: (Lyrics.Line) -> Void = { _ in }
    var onMoment: (Lyrics.Line) -> Void = { _ in }
    var onShare: (Lyrics.Line) -> Void = { _ in }
    @Environment(PlaybackCoordinator.self) private var player
    @State private var clock = Playhead()
    /// You're scrolling through the lyrics yourself: no auto-scroll and no blur until a moment after you stop.
    @State private var browsing = false
    @State private var scrolling = false

    /// Lines light up a touch early, as they do in Apple Music, so you see the words as you hear them.
    static let lead = 0.2
    private static let anchor = UnitPoint(x: 0.5, y: 0.32)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let now = clock.time(at: ctx.date, player: player) + Self.lead
            let active = lyrics.activeIndex(at: now)
            let intro = lyrics.introGap && active == nil
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 200)
                        if lyrics.introGap {
                            GapDots(start: 0, end: lyrics.lines[0].time, clock: clock, lead: Self.lead)
                                .padding(.vertical, intro ? 16 : 0)
                                .frame(height: intro ? nil : 0, alignment: .top).clipped()
                                .opacity(intro ? 1 : 0)
                                .id(-1)
                        }
                        ForEach(lyrics.lines) { line in row(line, active: active).id(line.id) }
                        Color.clear.frame(height: 420)
                    }
                    .padding(.horizontal, 24)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: active)
                }
                .onScrollPhaseChange { _, phase in
                    scrolling = phase != .idle
                    if phase == .interacting { browsing = true }
                }
                .task(id: scrolling) {
                    guard !scrolling, browsing else { return }
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled else { return }
                    browsing = false
                }
                .onChange(of: browsing) { _, now in if !now { scroll(proxy, to: active ?? (intro ? -1 : 0)) } }
                .onChange(of: active) { _, now in
                    guard !browsing else { return }
                    scroll(proxy, to: now ?? (intro ? -1 : 0))
                }
                // Opening the lyrics lands straight on the line being sung, not the top of the song.
                .task(id: lyrics) {
                    let target = active ?? (intro ? -1 : 0)
                    proxy.scrollTo(target, anchor: Self.anchor)
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo(target, anchor: Self.anchor)
                }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: Int) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.88)) { proxy.scrollTo(id, anchor: Self.anchor) }
    }

    @ViewBuilder private func row(_ line: Lyrics.Line, active: Int?) -> some View {
        let distance = active.map { line.id - $0 } ?? line.id + 1
        if line.text.isEmpty {
            // An instrumental break: dots while it's playing (when it's long enough to notice), nothing otherwise.
            let shows = distance == 0 && line.end - line.time >= 3
            GapDots(start: line.time, end: line.end, clock: clock, lead: Self.lead)
                .padding(.vertical, shows ? 16 : 0)
                .frame(height: shows ? nil : 0, alignment: .top).clipped()
                .opacity(shows ? 1 : 0)
        } else {
            Group {
                if distance == 0 {
                    TimelineView(.animation) { ctx in
                        SungLine(words: line.words, time: clock.time(at: ctx.date, player: player) + Self.lead)
                    }
                } else {
                    SungLine(words: line.words, time: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13)
            .opacity(distance == 0 ? 1 : (distance < 0 ? 0.42 : 0.6))
            .blur(radius: browsing || distance == 0 ? 0 : min(2.6, 0.7 + Double(abs(distance)) * 0.45))
            .scaleEffect(distance == 0 ? 1 : 0.97, anchor: .leading)
            .contentShape(Rectangle())
            .onTapGesture { player.seek(to: line.time); browsing = false }
            .contextMenu {
                Button("Save line", systemImage: "bookmark") { onSave(line) }
                Button("Save as favourite moment", systemImage: "star") { onMoment(line) }
                Button("Share lyrics", systemImage: "square.and.arrow.up") { onShare(line) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.text)
            .accessibilityAddTraits(distance == 0 ? .isSelected : [])
            .accessibilityHint("Double-tap to jump here")
        }
    }
}

/// One line, word by word. `time` nil: the line isn't being sung, so every word rests at the dim colour.
struct SungLine: View {
    let words: [Lyrics.Word]
    let time: Double?

    var body: some View {
        WordFlow(spacing: 8, lineSpacing: 2) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                SungWord(text: w.text, fill: time.map { w.fill(at: $0) } ?? -1, held: w.end - w.start)
            }
        }
    }
}

/// A word filling with light from left to right as it's sung. Held notes (over a second) glow while they last.
struct SungWord: View {
    let text: String
    /// 0…1 while its line is being sung; -1 when it isn't.
    let fill: Double
    var held: Double = 0
    var font: Font = .singAlong

    var body: some View {
        let lit = max(0, fill)
        let edge = lit * 1.2 - 0.1
        let glow = held > 1.1 && lit > 0 && lit < 1 ? 1.0 : 0
        Text(text).font(font).lineLimit(1).fixedSize()
            .foregroundStyle(.white.opacity(fill < 0 ? 1 : 0.4))
            .overlay {
                if lit > 0 {
                    Text(text).font(font).lineLimit(1).fixedSize().foregroundStyle(.white)
                        .mask {
                            LinearGradient(stops: [.init(color: .white, location: min(1, max(0, edge - 0.1))),
                                                   .init(color: .clear, location: min(1, max(0, edge + 0.1)))],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                        .shadow(color: .white.opacity(0.55 * glow), radius: 10)
                }
            }
            .offset(y: fill < 0 ? 0 : -2.5 * lit)
            .animation(.easeOut(duration: 0.3), value: glow)
    }
}

/// Three dots for an instrumental gap: they fill one after another until the next line, breathing gently.
struct GapDots: View {
    let start: Double
    let end: Double
    let clock: Playhead
    let lead: Double
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = clock.time(at: ctx.date, player: player) + lead
            let p = min(1, max(0, (t - start) / max(0.1, end - start - 0.4)))
            let breath = 1 + 0.08 * sin(ctx.date.timeIntervalSinceReferenceDate * 2.6)
            HStack(spacing: 10) {
                ForEach(0..<3) { i in
                    let f = min(1, max(0, p * 3 - Double(i)))
                    Circle().fill(.white.opacity(0.3 + 0.7 * f)).frame(width: 12, height: 12).scaleEffect(0.85 + 0.25 * f)
                }
            }
            // The dots shrink away just before the singing starts again.
            .scaleEffect(breath * (p >= 1 ? 0.6 : 1), anchor: .leading)
            .opacity(p >= 1 ? 0 : 1)
            .animation(.easeOut(duration: 0.3), value: p >= 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Instrumental")
    }
}

/// Words laid out like a paragraph: left to right, wrapping onto the next line when they don't fit.
struct WordFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(subviews, width: bounds.width)
        for (view, point) in zip(subviews, placed.points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: width.isFinite ? width : widest, height: y + rowHeight))
    }
}

/// Where the song is, smoothly between frames: it asks the player twice a second (and at once after a seek or a
/// new song) and counts on from there. A plain class (not observed): the timelines read it every frame.
@MainActor
final class Playhead {
    private var sampleTime = 0.0
    private var sampleDate = Date.distantPast
    private var generation = -1
    private var itemID: String?

    func time(at date: Date, player: PlaybackCoordinator) -> Double {
        if date.timeIntervalSince(sampleDate) > 0.5 || player.seekGeneration != generation || player.current?.id != itemID {
            sampleTime = player.currentTime
            sampleDate = date
            generation = player.seekGeneration
            itemID = player.current?.id
        }
        return sampleTime + (player.isPlaying ? max(0, date.timeIntervalSince(sampleDate)) : 0)
    }
}

extension Font {
    /// The sing-along lyrics' lettering.
    static let singAlong = Font.serif(31, weight: .semibold)
}

extension Lyrics {
    /// A wait of a few seconds before the first line, shown as dots.
    var introGap: Bool { (lines.first?.time ?? 0) >= 3 }
}

#Preview {
    let lyrics = Lyrics(lines: LRCParser.parse("[00:04.00]And I'm still standing in the doorway\n[00:08.50]Waiting for you\n[00:12.00]\n[00:18.00]Under the lights of the city"))
    SingAlongLyrics(lyrics: lyrics)
        .background(.black)
        .environment(PreviewData.library).environment(PreviewData.player).preferredColorScheme(.dark)
}
