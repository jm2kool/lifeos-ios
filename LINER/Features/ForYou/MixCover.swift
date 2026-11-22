import SwiftUI

/// The cover of a Made for You mix: a wash of the lead album's colour with the mix's name on it and a few of its
/// covers fanned in the corner, so each mix looks like a playlist of its own. Scales with its frame.
struct MixCover: View {
    let mix: MadeForYouMix
    @State private var colour: Color = Palette.secondary

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [colour, colour.mix(with: .black, by: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                fan(w)
                VStack(alignment: .leading, spacing: w * 0.02) {
                    Text("\(AppBrand.name).").font(.system(size: w * 0.065, weight: .heavy)).kerning(w * 0.004).opacity(0.8)
                    Text(mix.title).font(.serif(w * 0.13, weight: .bold)).lineLimit(3).minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.3), radius: w * 0.02)
                }
                .foregroundStyle(.white)
                .padding(w * 0.07)
                .frame(maxWidth: w * 0.92, alignment: .leading)
            }
            .frame(width: w, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: mix.coverAlbumIDs.first) {
            guard let lead = mix.coverAlbumIDs.first else { return }
            let found = await CoverColor.dominant(.album(lead))
            withAnimation(.easeIn(duration: 0.25)) { colour = found.mix(with: .black, by: 0.15) }
        }
        .accessibilityHidden(true)
    }

    /// Up to three covers, overlapping and tilted, tucked into the bottom-right corner.
    private func fan(_ w: CGFloat) -> some View {
        let ids = Array(mix.coverAlbumIDs.prefix(3))
        let side = w * 0.42
        return ZStack(alignment: .bottomTrailing) {
            ForEach(Array(ids.enumerated().reversed()), id: \.offset) { i, id in
                ArtworkView(albumID: id, cornerRadius: side * 0.08)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.45), radius: w * 0.03, y: w * 0.015)
                    .rotationEffect(.degrees(Double(i) * -9 + 6))
                    .offset(x: CGFloat(i) * -side * 0.42, y: CGFloat(i) * side * 0.06)
            }
        }
        .padding(w * 0.07)
        .frame(width: w, height: w, alignment: .bottomTrailing)
    }
}

#Preview {
    let snap = PreviewData.snapshot
    MixCover(mix: MadeForYouMix(id: "heavy", title: "Heavy Rotation", subtitle: "", songIDs: [],
                                coverAlbumIDs: snap.albums.prefix(3).map(\.id)))
        .frame(width: 220).clipShape(RoundedRectangle(cornerRadius: 14)).padding()
        .environment(PreviewData.library).preferredColorScheme(.dark)
}
