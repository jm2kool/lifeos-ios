@preconcurrency import MediaPlayer
import UIKit

/// Album artwork, loaded off the main thread at the size asked for, kept in memory (NSCache) and on disk.
/// Artwork comes straight from the scanned MediaPlayer items (no per-album queries), a few decodes at a time,
/// so fast scrolling doesn't starve it and nothing is left blank.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private let lock = NSLock()
    private var index: [UInt64: MPMediaItem] = [:]
    /// Covers that come from the web (Apple Music songs on artist pages that aren't in the library).
    private var remote: [UInt64: URL] = [:]
    private let gate = Gate(limit: 4)

    private init() {
        memory.totalCostLimit = 120 * 1024 * 1024
        folder = URL.cachesDirectory.appending(path: "LINER/Artwork", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Called after each scan: which item carries each album's artwork.
    func update(_ snapshot: LibrarySnapshot) {
        var map: [UInt64: MPMediaItem] = [:]
        for (albumID, songID) in snapshot.artworkSongs { if let item = snapshot.items[songID] { map[albumID] = item } }
        lock.withLock { index = map }
    }

    /// Registers a web cover for an album ID that isn't in the library.
    func register(remote url: URL, for album: UInt64) { lock.withLock { remote[album] = url } }

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
        await gate.enter()
        defer { Task { await gate.leave() } }
        if let hit = memory.object(forKey: k as NSString) { return hit }
        if let url = lock.withLock({ remote[album] }) {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let web = UIImage(data: data) else { return nil }
            let img = Self.resize(web, to: side)
            store(img, k)
            return img
        }
        guard !Task.isCancelled, let art = artwork(album: album, side: side) else { return nil }
        let img = Self.resize(art, to: side)
        store(img, k)
        if let jpeg = img.jpegData(compressionQuality: 0.85) { try? jpeg.write(to: file, options: .atomic) }
        return img
    }

    private func artwork(album: UInt64, side: Int) -> UIImage? {
        let item = lock.withLock { index[album] } ?? Self.query(album: album)
        guard let art = item?.artwork else { return nil }
        // Some cloud artwork reports odd bounds; ask at the requested size, then at its own size.
        return art.image(at: CGSize(width: side, height: side))
            ?? (art.bounds.width > 0 ? art.image(at: art.bounds.size) : nil)
    }

    private static func query(album: UInt64) -> MPMediaItem? {
        let q = MPMediaQuery.songs()
        q.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: album), forProperty: MPMediaItemPropertyAlbumPersistentID))
        return q.items?.first { $0.artwork != nil }
    }

    private func store(_ img: UIImage, _ k: String) {
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        memory.setObject(img, forKey: k as NSString, cost: cost)
    }

    /// Clears memory and disk (Settings → rebuild).
    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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

/// Lets a few artwork decodes run at once; the rest wait their turn.
actor Gate {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func enter() async {
        if running < limit { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }
}
