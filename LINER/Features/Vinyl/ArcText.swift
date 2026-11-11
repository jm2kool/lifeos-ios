import SwiftUI

/// Text set around a circle, the way a record label's rim is printed: along the top arc (reading left to right
/// over the top) or along the bottom arc (reading left to right underneath). Long lines shrink, then end in
/// "…". Each arc keeps to its own half of the circle, so a line on top never runs into one underneath.
struct ArcText: View {
    let text: String
    let radius: CGFloat
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var bottom = false
    var color: Color = .white
    /// How many characters have been sung (the sing-along fill); nil prints the whole line at full strength.
    var lit: Double? = nil
    /// The arc's longest sweep, as a share of a half circle.
    var sweep: Double = 0.92
    /// Where the line is on its way across its half, -1 (just arrived) … 1 (about to leave). It only travels as far
    /// as its own length leaves room for, so no letter ever crosses into the other half.
    var drift: Double = 0

    var body: some View {
        Canvas { ctx, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let maxArc = radius * .pi * CGFloat(sweep)
            var fontSize = size
            var glyphs = resolve(ctx, Array(text), fontSize)
            var total = glyphs.reduce(0) { $0 + $1.width }
            if total > maxArc {
                fontSize *= max(0.55, maxArc / total)
                glyphs = resolve(ctx, Array(text), fontSize)
                total = glyphs.reduce(0) { $0 + $1.width }
            }
            if total > maxArc {
                var chars = Array(text)
                while total > maxArc, chars.count > 1 {
                    chars.removeLast()
                    glyphs = resolve(ctx, chars + ["…"], fontSize)
                    total = glyphs.reduce(0) { $0 + $1.width }
                }
            }
            let sweep = Double(total / radius)
            let room = max(0, min(Self.maxTravel, (.pi * 0.97 - sweep) / 2))
            let travel = min(1, max(-1, drift)) * room
            var a = (bottom ? .pi / 2 + sweep / 2 : -.pi / 2 - sweep / 2) + (bottom ? -travel : travel)
            for (k, g) in glyphs.enumerated() {
                let half = Double(g.width / radius) / 2
                a += bottom ? -half : half
                var c = ctx
                if let lit { c.opacity = 0.38 + 0.62 * min(1, max(0, lit - Double(k))) }
                c.translateBy(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)
                c.rotate(by: .radians(bottom ? a - .pi / 2 : a + .pi / 2))
                c.draw(g.text, at: .zero, anchor: .center)
                a += bottom ? -half : half
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(text)
    }

    /// The furthest a short line travels either side of the top (radians): about a third of the half circle.
    static let maxTravel = 0.62

    private struct Glyph { let text: GraphicsContext.ResolvedText; let width: CGFloat }

    private func resolve(_ ctx: GraphicsContext, _ chars: [Character], _ size: CGFloat) -> [Glyph] {
        chars.map { ch in
            let t = ctx.resolve(Text(String(ch)).font(.system(size: size, weight: weight, design: .serif)).foregroundStyle(color))
            return Glyph(text: t, width: t.measure(in: CGSize(width: 1000, height: 1000)).width)
        }
    }
}

/// The line being sung, printed round the record's grooves (and the next one, fainter, underneath). The words
/// light up as they're sung, and the line travels round the way the record turns — but only ever across the top
/// half: it comes in on the left, is over the top halfway through, and leaves on the right as the next one
/// arrives, so a short, quick line goes round faster than a long, slow one. A long line goes onto two rings on
/// the top half; the next line keeps to the bottom half, so they never overlap.
struct RecordLyrics: View {
    let current: String
    let next: String
    let index: Int
    let radius: CGFloat
    /// How far through the line the song is, 0…1; it carries the line across the top half.
    var progress: Double = 0.5
    /// Characters of `current` sung so far; nil when there are no timings to follow.
    var lit: Double? = nil

    var body: some View {
        let parts = Self.split(current.isEmpty ? "♪" : current)
        let outer = parts.0, inner = parts.1
        let drift = min(1, max(0, progress)) * 2 - 1
        ZStack {
            Group {
                ArcText(text: outer, radius: radius * (inner == nil ? 0.7 : 0.78), size: radius * (inner == nil ? 0.1 : 0.088), lit: lit, drift: drift)
                if let inner {
                    ArcText(text: inner, radius: radius * 0.62, size: radius * 0.088, lit: lit.map { $0 - Double(outer.count + 1) }, drift: drift)
                }
            }
            .shadow(color: .black.opacity(0.9), radius: 3)
            .id("now-\(index)")
            .transition(.lyricDrift)
            if !next.isEmpty {
                ArcText(text: next, radius: radius * 0.76, size: radius * 0.062, weight: .regular, bottom: true,
                        color: .white.opacity(0.45), sweep: 0.78)
                    .id("next-\(index)")
                    .transition(.lyricDrift)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .animation(.smooth(duration: 0.6), value: index)
    }

    /// Long lines are split between two rings at the space nearest the middle.
    static func split(_ text: String) -> (String, String?) {
        guard text.count > 30 else { return (text, nil) }
        let middle = text.count / 2
        let spaces = text.indices.filter { text[$0] == " " }
        guard let cut = spaces.min(by: { abs(text.distance(from: text.startIndex, to: $0) - middle) < abs(text.distance(from: text.startIndex, to: $1) - middle) })
        else { return (text, nil) }
        return (String(text[..<cut]), String(text[text.index(after: cut)...]))
    }
}

/// A line arriving from a little behind on the record and leaving a little ahead, blurring as it goes. The old
/// line is gone before the new one shows, so they never sit on top of each other.
private struct LyricDrift: ViewModifier {
    let turn: Double
    let fade: Double
    let blur: CGFloat
    let scale: CGFloat
    func body(content: Content) -> some View {
        content.rotationEffect(.radians(turn)).scaleEffect(scale).blur(radius: blur).opacity(fade)
    }
}

extension AnyTransition {
    static var lyricDrift: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(active: LyricDrift(turn: -0.14, fade: 0, blur: 5, scale: 0.97),
                                              identity: LyricDrift(turn: 0, fade: 1, blur: 0, scale: 1))
                .animation(.smooth(duration: 0.55).delay(0.2)),
            removal: AnyTransition.modifier(active: LyricDrift(turn: 0.14, fade: 0, blur: 5, scale: 1.02),
                                            identity: LyricDrift(turn: 0, fade: 1, blur: 0, scale: 1))
                .animation(.easeIn(duration: 0.2)))
    }
}

#Preview {
    ZStack {
        Circle().fill(Color(white: 0.06)).frame(width: 320, height: 320)
        RecordLyrics(current: "And I'm still standing in the doorway of the house", next: "Waiting for you", index: 3, radius: 160, progress: 0.3, lit: 14)
    }
    .padding().background(.black).preferredColorScheme(.dark)
}
