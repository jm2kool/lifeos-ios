import SwiftUI

/// The album header: a motion cover if you attached one; otherwise the cover (edition cover, your own cover,
/// or the album artwork) as a moving Living Cover while you're on the page.
struct AlbumHeaderArt: View {
    let albumID: UInt64
    let note: AlbumNote?
    let edition: Edition?
    @State private var image: UIImage?
    @State private var look = ArtworkLook.neutral

    private var stillKey: String {
        "album-\(albumID)\(CoverVersions.suffix(albumID))-\(edition?.id.uuidString ?? "")-\(edition?.coverImage?.count ?? 0)"
    }

    var body: some View {
        let motion = edition?.motionCoverFile ?? note?.motionCoverFile
        ZStack {
            ArtworkView(albumID: albumID, cornerRadius: 0)
            if let motion {
                LoopingVideo(url: MotionCoverFiles.url(motion))
            } else if let image, MotionSettings.livingCoversOn {
                LivingCoverView(image: image, look: look, key: stillKey).transition(.opacity)
            }
        }
        .task(id: stillKey) {
            var img: UIImage?
            if let data = edition?.coverImage { img = UIImage(data: data) }
            if img == nil { img = CoverOverrides.shared.image(albumID) }
            if img == nil { img = await ArtworkCache.shared.image(album: albumID, pixels: 1400) }
            guard let img else { return }
            look = await ArtworkAnalysis.look(for: img, key: stillKey)
            withAnimation(.easeIn(duration: 0.4)) { image = img }
        }
    }
}

/// The top of an album page in the layout you chose: the cover edge to edge with your logo where you placed it,
/// or a square card over a blur of itself. Reports its height so the page knows when it has scrolled away.
struct CoverHeader<Art: View>: View {
    let lookKey: String
    let backdrop: LookRequest.Backdrop
    var coverColor: Color = .white
    /// 0…1 as the page scrolls past the header; your logo fades as it moves into the navigation bar.
    var scrolled: Double = 0
    @Binding var height: CGFloat
    @ViewBuilder let art: () -> Art

    var body: some View {
        let store = LookStore.shared
        let look = store.look(lookKey)
        Group {
            if look.layout == .square {
                ZStack {
                    LookBackdrop(backdrop: backdrop).blur(radius: 50).opacity(0.6).clipped()
                    LinearGradient(colors: [.black.opacity(0.2), Palette.background], startPoint: .center, endPoint: .bottom)
                    art()
                        .frame(width: 270, height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
                        .padding(.top, 60)
                }
                .frame(height: 420)
                .clipped()
            } else {
                art().aspectRatio(1, contentMode: .fit).clipped()
                    .overlay { LinearGradient(colors: [.clear, .black], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom) }
                    .overlay {
                        if let logo = store.logo(lookKey), let placement = look.placement {
                            PlacedLogo(image: logo, look: look, placement: placement, coverColor: coverColor)
                                .opacity(1 - scrolled)
                        }
                    }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
    }
}
