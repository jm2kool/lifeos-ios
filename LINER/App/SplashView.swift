import SwiftUI

/// The opening: the record spins in and settles, “LINER.” types in letter by letter with the tagline beneath,
/// then the record zooms towards you and the app appears. A simple fade with Reduce Motion on.
struct SplashView: View {
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recordIn = false
    @State private var spin = 0.0
    @State private var letters = 0
    @State private var tagline = false
    @State private var leaving = false

    private var word: [Character] { Array(AppBrand.name) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 26) {
                Image("Logo").resizable().scaledToFit()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
                    .rotationEffect(.degrees(spin))
                    .scaleEffect(leaving ? 9 : (recordIn ? 1 : 0.45))
                    .opacity(recordIn ? (leaving ? 0 : 1) : 0)
                    .shadow(color: .white.opacity(recordIn ? 0.12 : 0), radius: 30)
                HStack(spacing: 0) {
                    ForEach(Array(word.enumerated()), id: \.offset) { i, ch in
                        Text(String(ch)).font(.serif(54))
                            .opacity(i < letters ? 1 : 0)
                            .offset(y: i < letters ? 0 : 14)
                            .blur(radius: i < letters ? 0 : 6)
                    }
                }
                .opacity(leaving ? 0 : 1)
                Text(AppBrand.tagline).linerLabel()
                    .opacity(tagline && !leaving ? 1 : 0)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.name) \(AppBrand.tagline)")
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            recordIn = true; letters = word.count; tagline = true
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.35)) { leaving = true }
            try? await Task.sleep(for: .seconds(0.35))
            done()
            return
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { recordIn = true }
        withAnimation(.easeOut(duration: 1.6)) { spin = 400 }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        try? await Task.sleep(for: .seconds(0.45))
        for i in 1...word.count {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { letters = i }
            try? await Task.sleep(for: .seconds(0.06))
        }
        withAnimation(.easeOut(duration: 0.5)) { tagline = true }
        try? await Task.sleep(for: .seconds(0.75))
        withAnimation(.easeIn(duration: 0.5)) { leaving = true }
        try? await Task.sleep(for: .seconds(0.45))
        done()
    }
}

#Preview { SplashView {}.preferredColorScheme(.dark) }
