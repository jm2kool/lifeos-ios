import SwiftUI
import UIKit

/// Scripted scenes for the promo recordings CI makes on a simulator (`MATINEE_SCENE`, with `MATINEE_PREVIEW`).
/// `MATINEE_PACE` slows every scripted move and UIKit animation by that factor, so a slow simulator still
/// records plenty of frames; the clips are sped back up afterwards. Nothing here runs for normal use.
@MainActor
enum Demo {
    enum Scene: String { case film, colour, show, story, stats, profile, home }

    static let scene: Scene? = ProcessInfo.processInfo.environment["MATINEE_SCENE"].flatMap(Scene.init)
    static let pace: Double = ProcessInfo.processInfo.environment["MATINEE_PACE"].flatMap(Double.init).map { max(1, $0) } ?? 1

    static func playing(_ s: Scene) -> Bool { scene == s }

    /// A duration in scene time.
    static func t(_ seconds: Double) -> Double { seconds * pace }

    /// An animation slowed to scene time.
    static func slow(_ a: Animation) -> Animation { pace == 1 ? a : a.speed(1 / pace) }

    static func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(t(seconds))) }

    /// Slows UIKit and Core Animation (sheets, pushes, glass) to scene time.
    static func slowWindows() {
        guard pace > 1 else { return }
        for case let s as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in s.windows { w.layer.speed = Float(1 / pace) }
        }
    }

    static var screenHeight: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first?.bounds.height ?? 874
    }

    /// Scrolls step by step (an animated scrollTo ignores its duration and jumps), easing in and out over
    /// `seconds` of scene time, so a slow-motion recording catches every frame.
    static func glide(from a: CGFloat, to b: CGFloat, over seconds: Double, _ set: (CGFloat) -> Void) async {
        let steps = max(1, Int(t(seconds) * 60))
        for i in 1...steps {
            let p = Double(i) / Double(steps)
            let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
            set(a + (b - a) * CGFloat(e))
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Waits (in real time) until `ready` is true, or gives up after `limit` seconds.
    static func until(_ limit: Double = 20, _ ready: () -> Bool) async {
        let end = Date.now.addingTimeInterval(limit)
        while !ready() && Date.now < end { try? await Task.sleep(for: .milliseconds(100)) }
    }

    /// Tells a score dial on screen to sweep up to a score, as if dragged round.
    @Observable final class Director {
        static let shared = Director()
        var dialTarget: Double?
        /// Starts ticking off the next episodes of the show on screen.
        var showTicks = false
    }
}
