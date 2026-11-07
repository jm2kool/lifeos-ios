import SwiftUI

/// Square album art from the cache, with a quiet placeholder while it loads.
struct ArtworkView: View {
    let albumID: UInt64?
    var cornerRadius: CGFloat = 8
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            let pixels = max(geo.size.width, geo.size.height) * scale
            ZStack {
                Palette.placeholder
                if let image {
                    FillImage(image: image)
                        .transition(.opacity)
                } else {
                    Image(systemName: "music.note").font(.system(size: max(12, geo.size.width * 0.22))).foregroundStyle(Palette.faint)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .task(id: "\(albumID ?? 0)-\(Int(pixels))") {
                guard let albumID, pixels > 0 else { return }
                if let hit = ArtworkCache.shared.cached(album: albumID, pixels: pixels) { image = hit; return }
                let loaded = await ArtworkCache.shared.image(album: albumID, pixels: pixels)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A black-and-white artist photo, falling back to their top album's cover (also in black and white).
struct ArtistPortraitView: View {
    let name: String
    var fallbackAlbumID: UInt64?
    @State private var portrait: UIImage?
    @State private var tried = false

    var body: some View {
        ZStack {
            if let portrait {
                FillImage(image: portrait).transition(.opacity)
            } else if tried {
                ArtworkView(albumID: fallbackAlbumID, cornerRadius: 0).grayscale(1)
            } else {
                Palette.placeholder
            }
        }
        .clipped()
        .task(id: name) {
            if let hit = ArtistImageStore.shared.cached(name) { portrait = hit; tried = true; return }
            let loaded = await ArtistImageStore.shared.portrait(for: name)
            withAnimation(.easeOut(duration: 0.25)) { portrait = loaded; tried = true }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ArtworkView(albumID: nil).frame(width: 120, height: 120)
        ArtistPortraitView(name: "Lorde").frame(width: 120, height: 120).clipShape(Circle())
    }
    .padding().background(.black)
}
