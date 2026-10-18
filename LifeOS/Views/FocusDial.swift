import SwiftUI

/// A clock face for focus sessions. Drag the glass knob around the ring to set 5–120 minutes (5-minute steps,
/// a light tick for each). While a session runs, pass `progress` and the ring fills as time passes instead.
struct FocusDial<Center: View>: View {
    @Binding var minutes: Int
    var progress: Double? = nil
    @ViewBuilder var center: () -> Center
    @State private var dragging = false
    private let maxMinutes = 120.0, step = 5, ring: CGFloat = 28
    private static var quarterLabels: [String] { ["120", "30", "60", "90"] }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let r = side / 2 - ring / 2 - 8
            let fraction = progress ?? Double(minutes) / maxMinutes
            ZStack {
                Circle().stroke(.quaternary, lineWidth: ring).frame(width: r * 2, height: r * 2)
                // clock ticks every 5 minutes, longer every 30
                ForEach(0..<24, id: \.self) { i in
                    Capsule()
                        .fill(i % 6 == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .frame(width: i % 6 == 0 ? 3 : 1.5, height: i % 6 == 0 ? 12 : 7)
                        .offset(y: -(r - ring / 2 - 16))
                        .rotationEffect(.degrees(Double(i) * 15))
                }
                ForEach(0..<4, id: \.self) { q in
                    Text(verbatim: Self.quarterLabels[q]).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .offset(polar(Double(q) * 90, r - ring / 2 - 34))
                }
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(.tint, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: r * 2, height: r * 2)
                    .animation(.smooth(duration: 0.18), value: fraction)
                if progress == nil {
                    Color.clear
                        .frame(width: ring + 20, height: ring + 20)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .scaleEffect(dragging ? 1.2 : 1)
                        .shadow(color: .black.opacity(dragging ? 0.25 : 0.12), radius: dragging ? 10 : 5, y: 2)
                        .offset(polar(fraction * 360, r))
                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: dragging)
                        .animation(.smooth(duration: 0.18), value: fraction)
                        .accessibilityHidden(true)
                }
                center()
            }
            .frame(width: side, height: side)
            .contentShape(.circle)
            .gesture(drag(side: side), isEnabled: progress == nil)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: minutes)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Focus length")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { dir in
            if progress != nil { return }
            minutes = min(120, max(5, minutes + (dir == .increment ? step : -step)))
        }
    }

    private func polar(_ degrees: Double, _ radius: CGFloat) -> CGSize {
        let a = degrees * .pi / 180
        return CGSize(width: sin(a) * radius, height: -cos(a) * radius)
    }

    private func drag(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                dragging = true
                let dx = v.location.x - side / 2, dy = v.location.y - side / 2
                guard dx * dx + dy * dy > 400 else { return }   // ignore touches right at the centre
                var deg = atan2(dx, -dy) * 180 / .pi
                if deg < 0 { deg += 360 }
                var m = Int((deg / 360 * maxMinutes / Double(step)).rounded()) * step
                // past the top: stay at the end you came from instead of jumping round the clock
                if minutes >= 100 && m <= 20 { m = 120 } else if minutes <= 20 && m >= 100 { m = 5 }
                minutes = min(120, max(5, m))
            }
            .onEnded { _ in dragging = false }
    }
}
