import SwiftUI

/// A logo drawn in the colour you picked for it.
struct TintedLogo: View {
    let image: UIImage
    let tint: LogoTint
    /// The cover's main colour, for the "Cover" tint.
    var coverColor: Color = .white

    var body: some View {
        switch tint {
        case .original: Image(uiImage: image).resizable().scaledToFit()
        case .mono: Image(uiImage: image).resizable().scaledToFit().grayscale(1)
        case .white: template(.white)
        case .black: template(.black)
        case .cover: template(coverColor)
        case .custom(let hex): template(Color(hex: hex))
        }
    }

    private func template(_ color: Color) -> some View {
        Image(uiImage: image).renderingMode(.template).resizable().scaledToFit().foregroundStyle(color)
    }
}

/// Your logo laid over a header (album cover or artist photo) where you placed it.
struct PlacedLogo: View {
    let image: UIImage
    let look: SubjectLook
    let placement: LogoPlacement
    var coverColor: Color = .white

    var body: some View {
        GeometryReader { geo in
            TintedLogo(image: image, tint: look.tint, coverColor: coverColor)
                .frame(width: geo.size.width * placement.width)
                .shadow(color: .black.opacity(look.tint == .black ? 0 : 0.35), radius: 10)
                .rotationEffect(.degrees(placement.rotation))
                .position(x: geo.size.width * placement.x, y: geo.size.height * placement.y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An album's title as a logo when there is one (yours, then the one lifted from the cover), otherwise text in
/// the album's font. Used on the album page, pins, the sleeve and the navigation bar.
struct AlbumLogoTitle: View {
    let lookKey: String
    let albumID: UInt64?
    let title: String
    var maxWidth: CGFloat = 300
    var maxHeight: CGFloat = 110
    var font: Font = .itemTitle
    var fontSize: CGFloat = 30
    var coverColor: Color = .white
    var lineLimit = 3
    var alignment: Alignment = .leading
    /// Leaves your logo out when it's been placed on the cover (the cover already shows it).
    var skipPlaced = false
    @AppStorage(AlbumText.plainTitlesKey) private var plainTitles = ""
    @State private var lifted: UIImage?

    /// Customise Album → Title can turn the lettering lifted from the cover off for one album.
    private var plain: Bool { albumID.map { AlbumTracklist.savedOnly("album-\($0)", in: plainTitles) } ?? false }

    var body: some View {
        let store = LookStore.shared
        let look = store.look(lookKey)
        let mine = store.logo(lookKey)
        Group {
            if let mine, !(skipPlaced && look.placement != nil) {
                TintedLogo(image: mine, tint: look.tint, coverColor: coverColor)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(title)
            } else if mine != nil {
                EmptyView()
            } else if let lifted, !plain {
                Image(uiImage: lifted).resizable().scaledToFit()
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .accessibilityLabel(title)
                    .transition(.opacity)
            } else {
                Text(title).albumFace(fontSize, fallback: font).lineLimit(lineLimit)
            }
        }
        .task(id: "\(albumID ?? 0)-\(title)") {
            guard let albumID else { return }
            let found = await AlbumLogoStore.shared.logo(albumID: albumID, title: title)
            withAnimation(.easeIn(duration: 0.3)) { lifted = found }
        }
    }
}

/// The small logo (or title) in the navigation bar once the header has scrolled away.
struct NavBarLogo: View {
    let lookKey: String
    let albumID: UInt64?
    let title: String
    let visible: Double

    var body: some View {
        AlbumLogoTitle(lookKey: lookKey, albumID: albumID, title: title, maxWidth: 180, maxHeight: 30,
                       font: .serif(17, weight: .semibold), fontSize: 17, lineLimit: 1)
            .opacity(visible)
            .offset(y: (1 - visible) * 8)
            .allowsHitTesting(false)
    }
}

/// How far a page has scrolled past its header, as 0…1, for fading the navigation bar title in. While the
/// cover or photo is on screen the bar is fully clear (no blur over the artwork); the blur comes back only once
/// the header has scrolled away, so the title stays readable over the tracklist.
struct HeaderScrollProgress: ViewModifier {
    let headerHeight: CGFloat
    @Binding var progress: Double

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
                let start = headerHeight - 140
                let p = Double(min(1, max(0, (y - start) / 60)))
                if abs(p - progress) > 0.01 || (p == 0) != (progress == 0) || (p == 1) != (progress == 1) { progress = p }
            }
            .scrollEdgeEffectHidden(progress < 1, for: .top)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }
}

extension View {
    func headerScrollProgress(headerHeight: CGFloat, progress: Binding<Double>) -> some View {
        modifier(HeaderScrollProgress(headerHeight: headerHeight, progress: progress))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        AlbumLogoTitle(lookKey: "preview", albumID: nil, title: "Melodrama")
        TintedLogo(image: UIImage(systemName: "music.note")!, tint: .custom("#FF4466")).frame(width: 80)
    }
    .padding().background(.black).preferredColorScheme(.dark)
}
