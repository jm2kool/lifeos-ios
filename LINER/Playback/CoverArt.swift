import UIKit

/// Finds the cover for any queue item: library artwork from the cache, or a mixtape's saved cover.
enum CoverArt {
    static func image(for item: QueueItem, pixels: CGFloat) async -> UIImage? {
        switch item {
        case .library(let song):
            return await ArtworkCache.shared.image(album: song.albumID, pixels: pixels)
        case .local(let track):
            guard let url = track.coverURL else { return nil }
            return await loadFile(url)
        }
    }

    @concurrent
    static func loadFile(_ url: URL) async -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
