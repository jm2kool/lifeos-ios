import SwiftUI

/// Opening titles: an old film-leader countdown (3, 2, 1) with projector flicker and grain,
/// a flash of projector light, then the ticket mark punches in and the wordmark rises
/// before everything zooms through into the app. Tap to skip.
struct SplashView: View {
    var onFinish: () -> Void
    @State private var start = Date()
    @State private var finished = false

    private let countdownEnd = 1.15
    private let flashEnd = 1.4
    private let brandEnd = 2.25
    private let total = 2.75

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            ZStack {
                Color.black
                if t < countdownEnd { leader(t) }
                if t >= countdownEnd - 0.05 { brand(t) }
                // Projector flash between the leader and the titles.
                Color.white
                    .opacity(flash(t))
                    .blendMode(.plusLighter)
                Grain(seed: Int(t * 24)).opacity(t < flashEnd ? 0.16 : 0.07)
            }
            .scaleEffect(t > brandEnd ? 1 + (t - brandEnd) * 1.1 : 1)
            .opacity(t > brandEnd ? max(0, 1 - (t - brandEnd) / (total - brandEnd)) : 1)
            .onChange(of: t >= total) { _, done in if done { finish() } }
        }
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture { finish() }
        .accessibilityLabel("Matinee")
        .accessibilityAddTraits(.isImage)
        .onAppear { start = .now; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    private func flash(_ t: Double) -> Double {
        guard t > countdownEnd - 0.08 && t < flashEnd else { return 0 }
        let p = (t - (countdownEnd - 0.08)) / (flashEnd - countdownEnd + 0.08)
        return p < 0.25 ? p / 0.25 * 0.95 : 0.95 * (1 - (p - 0.25) / 0.75)
    }

    // MARK: Film leader

    @ViewBuilder private func leader(_ t: Double) -> some View {
        let step = countdownEnd / 3
        let n = 3 - min(2, Int(t / step))
        let local = (t.truncatingRemainder(dividingBy: step)) / step
        // Old projectors flicker: a small, irregular brightness wobble.
        let flicker = 0.82 + 0.18 * abs(sin(t * 47) * cos(t * 13))
        GeometryReader { g in
            let side = min(g.size.width, g.size.height) * 0.78
            ZStack {
                RadialGradient(colors: [Color(white: 0.42), Color(white: 0.16)], center: .center, startRadius: 10, endRadius: g.size.height * 0.7)
                // Crosshair
                Rectangle().fill(Color.black.opacity(0.55)).frame(width: 2, height: g.size.height)
                Rectangle().fill(Color.black.opacity(0.55)).frame(width: g.size.width, height: 2)
                Circle().stroke(Color.white.opacity(0.75), lineWidth: 3).frame(width: side, height: side)
                Circle().stroke(Color.white.opacity(0.5), lineWidth: 2).frame(width: side * 0.82, height: side * 0.82)
                // Sweeping arm, filling the dial like a clock wipe.
                SweepShape(progress: local)
                    .fill(Color.black.opacity(0.28))
                    .frame(width: side * 0.82, height: side * 0.82)
                Text("\(n)")
                    .font(.system(size: side * 0.5, weight: .black, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .scaleEffect(1 + (1 - local) * 0.06)
                // Scratches and dust
                Scratches(seed: Int(t * 18)).stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .frame(width: g.size.width, height: g.size.height)
            .brightness(flicker - 1)
            .overlay {
                // Vignette
                RadialGradient(colors: [.clear, .black.opacity(0.85)], center: .center, startRadius: side * 0.45, endRadius: g.size.height * 0.75)
            }
        }
    }

    // MARK: Titles

    @ViewBuilder private func brand(_ t: Double) -> some View {
        let local = max(0, t - flashEnd + 0.15)
        let markIn = min(1, local / 0.45)
        let spring = markIn >= 1 ? 1 : 1 - pow(1 - markIn, 3) * cos(markIn * .pi * 2.2)
        ZStack {
            // Warm projector glow behind the mark.
            Circle().fill(Theme.accent).frame(width: 340, height: 340).blur(radius: 110).opacity(0.55 * markIn).offset(x: -60, y: -80)
            Circle().fill(Theme.heart).frame(width: 300, height: 300).blur(radius: 110).opacity(0.45 * markIn).offset(x: 80, y: 90)
            VStack(spacing: 18) {
                MatineeMark()
                    .frame(width: 92, height: 92)
                    .scaleEffect(0.3 + 0.7 * spring)
                    .rotationEffect(.degrees((1 - spring) * -40))
                    .opacity(markIn)
                HStack(spacing: 0) {
                    ForEach(Array("Matinee".enumerated()), id: \.offset) { i, ch in
                        let p = min(1, max(0, (local - 0.18 - Double(i) * 0.045) / 0.3))
                        Text(String(ch))
                            .font(.system(size: 52, weight: .heavy, design: .serif))
                            .foregroundStyle(.white)
                            .offset(y: (1 - p) * 26)
                            .opacity(p)
                            .blur(radius: (1 - p) * 6)
                    }
                }
                Text("NOW SHOWING · YOUR FILMS")
                    .font(.caption.weight(.heavy)).tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(min(1, max(0, (local - 0.5) / 0.3)))
            }
        }
    }
}

/// A pie-slice that sweeps clockwise from 12 o'clock, like a film leader's clock wipe.
struct SweepShape: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: rect.width / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * progress), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// A few vertical film scratches that jump around each frame.
struct Scratches: Shape {
    var seed: Int
    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed &* 2_654_435_761))
        var p = Path()
        for _ in 0..<3 {
            let x = CGFloat(rng.next()) * rect.width
            let top = CGFloat(rng.next()) * rect.height * 0.5
            p.move(to: CGPoint(x: x, y: top))
            p.addLine(to: CGPoint(x: x + CGFloat(rng.next() - 0.5) * 6, y: top + rect.height * (0.2 + CGFloat(rng.next()) * 0.6)))
        }
        return p
    }
}

/// Film grain: speckles that change every frame.
struct Grain: View {
    var seed: Int
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed &* 40_503 &+ 7))
            for _ in 0..<900 {
                let x = CGFloat(rng.next()) * size.width, y = CGFloat(rng.next()) * size.height
                let s = CGFloat(0.6 + rng.next() * 1.4)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                         with: .color(rng.next() > 0.5 ? .white : .black))
            }
        }
        .allowsHitTesting(false)
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    /// 0..<1
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}
