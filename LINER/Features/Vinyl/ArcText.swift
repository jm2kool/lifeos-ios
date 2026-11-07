import SwiftUI

/// Text set around a circle, the way a record label's rim is printed: along the top arc (reading left to right
/// over the top) or along the bottom arc (reading left to right underneath). Long lines shrink, then wrap
/// further round the circle, then end in "…".
struct ArcText: View {
    let text: String
    let radius: CGFloat
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var bottom = false
    var color: Color = .white

    var body: some View {
        Canvas { ctx, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let maxArc = radius * .pi * (bottom ? 0.9 : 1.35)
            var fontSize = size
            var glyphs = resolve(ctx, Array(text), fontSize)
            var total = glyphs.reduce(0) { $0 + $1.width }
            if total > maxArc {
                fontSize *= max(0.6, maxArc / total)
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
            var a = bottom ? .pi / 2 + sweep / 2 : -.pi / 2 - sweep / 2
            for g in glyphs {
                let half = Double(g.width / radius) / 2
                a += bottom ? -half : half
                var c = ctx
                c.translateBy(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)
                c.rotate(by: .radians(bottom ? a - .pi / 2 : a + .pi / 2))
                c.draw(g.text, at: .zero, anchor: .center)
                a += bottom ? -half : half
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(text)
    }

    private struct Glyph { let text: GraphicsContext.ResolvedText; let width: CGFloat }

    private func resolve(_ ctx: GraphicsContext, _ chars: [Character], _ size: CGFloat) -> [Glyph] {
        chars.map { ch in
            let t = ctx.resolve(Text(String(ch)).font(.system(size: size, weight: weight, design: .serif)).foregroundStyle(color))
            return Glyph(text: t, width: t.measure(in: CGSize(width: 1000, height: 1000)).width)
        }
    }
}

/// The line being sung, printed round the record's grooves (and the next one, fainter, underneath). It stays
/// still while the record turns beneath it, so it can be read.
struct RecordLyrics: View {
    let current: String
    let next: String
    let index: Int
    let radius: CGFloat

    var body: some View {
        ZStack {
            ArcText(text: current.isEmpty ? "♪" : current, radius: radius * 0.68, size: radius * 0.1)
                .shadow(color: .black.opacity(0.9), radius: 3)
            if !next.isEmpty {
                ArcText(text: next, radius: radius * 0.7, size: radius * 0.065, weight: .regular, bottom: true, color: .white.opacity(0.45))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .id(index)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)), removal: .opacity.combined(with: .scale(scale: 1.05))))
        .animation(.easeInOut(duration: 0.4), value: index)
    }
}

#Preview {
    ZStack {
        Circle().fill(Color(white: 0.06)).frame(width: 320, height: 320)
        RecordLyrics(current: "And I'm still standing in the doorway", next: "Waiting for you", index: 3, radius: 160)
    }
    .padding().background(.black).preferredColorScheme(.dark)
}
