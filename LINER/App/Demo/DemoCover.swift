import SwiftUI

/// A made-up album cover for demo mode: a mesh of the album's colours, a simple shape and its title, drawn once
/// and stored like real artwork.
struct DemoCover: View {
    enum Style { case sun, rings, mesh, type, bars }

    let title: String
    let artist: String
    let colours: [Color]
    let style: Style

    init(_ entry: DemoLibrary.Entry) {
        title = entry.title
        artist = entry.artist
        colours = entry.colours.map(Color.init(hex:))
        style = entry.style
    }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.62, 0.42], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: [
                    colours[0], colours[1], colours[2],
                    colours[1], colours[3], colours[0],
                    colours[2], colours[0], colours[1],
                ])
                shape(s)
                caption(s)
            }
            .frame(width: s, height: s)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder private func shape(_ s: CGFloat) -> some View {
        switch style {
        case .sun:
            ZStack {
                Circle().fill(LinearGradient(colors: [colours[3], colours[1]], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.5).offset(y: -s * 0.04)
                    .shadow(color: colours[3].opacity(0.8), radius: s * 0.08)
                VStack(spacing: s * 0.025) {
                    ForEach(0..<5, id: \.self) { i in
                        Rectangle().fill(colours[2].opacity(0.9)).frame(height: s * (0.012 + Double(i) * 0.006))
                    }
                }
                .offset(y: s * 0.17)
            }
        case .rings:
            ZStack {
                ForEach(0..<7, id: \.self) { i in
                    Circle().stroke(colours[3].opacity(0.85 - Double(i) * 0.1), lineWidth: s * 0.012)
                        .frame(width: s * (0.18 + Double(i) * 0.13))
                }
            }
            .offset(x: s * 0.12, y: -s * 0.08)
        case .mesh:
            Circle().fill(RadialGradient(colors: [colours[3].opacity(0.9), .clear], center: .center, startRadius: 0, endRadius: s * 0.4))
                .frame(width: s * 0.9).offset(x: -s * 0.18, y: -s * 0.2).blendMode(.screen)
        case .type:
            Text(title.split(separator: " ").first.map(String.init) ?? title)
                .font(.system(size: s * 0.3, weight: .black, design: .serif))
                .foregroundStyle(colours[3].opacity(0.92))
                .minimumScaleFactor(0.3).lineLimit(1)
                .rotationEffect(.degrees(-90))
                .frame(width: s, height: s, alignment: .center)
                .offset(x: s * 0.28)
        case .bars:
            HStack(spacing: s * 0.03) {
                ForEach(0..<6, id: \.self) { i in
                    Capsule().fill(colours[(i % 2) + 2].opacity(0.85))
                        .frame(width: s * 0.06, height: s * (0.25 + 0.08 * Double((i * 5) % 6)))
                }
            }
            .offset(y: s * 0.05)
        }
    }

    private func caption(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: s * 0.01) {
            Spacer()
            Text(title).font(.system(size: s * 0.075, weight: .semibold, design: .serif)).lineLimit(2)
            Text(artist.uppercased()).font(.system(size: s * 0.032, weight: .semibold)).tracking(s * 0.008).opacity(0.8)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: s * 0.02)
        .padding(s * 0.07)
        .frame(width: s, height: s, alignment: .bottomLeading)
    }
}

/// A made-up artist photo for demo mode: a lit head-and-shoulders silhouette (turned black and white on the way in).
struct DemoPortrait: View {
    let colours: [Color]

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                RadialGradient(colors: [colours[3], colours[2]], center: .topLeading, startRadius: 0, endRadius: s * 1.2)
                Ellipse().fill(LinearGradient(colors: [colours[1].mix(with: .black, by: 0.2), .black], startPoint: .leading, endPoint: .trailing))
                    .frame(width: s * 0.86, height: s * 0.5).offset(y: s * 0.42)
                Capsule().fill(LinearGradient(colors: [colours[0].mix(with: .white, by: 0.3), colours[2].mix(with: .black, by: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: s * 0.34, height: s * 0.44).offset(y: -s * 0.02)
            }
            .frame(width: s, height: s).clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

extension Color {
    /// A colour from a 0xRRGGBB number.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(), GridItem()]) {
        DemoCover(DemoLibrary.entries[DemoLibrary.entries.count - 1])
        DemoPortrait(colours: DemoLibrary.entries[DemoLibrary.entries.count - 1].colours.map(Color.init(hex:))).grayscale(1)
    }
    .padding().background(.black)
    .environment(PreviewData.library)
}
