import SwiftUI

/// Lays words out in rows like running text, wrapping where it must. Lines can sit on the left, centre or right.
struct WordFlow: Layout {
    var alignment: TextAlignment = .leading
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 2

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let gap = i > 0 && subviews[i - 1][WordGap.self] ? spacing : 0
            if x + gap + size.width > width, !rows[rows.count - 1].isEmpty {
                rows.append([]); x = 0
            } else {
                x += gap
            }
            rows[rows.count - 1].append((i, size))
            x += size.width
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.reduce(0) { $0 + ($1.map(\.1.height).max() ?? 0) } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map { row in row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let rowHeight = row.map(\.1.height).max() ?? 0
            var widths: CGFloat = 0
            for (k, item) in row.enumerated() {
                widths += item.1.width + (k > 0 && subviews[row[k - 1].0][WordGap.self] ? spacing : 0)
            }
            var x = switch alignment {
            case .leading: bounds.minX
            case .center: bounds.minX + (bounds.width - widths) / 2
            case .trailing: bounds.maxX - widths
            }
            for (k, item) in row.enumerated() {
                if k > 0 && subviews[row[k - 1].0][WordGap.self] { x += spacing }
                subviews[item.0].place(at: CGPoint(x: x, y: y + rowHeight - item.1.height), proposal: ProposedViewSize(item.1))
                x += item.1.width
            }
            y += rowHeight + lineSpacing
        }
    }
}

/// Whether a space follows this word in a `WordFlow`.
struct WordGap: LayoutValueKey { static let defaultValue = true }

/// How a lyric line is drawn.
struct KaraokeStyle {
    var font: Font
    var size: CGFloat
    var lit: Color = .white
    var dim: Color = .white.opacity(0.32)
    var alignment: TextAlignment = .leading
    /// Words light up softly as they are sung (true), or appear one by one (false, the lyric-video style).
    var fill = true
    var glow = true
    /// Capitals or small letters, from the album's font.
    var textCase: Text.Case? = nil
}

/// One lyric line whose words fill with light as they're sung. Only the line being sung redraws every frame.
struct KaraokeLine: View {
    enum Phase { case past, active, future }
    let line: Lyrics.Line
    let phase: Phase
    let style: KaraokeStyle
    let clock: @MainActor () -> Double

    var body: some View {
        if phase == .active {
            TimelineView(.animation) { _ in words(at: clock()) }
        } else {
            words(at: phase == .past ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude)
        }
    }

    private func words(at time: Double) -> some View {
        WordFlow(alignment: style.alignment, spacing: style.size * 0.27, lineSpacing: style.size * 0.08) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                let p = word.end > word.start ? min(1, max(0, (time - word.start) / (word.end - word.start))) : (time >= word.start ? 1 : 0)
                KaraokeWord(text: word.text, progress: p, singing: time >= word.start && time < word.end,
                            held: word.end - word.start > 0.9, background: word.isBackground, style: style)
                    .layoutValue(key: WordGap.self, value: word.space)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text)
    }
}

/// A single word: dim underneath, lit on top through a soft-edged mask that sweeps left to right.
struct KaraokeWord: View {
    let text: String
    let progress: Double
    let singing: Bool
    let held: Bool
    let background: Bool
    let style: KaraokeStyle

    var body: some View {
        let shown = style.textCase == .uppercase ? text.uppercased() : (style.textCase == .lowercase ? text.lowercased() : text)
        let base = Text(shown).font(background ? .system(size: style.size * 0.72, weight: .semibold).italic() : style.font)
        if style.fill {
            base.foregroundStyle(style.dim)
                .overlay {
                    base.foregroundStyle(style.lit).mask(alignment: .leading) { sweep }
                }
                .shadow(color: style.lit.opacity(style.glow && singing ? 0.55 : 0), radius: held ? 14 : 9)
                .scaleEffect(held && singing ? 1 + 0.06 * min(1, progress * 1.4) : 1, anchor: .bottom)
                .offset(y: singing ? -2 : 0)
                .animation(.easeOut(duration: 0.22), value: singing)
        } else {
            base.foregroundStyle(singing ? style.lit : style.dim)
                .opacity(progress > 0 ? 1 : 0)
                .blur(radius: progress > 0 ? 0 : 8)
                .offset(y: progress > 0 ? 0 : 14)
                .scaleEffect(singing ? 1.04 : 1, anchor: .bottomLeading)
                .shadow(color: style.lit.opacity(singing && style.glow ? 0.6 : 0), radius: 14)
                .animation(.spring(response: 0.38, dampingFraction: 0.7), value: progress > 0)
                .animation(.easeOut(duration: 0.2), value: singing)
        }
    }

    @ViewBuilder private var sweep: some View {
        if progress >= 1 {
            Rectangle()
        } else if progress <= 0 {
            Color.clear
        } else {
            // A soft edge 18% of the word wide, moving from just before the word to just past it.
            let edge = 0.18
            let head = progress * (1 + edge)
            LinearGradient(stops: [.init(color: .black, location: max(0, head - edge)), .init(color: .clear, location: min(1, head))],
                           startPoint: .leading, endPoint: .trailing)
        }
    }
}

#Preview {
    let line = WordTiming.apply(Lyrics(lines: [Lyrics.Line(id: 0, time: 0, text: "Hold this note and don't let go (go)")]), duration: 6).lines[0]
    let start = Date.now
    return VStack(alignment: .leading, spacing: 30) {
        KaraokeLine(line: line, phase: .active, style: KaraokeStyle(font: .system(size: 34, weight: .bold), size: 34)) {
            Date.now.timeIntervalSince(start).truncatingRemainder(dividingBy: 6)
        }
        KaraokeLine(line: line, phase: .active, style: KaraokeStyle(font: .serif(40, weight: .bold), size: 40, fill: false)) {
            Date.now.timeIntervalSince(start).truncatingRemainder(dividingBy: 6)
        }
    }
    .padding().frame(maxHeight: .infinity).background(LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom))
}
