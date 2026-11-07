import SwiftUI

/// The in-app Living Cover: the full-screen cover breathing (slow zoom and drift), or with the subject lifted
/// off the background in "Lift" style. Drawn live, so it needs no rendering and keeps going in Low Power Mode
/// unless you ask it not to.
struct LivingCoverView: View {
    let image: UIImage
    let look: ArtworkLook
    let key: String
    @State private var cutout: UIImage?
    @AppStorage("livingCoverStyle") private var style = LivingCoverRenderer.Style.drift.rawValue

    var body: some View {
        if MotionSettings.shouldAnimate {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angle = (t.truncatingRemainder(dividingBy: 8) / 8) * 2 * .pi
                let ease = 0.5 - 0.5 * cos(angle)
                GeometryReader { geo in
                    ZStack {
                        FocusedFillImage(image: image, focus: look.focus)
                            .scaleEffect(1.02 + 0.05 * ease)
                            .offset(x: geo.size.width * 0.014 * sin(angle), y: geo.size.height * 0.004 * sin(2 * angle))
                        if let cutout, style == LivingCoverRenderer.Style.lift.rawValue {
                            FocusedFillImage(image: cutout, focus: look.focus)
                                .scaleEffect(1.04 + 0.06 * ease)
                                .offset(x: -geo.size.width * 0.012 * sin(angle), y: -geo.size.height * 0.006 * ease)
                                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                        }
                    }
                }
            }
            .task(id: key) {
                if style == LivingCoverRenderer.Style.lift.rawValue { cutout = await SubjectMask.cutout(image, key: key) }
            }
        } else {
            FocusedFillImage(image: image, focus: look.focus)
        }
    }
}
