import SwiftUI

/// The full-screen lyrics' background: the cover's own colours as a slowly moving mesh, bright and saturated,
/// so the whole screen takes on the song's colour. It breathes a little faster while the music is playing.
struct LyricsBackdrop: View {
    let colours: AlbumColours
    var playing = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var nine: [Color] {
        let s = colours.swatches.isEmpty ? [colours.background] : colours.swatches
        let base = colours.background
        // A 3×3 grid: the background colour in the corners and the cover's swatches moving through the middle.
        return [base, s[0 % s.count], s[1 % s.count],
                s[2 % s.count], s[0 % s.count], base,
                s[1 % s.count], base, s[(s.count - 1)]]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * (playing ? 0.22 : 0.08)
            MeshGradient(width: 3, height: 3, points: points(t), colors: nine, smoothsColors: true)
                .saturation(1.25)
                .overlay(Color.black.opacity(colours.isDark ? 0.18 : 0.28))
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: colours)
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func wobble(_ phase: Double, _ amount: Double) -> Float { Float(sin(t + phase) * amount) }
        return [
            [0, 0], [0.5 + wobble(0.3, 0.2), 0], [1, 0],
            [0, 0.5 + wobble(1.7, 0.18)], [0.5 + wobble(2.1, 0.22), 0.5 + wobble(0.9, 0.2)], [1, 0.5 + wobble(3.3, 0.18)],
            [0, 1], [0.5 + wobble(4.2, 0.2), 1], [1, 1],
        ]
    }
}

#Preview {
    LyricsBackdrop(colours: AlbumColours(background: .indigo, primary: .white, secondary: .white, accent: .pink,
                                         swatches: [.pink, .purple, .orange], isDark: true))
}
