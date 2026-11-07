import SwiftUI

/// The record: fine grooves drawn in one pass, a couple of quiet track gaps, a soft light sheen that stays put
/// while the record turns under it, and the cover as the centre label with a tiny "LINER. — curated by Jash"
/// and the year (a nod to MD Vinyl).
struct RecordDisc: View {
    let record: VinylRecord
    let side: String

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = min(size.width, size.height) / 2
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(white: 0.055)))
                    // Grooves from the lead-in to the label, with two track gaps.
                    var radius = r * 0.97
                    var i = 0
                    while radius > r * 0.38 {
                        let gap = abs(radius - r * 0.74) < r * 0.006 || abs(radius - r * 0.55) < r * 0.006
                        let ring = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                        ctx.stroke(ring, with: .color(.white.opacity(gap ? 0.0 : (i % 2 == 0 ? 0.045 : 0.02))), lineWidth: max(0.5, r * 0.004))
                        radius -= r * 0.0085
                        i += 1
                    }
                    // The outer rim catches a little light.
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r + 1, y: c.y - r + 1, width: r * 2 - 2, height: r * 2 - 2)),
                               with: .color(.white.opacity(0.12)), lineWidth: 1)
                }
                label(d * 0.36)
                Circle().fill(Color.black).frame(width: d * 0.025)
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func label(_ size: CGFloat) -> some View {
        ZStack {
            RecordCover(record: record).frame(width: size, height: size).clipShape(Circle())
            Circle().stroke(Color.black.opacity(0.6), lineWidth: 2).frame(width: size, height: size)
            VStack {
                Spacer()
                Text("\(AppBrand.name) — curated by Jash\(record.year.map { " · \($0)" } ?? "") · Side \(side)")
                    .font(.system(size: max(5, size * 0.04), weight: .semibold)).tracking(0.5)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(.white.opacity(0.9)).shadow(color: .black, radius: 1)
                    .padding(.horizontal, size * 0.18).padding(.bottom, size * 0.1)
            }
            .frame(width: size, height: size)
        }
    }
}

/// A fixed sheen for a spinning record: lay it over the disc *outside* its rotation, so the light stays still
/// like it does on a real turntable.
struct RecordSheen: View {
    var body: some View {
        Circle()
            .fill(AngularGradient(colors: [.clear, .white.opacity(0.10), .clear, .clear, .white.opacity(0.07), .clear, .clear], center: .center,
                                  angle: .degrees(-30)))
            .mask {
                ZStack { Circle(); Circle().scale(0.37).blendMode(.destinationOut) }.compositingGroup()
            }
            .blendMode(.screen)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A minimal matte tonearm that swings onto the record.
struct Tonearm: View {
    let down: Bool
    let length: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Circle().fill(Color(white: 0.16)).frame(width: 46, height: 46)
                .overlay(Circle().stroke(.white.opacity(0.08)))
                .glassEffect(.regular, in: .circle)
            VStack(spacing: 0) {
                Capsule().fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.3)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 6, height: length)
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.25)).frame(width: 16, height: 30)
            }
            .padding(.top, 20)
        }
        .rotationEffect(.degrees(down ? 24 : 2), anchor: UnitPoint(x: 0.5, y: 0.05))
        .shadow(color: .black.opacity(0.6), radius: 8, x: 4, y: 6)
    }
}

#Preview {
    ZStack {
        RecordDisc(record: .album(PreviewData.snapshot.albums[0], PreviewData.snapshot), side: "A")
        RecordSheen()
    }
    .frame(width: 320).padding().background(.black).environment(PreviewData.library).preferredColorScheme(.dark)
}
