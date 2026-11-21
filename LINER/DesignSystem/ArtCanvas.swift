import CoreMotion
import SwiftUI

extension EnvironmentValues {
    /// Whether a view sits on a page painted with artwork colours; cards there turn see-through so the colour shows.
    @Entry var onArt = false
}

extension View {
    /// Paints the page behind this view with artwork colours, Apple Card style (plain black until they arrive).
    func artCanvas(_ colours: [ArtPalette.RGB]) -> some View {
        background { ArtCanvas(colours: colours) }
            .environment(\.onArt, !colours.isEmpty)
    }
}

/// A whole page painted with artwork colours: the moving mesh, dimmed towards the bottom so white text reads.
struct ArtCanvas: View {
    let colours: [ArtPalette.RGB]

    var body: some View {
        ZStack {
            Palette.background
            if !colours.isEmpty {
                ArtMesh(colours: colours)
                    .overlay(LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.22), .black.opacity(0.5)],
                                            startPoint: .top, endPoint: .bottom))
                    .id(colours)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: colours)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A moving mesh of artwork colours in the spirit of the Apple Card in Wallet: a 4×4 mesh whose points drift,
/// whose colours slowly pass from one to the next, and which leans as you tilt the phone. Holds still with
/// Reduce Motion, and in Low Power Mode when Settings asks for that.
struct ArtMesh: View {
    let colours: [ArtPalette.RGB]
    @State private var tilt = TiltReader()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var still: Bool { reduceMotion || !MotionSettings.shouldAnimate }

    var body: some View {
        if colours.isEmpty {
            Color.clear
        } else {
            let still = still, colours = colours, tilt = tilt
            TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { tl in
                let t = still ? 120 : Float(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
                MeshGradient(width: 4, height: 4, points: Self.points(t, tilt: still ? .zero : tilt.read()),
                             colors: Self.colors(colours, t), smoothsColors: true)
            }
            .onAppear { if !still { tilt.start() } }
            .onDisappear { tilt.stop() }
            .accessibilityHidden(true)
        }
    }

    static func points(_ t: Float, tilt: SIMD2<Float>) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for y in 0..<4 {
            for x in 0..<4 {
                var p = SIMD2<Float>(Float(x) / 3, Float(y) / 3)
                let seed = Float(x * 7 + y * 13)
                // Inner points wander in loops; edge points slide along their edge.
                if x != 0 && x != 3 { p.x += 0.14 * sin(t * (0.42 + seed * 0.011) + seed) + tilt.x * 0.09 }
                if y != 0 && y != 3 { p.y += 0.14 * cos(t * (0.37 + seed * 0.013) + seed * 0.7) + tilt.y * 0.09 }
                out.append(p)
            }
        }
        return out
    }

    /// Each point fades from one colour to the next on its own clock.
    static func colors(_ pal: [ArtPalette.RGB], _ t: Float) -> [Color] {
        let n = pal.count
        return (0..<16).map { i in
            let phase = t * 0.09 + Float(i) * 0.61
            let k = Int(phase.rounded(.down))
            let f = phase - Float(k)
            let smooth = f * f * (3 - 2 * f)
            let a = pal[((k + i * 3) % n + n) % n], b = pal[((k + 1 + i * 3) % n + n) % n]
            let c = a + (b - a) * smooth
            return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
        }
    }
}

/// Gentle device tilt for the mesh, smoothed. Read once a frame, so there are no motion callbacks to hop
/// between queues. Needs no permission. Only the main thread touches it.
final class TiltReader: @unchecked Sendable {
    private let manager = CMMotionManager()
    private var tilt = SIMD2<Float>(0, 0)

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates()
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    func read() -> SIMD2<Float> {
        guard let g = manager.deviceMotion?.gravity else { return tilt }
        let target = SIMD2<Float>(Float(max(-1, min(1, g.x))), Float(max(-1, min(1, g.y + 0.6))))
        tilt += (target - tilt) * 0.12
        return tilt
    }
}

#Preview {
    ArtCanvas(colours: [SIMD3(0.8, 0.2, 0.4), SIMD3(0.2, 0.3, 0.7), SIMD3(0.9, 0.6, 0.2), SIMD3(0.1, 0.05, 0.1)])
}
