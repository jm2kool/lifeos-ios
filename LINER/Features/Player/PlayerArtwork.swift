import SwiftUI

/// Loads the current item's cover and its look (colours + focus) for the player screens.
@MainActor @Observable
final class PlayerArtwork {
    private(set) var image: UIImage?
    private(set) var look = ArtworkLook.neutral
    private(set) var key: String?

    func load(_ item: QueueItem?) async {
        guard let item else { image = nil; key = nil; return }
        let itemKey = CoverArt.key(for: item)
        guard itemKey != key else { return }
        key = itemKey
        let img = await CoverArt.image(for: item, pixels: 1600)
        var look = ArtworkLook.neutral
        if let img { look = await ArtworkAnalysis.look(for: img, key: itemKey) }
        guard key == itemKey else { return }
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
            if let song = item.song, CoverArt.edition(for: item)?.coverImage == nil {
                ArtworkView(albumID: song.albumID, cornerRadius: cornerRadius)
            } else {
                ZStack {
                    Palette.placeholder
                    if let image { FillImage(image: image) }
                    else { Image(systemName: item.isLibrary ? "music.note" : "recordingtape").foregroundStyle(Palette.faint) }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .task(id: CoverArt.key(for: item)) { image = await CoverArt.image(for: item, pixels: 300) }
            }
        }
    }
}
