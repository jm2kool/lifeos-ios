import SwiftUI
import UIKit

/// Album logos you add yourself, for albums whose cover has no clean title to lift (or when you'd rather use
/// another one). Kept as PNGs in Application Support/LINER/AlbumLogos, so they survive cache clear-outs, and
/// included in the JSON backup. A logo of your own always wins over the one lifted from the cover.
@MainActor @Observable
final class CustomAlbumLogos {
    static let shared = CustomAlbumLogos()
    /// Goes up whenever a logo is set or removed, so titles on screen reload.
    private(set) var revision = 0
    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL

    private init() {
        folder = URL.applicationSupportDirectory.appending(path: "LINER/AlbumLogos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ albumID: UInt64) -> URL { folder.appending(path: "\(albumID).png") }

    func has(_ albumID: UInt64) -> Bool { FileManager.default.fileExists(atPath: file(albumID).path) }

    func image(_ albumID: UInt64) -> UIImage? {
        let key = String(albumID) as NSString
        if let hit = memory.object(forKey: key) { return hit }
        guard let data = try? Data(contentsOf: file(albumID)), let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: key)
        return img
    }

    /// The stored PNG, for the backup.
    func data(_ albumID: UInt64) -> Data? { try? Data(contentsOf: file(albumID)) }

    /// Saves a picture as the album's logo. Returns false when it isn't a picture.
    @discardableResult
    func set(_ data: Data, for albumID: UInt64) async -> Bool {
        guard let picked = UIImage(data: data) else { return false }
        let png = await Task.detached(priority: .userInitiated) { Self.prepare(picked) }.value
        guard let png else { return false }
        return store(png, for: albumID)
    }

    /// Puts back a logo from a backup, as it was saved.
    @discardableResult
    func store(_ png: Data, for albumID: UInt64) -> Bool {
        guard UIImage(data: png) != nil, (try? png.write(to: file(albumID), options: .atomic)) != nil else { return false }
        memory.removeObject(forKey: String(albumID) as NSString)
        revision += 1
        return true
    }

    func remove(_ albumID: UInt64) {
        try? FileManager.default.removeItem(at: file(albumID))
        memory.removeObject(forKey: String(albumID) as NSString)
        revision += 1
    }

    /// Makes the titles on screen look again (after Album title logos is switched on or off).
    func refresh() { revision += 1 }

    /// Every album with a logo of its own.
    var albumIDs: [UInt64] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).compactMap { UInt64($0.dropLast(4)) }
    }

    /// A picture ready to use as a logo: scaled down, and when it has a plain background (a screenshot, a JPEG)
    /// the lettering is cut away from it. Pictures that are already transparent are kept as they are.
    nonisolated private static func prepare(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height) * image.scale
        let scale = min(1, 1400 / max(longest, 1))
        let size = CGSize(width: max(1, image.size.width * image.scale * scale), height: max(1, image.size.height * image.scale * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let cg = drawn.cgImage else { return nil }
        if !isTransparent(cg), let cut = LogoLifter.cutOut(cg) { return cut }
        return drawn.pngData()
    }

    /// Whether a fair part of the picture is see-through (so it's already a cut-out logo).
    nonisolated private static func isTransparent(_ image: CGImage) -> Bool {
        let w = 48, h = 48
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return false }
        let clear = (0..<(w * h)).filter { px[$0 * 4 + 3] < 40 }.count
        return Double(clear) / Double(w * h) > 0.08
    }
}

/// Remembers, per cover, whether the album's name is printed on it, so sleeves don't print it a second time.
@MainActor
enum CoverTitles {
    private static var known: [String: Bool] = [:]

    /// `key` names the cover (and changes when the cover does).
    static func printed(on cover: UIImage, title: String, key: String) async -> Bool {
        let key = "coverTitle.\(key)"
        if let hit = known[key] { return hit }
        if let saved = UserDefaults.standard.object(forKey: key) as? Bool { known[key] = saved; return saved }
        let found = await Task.detached(priority: .utility) { LogoLifter.coverShowsTitle(cover, title: title) }.value
        known[key] = found
        UserDefaults.standard.set(found, forKey: key)
        return found
    }
}
