import SwiftUI

/// Which mood of colour sits behind a screen. Today follows the time of day.
enum AmbientPalette: Hashable { case today, inbox, study, library, search }

extension EnvironmentValues {
    @Entry var ambientPalette: AmbientPalette = .today
}

/// Soft pools of colour behind the content: two near the top, a faint one lower down.
/// They drift very slowly, stay well under the text, and hold still with Reduce Motion on.
struct AmbientBackground: View {
    var palette: AmbientPalette? = nil
    @Environment(\.ambientPalette) private var envPalette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: reduceMotion)) { ctx in
                let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
                let c = colors(palette ?? envPalette, at: ctx.date)
                let k: Double = scheme == .dark ? 0.40 : 0.26
                ZStack {
                    Color(.systemGroupedBackground)
                    glow(c.0, x: 0.12 + 0.07 * sin(t / 17), y: 0.04 + 0.03 * cos(t / 21), radius: w * 1.05, strength: k)
                    glow(c.1, x: 0.95 + 0.05 * cos(t / 19), y: 0.13 + 0.04 * sin(t / 23), radius: w * 0.9, strength: k * 0.85)
                    glow(c.2, x: 0.45 + 0.12 * sin(t / 29), y: 0.70 + 0.05 * cos(t / 31), radius: w * 0.95, strength: k * 0.4)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, x: Double, y: Double, radius: CGFloat, strength: Double) -> some View {
        Rectangle().fill(RadialGradient(
            stops: [.init(color: color.opacity(strength), location: 0),
                    .init(color: color.opacity(strength * 0.45), location: 0.4),
                    .init(color: color.opacity(0), location: 1)],
            center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: radius))
    }

    private func colors(_ p: AmbientPalette, at date: Date) -> (Color, Color, Color) {
        switch p {
        case .inbox: return (.blue, .cyan, .indigo)
        case .study: return (.green, .teal, .mint)
        case .library: return (.purple, .pink, .indigo)
        case .search: return (.indigo, .teal, .pink)
        case .today:
            let h = Calendar.current.component(.hour, from: date)
            switch h {
            case 5..<11: return (.orange, Color(red: 1, green: 0.78, blue: 0.36), .pink)      // morning: warm
            case 11..<17: return (.cyan, .blue, .mint)                                         // daytime: clear
            case 17..<21: return (.purple, .pink, .orange)                                     // evening: dusk
            default: return (.indigo, .blue, .purple)                                          // night: deep
            }
        }
    }
}
