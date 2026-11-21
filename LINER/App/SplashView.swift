import SwiftUI

/// The opening. A record (your most played album as its label) comes up spinning, the tonearm swings over and
/// drops the needle with a tap you can feel, light runs out through the grooves, then the record shrinks into the
/// full stop of “LINER.” as the name rises in beside it. A simple fade with Reduce Motion on.
struct SplashView: View {
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var space
    @State private var stage = Stage.dark
    @State private var spin = 0.0
    @State private var letters = 0
    @State private var pulse = false
    @State private var label: UIImage? = SplashCover.load()

    enum Stage: Int, Comparable {
        case dark, record, arm, playing, word, leaving
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    /// The name without its full stop; the record becomes the stop.
    private var word: [Character] {
        let n = AppBrand.name
        return Array(n.hasSuffix(".") ? String(n.dropLast()) : n)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Where the record sits while it plays…
            Color.clear.frame(width: 230, height: 230)
                .matchedGeometryEffect(id: "disc", in: space, isSource: stage < .word)
            VStack(spacing: 18) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    ForEach(Array(word.enumerated()), id: \.offset) { i, ch in
                        Text(String(ch)).font(.serif(54))
                            .opacity(i < letters ? 1 : 0)
                            .offset(y: i < letters ? 0 : 18)
                            .blur(radius: i < letters ? 0 : 8)
                    }
                    // …and where it lands: the full stop.
                    Color.clear.frame(width: 15, height: 15)
                        .matchedGeometryEffect(id: "disc", in: space, isSource: stage >= .word)
                        .padding(.leading, 2)
                }
                Text(AppBrand.tagline).linerLabel()
                    .opacity(stage == .word ? 1 : 0)
            }
            .opacity(stage >= .word ? 1 : 0)
            .scaleEffect(stage == .leaving ? 1.08 : 1)

            SplashRecord(label: label, spin: spin, small: stage >= .word)
                .matchedGeometryEffect(id: "disc", in: space, isSource: false)
                .opacity(stage == .dark ? 0 : 1)
                .scaleEffect(stage == .dark ? 0.8 : 1)
                .background {
                    Circle().stroke(.white.opacity(pulse ? 0 : 0.35), lineWidth: 1.5)
                        .scaleEffect(pulse ? 1.9 : 1)
                        .opacity(stage == .playing ? 1 : 0)
                }

            Tonearm(down: stage >= .playing)
                .frame(width: 230, height: 230)
                .rotationEffect(.degrees(stage >= .arm ? 0 : -38), anchor: UnitPoint(x: 0.97, y: 0.06))
                .offset(x: 70, y: -40)
                .opacity(stage >= .arm && stage < .word ? 1 : 0)
        }
        .opacity(stage == .leaving ? 0 : 1)
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.name) \(AppBrand.tagline)")
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            stage = .word; letters = word.count
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.35)) { stage = .leaving }
            try? await Task.sleep(for: .seconds(0.35))
            done()
            return
        }
        // 33⅓ rpm is 200° a second; it keeps turning the whole time.
        withAnimation(.linear(duration: 3)) { spin = 600 }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { stage = .record }
        try? await Task.sleep(for: .seconds(0.3))
        withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.55)) { stage = .arm }
        try? await Task.sleep(for: .seconds(0.6))
        withAnimation(.easeIn(duration: 0.12)) { stage = .playing }
        try? await Task.sleep(for: .seconds(0.12))
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        withAnimation(.easeOut(duration: 0.9)) { pulse = true }
        try? await Task.sleep(for: .seconds(0.65))
        withAnimation(.timingCurve(0.6, 0, 0.2, 1, duration: 0.7)) { stage = .word }
        try? await Task.sleep(for: .seconds(0.3))
        for i in 1...max(1, word.count) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { letters = i }
            try? await Task.sleep(for: .seconds(0.05))
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        try? await Task.sleep(for: .seconds(0.7))
        withAnimation(.easeIn(duration: 0.4)) { stage = .leaving }
        try? await Task.sleep(for: .seconds(0.38))
        done()
    }
}

#Preview { SplashView {}.preferredColorScheme(.dark) }
