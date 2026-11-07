import SwiftUI

/// The record: grooves from a radial gradient and fine rings, a soft specular sheen, and the album art as the
/// centre label with a tiny "LINER. — curated by Jash" and the year (a nod to MD Vinyl).
struct RecordDisc: View {
    let record: VinylRecord
    let side: String

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(white: 0.13), Color(white: 0.05), Color(white: 0.09), Color(white: 0.04)],
                                             center: .center, startRadius: d * 0.18, endRadius: d * 0.5))
                ForEach(0..<26, id: \.self) { i in
                    Circle().stroke(Color.white.opacity(i % 3 == 0 ? 0.05 : 0.025), lineWidth: 0.6)
                        .padding(d * (0.04 + Double(i) * 0.012))
                }
                Circle().fill(AngularGradient(colors: [.clear, .white.opacity(0.09), .clear, .clear, .white.opacity(0.06), .clear],
                                              center: .center))
                    .blendMode(.screen)
                label(d * 0.36)
                Circle().fill(Color.black).frame(width: d * 0.025)
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func label(_ size: CGFloat) -> some View {
        ZStack {
            RecordCover(record: record).frame(width: size, height: size).clipShape(Circle())
            Circle().stroke(Color.black.opacity(0.5), lineWidth: 2).frame(width: size, height: size)
            VStack {
                Spacer()
                Text("\(AppBrand.name) — curated by Jash\(record.year.map { " · \($0)" } ?? "") · Side \(side)")
                    .font(.system(size: max(5, size * 0.035), weight: .semibold)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.85)).shadow(color: .black, radius: 1)
                    .padding(.bottom, size * 0.12)
            }
            .frame(width: size, height: size)
        }
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
