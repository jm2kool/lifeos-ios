import SwiftUI

/// A still cover brought to life with a Studio motion effect: a slow Zoom, a gentle Drift, a sweep of Light,
/// Focus (the background softens and the subject stays sharp), floating Particles, or Film grain. Still when
/// Low Power Mode asks for it or Reduce Motion is on.
struct StudioMotionView: View {
    let image: UIImage
    let motion: StudioMotion
    var focus = CGPoint(x: 0.5, y: 0.4)
    var key = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cutout: UIImage?

    var body: some View {
        if motion == .off || reduceMotion || !MotionSettings.shouldAnimate {
            FocusedFillImage(image: image, focus: focus)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ZStack { layers(t, geo.size) }
                }
            }
            .clipped()
            .task(id: "\(key)-\(motion.rawValue)") {
                if motion == .focus { cutout = await SubjectMask.cutout(image, key: key.isEmpty ? UUID().uuidString : key) }
            }
        }
    }

    @ViewBuilder private func layers(_ t: Double, _ size: CGSize) -> some View {
        let wave = 0.5 - 0.5 * cos(t / 12 * 2 * .pi)
        switch motion {
        case .zoom:
            FocusedFillImage(image: image, focus: focus).scaleEffect(1 + 0.16 * wave)
        case .drift:
            FocusedFillImage(image: image, focus: focus).scaleEffect(1.1)
                .offset(x: size.width * 0.035 * sin(t / 7), y: size.height * 0.025 * cos(t / 9))
        case .light:
            FocusedFillImage(image: image, focus: focus)
            let sweep = (t / 6).truncatingRemainder(dividingBy: 1)
            LinearGradient(colors: [.clear, .white.opacity(0.32), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: size.width * 0.5)
                .rotationEffect(.degrees(20))
                .offset(x: size.width * (sweep * 2.4 - 1.2))
                .blendMode(.plusLighter)
        case .focus:
            FocusedFillImage(image: image, focus: focus).blur(radius: 6 + 4 * wave).scaleEffect(1.06)
            if let cutout {
                FocusedFillImage(image: cutout, focus: focus).scaleEffect(1.02 + 0.04 * wave)
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            }
        case .particles:
            FocusedFillImage(image: image, focus: focus).scaleEffect(1.04)
            Canvas { ctx, s in
                for k in 0..<36 {
                    let seed = Double(k) * 12.9898
                    let speed = 0.03 + (sin(seed) * 0.5 + 0.5) * 0.05
                    let x = (sin(seed * 3.1) * 0.5 + 0.5) * s.width + sin(t * 0.6 + seed) * 12
                    let y = s.height * (1 - ((t * speed + sin(seed * 7.3) * 0.5 + 0.5).truncatingRemainder(dividingBy: 1)))
                    let r = 1.2 + (sin(seed * 5.7) * 0.5 + 0.5) * 2.4
                    let fade = min(1, (s.height - y) / (s.height * 0.2)) * min(1, y / (s.height * 0.3))
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.75 * max(0, fade))))
                }
            }
            .blendMode(.plusLighter)
        case .film:
            FocusedFillImage(image: image, focus: focus)
                .saturation(0.85).contrast(1.06)
                .brightness(0.015 * sin(t * 23))
            Canvas { ctx, s in
                let frame = Int(t * 24)
                for k in 0..<500 {
                    let n = Double((k &* 7919 &+ frame &* 104_729) % 10_007) / 10_007
                    let m = Double((k &* 6_271 &+ frame &* 3_571) % 9_973) / 9_973
                    ctx.fill(Path(CGRect(x: n * s.width, y: m * s.height, width: 1.4, height: 1.4)),
                             with: .color(.white.opacity(k % 2 == 0 ? 0.16 : 0.08)))
                }
            }
            .blendMode(.overlay)
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: size.width * 0.3, endRadius: size.width * 0.85)
        case .off:
            FocusedFillImage(image: image, focus: focus)
        }
    }
}

#Preview {
    let img = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { ctx in
        UIColor.systemPink.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        UIColor.systemPurple.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 100, y: 80, width: 200, height: 240))
    }
    return LazyVGrid(columns: [GridItem(), GridItem()]) {
        ForEach(StudioMotion.allCases) { m in
            StudioMotionView(image: img, motion: m).aspectRatio(1, contentMode: .fit).overlay(alignment: .bottomLeading) { Text(m.label).padding(6) }
        }
    }
    .padding()
}
