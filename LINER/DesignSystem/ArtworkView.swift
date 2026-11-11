import SwiftUI

/// Square album art: your own cover if you set one, else the library artwork from the cache, with a quiet
/// placeholder while it loads. Failed loads are retried, and tried again after each library scan.
struct ArtworkView: View {
    let albumID: UInt64?
    var cornerRadius: CGFloat = 8
    @Environment(\.displayScale) private var scale
    @Environment(LibraryService.self) private var library
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            let pixels = max(geo.size.width, geo.size.height) * scale
            let custom = albumID.flatMap { CoverOverrides.shared.image($0) }
            ZStack {
                Palette.placeholder
                if let shown = custom ?? image {
                    FillImage(image: shown).transition(.opacity)
                } else {
                    Image(systemName: "music.note").font(.system(size: max(12, geo.size.width * 0.22))).foregroundStyle(Palette.faint)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .task(id: "\(albumID ?? 0)-\(Int(pixels))-\(library.snapshot.scannedAt.timeIntervalSince1970)") {
                guard custom == nil, let albumID, pixels > 0 else { return }
                if let hit = ArtworkCache.shared.cached(album: albumID, pixels: pixels) { image = hit; return }
                for attempt in 0..<3 {
                    if let loaded = await ArtworkCache.shared.image(album: albumID, pixels: pixels) {
                        withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                        return
                    }
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(1.0 + Double(attempt)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A black-and-white artist photo (or the poster you picked for them), falling back to their top album's cover
/// (also in black and white).
struct ArtistPortraitView: View {
    let name: String
    var fallbackAlbumID: UInt64?
    /// Told about the photo once it's loaded (the artist page uses it to keep the title readable).
    var onLoad: ((UIImage) -> Void)?
    @State private var portrait: UIImage?
    @State private var tried = false

    var body: some View {
        let mine = ArtistPosters.shared.image(name)
        ZStack {
            if let shown = mine ?? portrait {
                FillImage(image: shown).transition(.opacity).id(ObjectIdentifier(shown))
            } else if tried {
                ArtworkView(albumID: fallbackAlbumID, cornerRadius: 0).grayscale(1)
            } else {
                Palette.placeholder
            }
        }
        .clipped()
        .task(id: "\(name)-\(ArtistPosters.shared.version(name))") {
            if let mine { onLoad?(mine); return }
            if let hit = ArtistImageStore.shared.cached(name) { portrait = hit; tried = true; onLoad?(hit); return }
            let loaded = await ArtistImageStore.shared.portrait(for: name)
            withAnimation(.easeOut(duration: 0.25)) { portrait = loaded; tried = true }
            if let loaded { onLoad?(loaded) }
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
    .environment(PreviewData.library)
}
