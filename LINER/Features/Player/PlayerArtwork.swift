import SwiftUI

/// Loads the current item's cover and its look (colours + focus) for the player screens.
@MainActor @Observable
final class PlayerArtwork {
    private(set) var image: UIImage?
    private(set) var look = ArtworkLook.neutral
    private(set) var key: String?

    func load(_ item: QueueItem?) async {
        guard let item else { image = nil; key = nil; return }
        guard item.artworkKey != key else { return }
        key = item.artworkKey
        let img = await CoverArt.image(for: item, pixels: 1600)
        var look = ArtworkLook.neutral
        if let img { look = await ArtworkAnalysis.look(for: img, key: item.artworkKey) }
        guard key == item.artworkKey else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            self.image = img
            self.look = look
        }
    }
}

/// Small square cover for any queue item.
struct QueueItemArtwork: View {
    let item: QueueItem
    var cornerRadius: CGFloat = 6
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let song = item.song {
                ArtworkView(albumID: song.albumID, cornerRadius: cornerRadius)
            } else {
                ZStack {
                    Palette.placeholder
                    if let image { FillImage(image: image) }
                    else { Image(systemName: "recordingtape").foregroundStyle(Palette.faint) }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .task(id: item.id) { image = await CoverArt.image(for: item, pixels: 300) }
            }
        }
    }
}
