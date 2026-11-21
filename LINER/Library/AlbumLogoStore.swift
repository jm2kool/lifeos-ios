import SwiftUI
import UIKit

/// Album title logos, the way Matinee shows film logos. No music service offers album logos, so they're lifted
/// from the cover: on-device text recognition finds where the album's name is printed, and that lettering is cut
/// away from its background. Only clean results are kept (the name found, on a plain enough background); every
/// other album keeps its title in text. Dark lettering is turned white so it reads on LINER.'s black.
/// Setting: Settings → Covers → Album title logos.
@MainActor
final class AlbumLogoStore {
    static let shared = AlbumLogoStore()
    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private let misses = UserDefaults.standard

    static var enabled: Bool { UserDefaults.standard.object(forKey: "albumLogos") as? Bool ?? true }

    private init() {
        folder = URL.cachesDirectory.appending(path: "LINER/AlbumLogos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The album's title logo, or nil when the cover doesn't have a clean one.
    func logo(albumID: UInt64, title: String) async -> UIImage? {
        guard Self.enabled else { return nil }
        let key = "\(albumID)\(CoverVersions.suffix(albumID))"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if misses.bool(forKey: "albumLogo.miss.\(key)") { return nil }
        let file = folder.appending(path: "\(key).png")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            return img
        }
        var cover = CoverOverrides.shared.image(albumID)
        if cover == nil { cover = await ArtworkCache.shared.image(album: albumID, pixels: 1200) }
        guard let cover else { return nil }   // no cover yet: try again next time
        let png = await Task.detached(priority: .utility) { LogoLifter.lift(cover, title: title) }.value
        guard let png, let img = UIImage(data: png) else {
            misses.set(true, forKey: "albumLogo.miss.\(key)")
            return nil
        }
        try? png.write(to: file)
        memory.setObject(img, forKey: key as NSString)
        return img
    }
}
