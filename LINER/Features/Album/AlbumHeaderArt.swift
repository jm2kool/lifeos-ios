import SwiftUI

/// The album header: a video cover (Studio's or the motion cover you attached), or the still cover (edition
/// cover, Studio's album-page cover, your own cover, or the album artwork) with its Studio motion effect, or as
/// a moving Living Cover while you're on the page.
struct AlbumHeaderArt: View {
    let albumID: UInt64
    let note: AlbumNote?
    let edition: Edition?
    var motion: StudioMotion = .off
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
                StudioMotionView(image: image, motion: motion, focus: look.focus, key: stillKey).transition(.opacity)
            } else if let image, MotionSettings.livingCoversOn {
                LivingCoverView(image: image, look: look, key: stillKey).transition(.opacity)
            }
        }
        .task(id: stillKey) {
            var img: UIImage?
            if let data = edition?.coverImage { img = UIImage(data: data) }
            if img == nil { img = StudioStore.shared.still(albumID, .album) }
            if img == nil { img = CoverOverrides.shared.image(albumID) }
            if img == nil { img = await ArtworkCache.shared.image(album: albumID, pixels: 1400) }
            guard let img else { return }
            look = await ArtworkAnalysis.look(for: img, key: stillKey)
            withAnimation(.easeIn(duration: 0.4)) { image = img }
        }
    }
}

#Preview {
    AlbumHeaderArt(albumID: PreviewData.snapshot.albums[0].id, note: nil, edition: nil, motion: .drift)
        .aspectRatio(1, contentMode: .fit)
        .environment(PreviewData.library).preferredColorScheme(.dark)
}
