import UIKit

/// Finds the cover for any queue item: an edition's cover (see `EditionCover`), your own album cover, library artwork from the cache, or a mixtape's cover.
@MainActor
enum CoverArt {
    static func image(for item: QueueItem, pixels: CGFloat) async -> UIImage? {
        switch item {
        case .library(let song):
            if let data = edition(for: item)?.coverImage, let img = UIImage(data: data) { return img }
            if let mine = CoverOverrides.shared.image(song.albumID) { return mine }
            return await ArtworkCache.shared.image(album: song.albumID, pixels: pixels)
        case .local(let track):
            if let data = edition(for: item)?.coverImage, let img = UIImage(data: data) { return img }
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
