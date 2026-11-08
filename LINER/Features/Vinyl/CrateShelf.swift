import SwiftUI

/// The Library's albums as a crate (MD Vinyl-style): big sleeves that lean back as you flip past them, the
/// record sliding out of the one in front, with a tick under your finger for every record. Tap a sleeve and it
/// zooms open into the album page.
struct CrateShelf: View {
    let albums: [Album]
    let namespace: Namespace.ID
    @State private var ticks = 0
    @State private var taps = 0

    var body: some View {
        LazyVStack(spacing: 22) {
            ForEach(albums) { album in
                NavigationLink(value: album) { CrateSleeve(album: album) }
                    .buttonStyle(SleevePressStyle())
                    .modifier(ZoomSource(id: album.id, namespace: namespace))
                    .simultaneousGesture(TapGesture().onEnded { taps += 1 })
                    .contextMenu { AlbumActionsMenu(album: album) }
                    .scrollTransition(.interactive, axis: .vertical) { content, phase in
                        content
                            // Records above the middle lean back into the crate; ones below tip towards you.
                            .rotation3DEffect(.degrees(phase.value * -28), axis: (x: 1, y: 0, z: 0),
                                              anchor: phase.value < 0 ? .bottom : .top, perspective: 0.55)
                            .scaleEffect(1 - abs(phase.value) * 0.1)
                            .opacity(1 - abs(phase.value) * 0.4)
                    }
                    .onScrollVisibilityChange(threshold: 0.95) { if $0 { ticks += 1 } }
                    .accessibilityLabel("\(album.title), \(album.artist)")
                    .accessibilityHint("Double-tap to open the album")
            }
        }
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: ticks)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}

/// One record in the crate: the sleeve, the vinyl peeking out (further when it's the one in front), the name.
private struct CrateSleeve: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .leading) {
                RecordDisc(record: .album(album, .init()), side: "A")
                    .padding(6)
                    // Slides out of the sleeve as it reaches the middle of the screen and back in as it leaves.
                    .visualEffect { content, proxy in
                        content.offset(x: 8 + 78 * CrateSleeve.peek(proxy))
                    }
                ArtworkView(albumID: album.id, cornerRadius: 6)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.7), radius: 16, x: 6, y: 10)
            }
            .aspectRatio(1, contentMode: .fit)
            .containerRelativeFrame(.horizontal) { w, _ in w * 0.72 }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(album.title).font(.serif(20)).lineLimit(1)
                Text([album.artist.uppercased(), album.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .linerLabel(size: 10).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    /// How far the record is out (0 tucked in, 1 fully out): out at the middle of the screen, in towards the edges.
    nonisolated static func peek(_ proxy: GeometryProxy) -> CGFloat {
        guard let view = proxy.bounds(of: .scrollView(axis: .vertical)), view.height > 0 else { return 0 }
        let mid = proxy.frame(in: .scrollView(axis: .vertical)).midY
        let away = abs(mid - view.midY) / (view.height / 2)
        let t = max(0, min(1, 1 - (away - 0.12) * 1.9))
        return t * t * (3 - 2 * t)
    }
}

/// The sleeve dips a little under your finger.
private struct SleevePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    @Previewable @Namespace var ns
    NavigationStack { ScrollView { CrateShelf(albums: PreviewData.snapshot.albums, namespace: ns) } }
        .environment(PreviewData.library).environment(PreviewData.player).environment(PreviewData.passports)
        .modelContainer(Store.shared.container).preferredColorScheme(.dark)
}
