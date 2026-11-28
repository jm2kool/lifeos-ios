import SwiftUI

/// The album header: a video cover (Studio's, or the motion cover you attached); otherwise the still cover
/// (edition cover, Studio's album-page cover, your own cover, or the album artwork), held still unless you gave
/// it a motion effect in Studio.
struct AlbumHeaderArt: View {
    let albumID: UInt64
    let note: AlbumNote?
    let edition: Edition?
    var motion: StudioMotion = .off
    /// Told about the still cover once it's loaded, with a key for it (the page takes its colours).
    var onImage: ((UIImage, String) -> Void)?
    @State private var image: UIImage?
    @State private var look = ArtworkLook.neutral

    private var stillKey: String {
        "album-\(albumID)\(CoverVersions.suffix(albumID))-\(edition?.id.uuidString ?? "")-\(edition?.coverImage?.count ?? 0)"
    }

    var body: some View {
        let video = edition?.motionCoverFile ?? StudioStore.shared.video(albumID, .album) ?? note?.motionCoverFile
        ZStack {
            ArtworkView(albumID: albumID, cornerRadius: 0, place: .album)
            if let video {
                LoopingVideo(url: MotionCoverFiles.url(video))
            } else if let image, motion != .off {
                // Still unless you gave the cover motion in Studio.
                StudioMotionView(image: image, motion: motion, focus: look.focus, key: stillKey).transition(.opacity)
            }
        }
        .task(id: stillKey) {
            var img: UIImage?
            if let data = edition?.coverImage { img = UIImage(data: data) }
            if img == nil { img = StudioStore.shared.still(albumID, .album) }
            if img == nil { img = CoverOverrides.shared.image(albumID) }
            if img == nil { img = await ArtworkCache.shared.image(album: albumID, pixels: 1400) }
            guard let img else { return }
            onImage?(img, stillKey)
            look = await ArtworkAnalysis.look(for: img, key: stillKey)
            withAnimation(.easeIn(duration: 0.4)) { image = img }
        }
    }
}

/// The top of an album page in the layout you chose: the cover edge to edge with your logo where you placed it,
/// or a square card over a blur of itself. Either melts at the bottom into the page painted with the cover's colours. Reports its height so the page knows when it has scrolled away.
struct CoverHeader<Art: View>: View {
    let lookKey: String
    let backdrop: LookRequest.Backdrop
    var coverColor: Color = .white
    /// 0…1 as the page scrolls past the header; your logo fades as it moves into the navigation bar.
    var scrolled: Double = 0
    @Binding var height: CGFloat
    /// The page colour the full-screen cover fades into, finishing by the title (nil keeps a plain fade).
    var fadeColour: Color? = nil
    @ViewBuilder let art: () -> Art

    var body: some View {
        let store = LookStore.shared
        let look = store.look(lookKey)
        Group {
            if look.layout == .square {
                ZStack {
                    LookBackdrop(backdrop: backdrop).blur(radius: 50).opacity(0.6).clipped()
                    Color.black.opacity(0.2)
                    art()
                        .frame(width: 270, height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
                        .padding(.top, 60)
                }
                .frame(height: 420)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            } else {
                art().aspectRatio(1, contentMode: .fit).clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: fadeColour == nil ? 0.6 : 0.5),
                                             .init(color: .clear, location: fadeColour == nil ? 1 : 0.94)], startPoint: .top, endPoint: .bottom))
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
