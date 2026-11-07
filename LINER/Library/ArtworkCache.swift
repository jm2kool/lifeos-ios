@preconcurrency import MediaPlayer
import UIKit

/// Album artwork, loaded off the main thread at the size asked for, kept in memory (NSCache) and on disk.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL

    private init() {
        memory.totalCostLimit = 120 * 1024 * 1024
        folder = URL.cachesDirectory.appending(path: "LINER/Artwork", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Sizes are rounded up to a few buckets so a grid and a list share files.
    static func bucket(_ pixels: CGFloat) -> Int {
        [160, 320, 640, 1000, 1600].first { CGFloat($0) >= pixels } ?? 1600
    }

    private func key(_ album: UInt64, _ side: Int) -> String { "\(album)-\(side)" }

    /// Instant memory hit, for the first frame of a view.
    func cached(album: UInt64, pixels: CGFloat) -> UIImage? {
        memory.object(forKey: key(album, Self.bucket(pixels)) as NSString)
    }

    @concurrent
    func image(album: UInt64, pixels: CGFloat) async -> UIImage? {
        let side = Self.bucket(pixels)
        let k = key(album, side)
        if let hit = memory.object(forKey: k as NSString) { return hit }
        let file = folder.appending(path: "\(k).jpg")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            store(img, k)
            return img
        }
        guard let art = Self.artwork(album: album)?.image(at: CGSize(width: side, height: side)) else { return nil }
        let img = Self.resize(art, to: side)
        store(img, k)
        if let jpeg = img.jpegData(compressionQuality: 0.85) { try? jpeg.write(to: file, options: .atomic) }
        return img
    }

    private func store(_ img: UIImage, _ k: String) {
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        memory.setObject(img, forKey: k as NSString, cost: cost)
    }

    /// Clears memory and disk (Settings → rebuild, or when artwork changes).
    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private static func artwork(album: UInt64) -> MPMediaItemArtwork? {
        let q = MPMediaQuery.songs()
        q.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: album), forProperty: MPMediaItemPropertyAlbumPersistentID))
        return q.items?.first { $0.artwork != nil }?.artwork
    }

    private static func resize(_ image: UIImage, to side: Int) -> UIImage {
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        guard longest > CGFloat(side) * 1.1 else { return image }
        let ratio = CGFloat(side) / longest
        let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
