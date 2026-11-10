import UIKit

/// Your own artist posters: any photo you pick for an artist, shown wherever their portrait would be (artist
/// pages, pins, share cards). Kept in Application Support so they survive cache clears; black and white by
/// default like the rest of the app's portraits, or in colour if you choose.
@MainActor @Observable
final class ArtistPosters {
    static let shared = ArtistPosters()
    /// Bumped whenever an artist's poster changes, so views showing it reload.
    private(set) var versions: [String: Int] = [:]
    @ObservationIgnored private var images: [String: UIImage] = [:]
    @ObservationIgnored private var missing = Set<String>()
    private let folder: URL

    private init() {
        folder = URL.applicationSupportDirectory.appending(path: "LINER/ArtistPosters", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL { folder.appending(path: "\(key).jpg") }

    func version(_ name: String) -> Int { versions[MediaKey.normalise(name)] ?? 0 }

    /// Your poster for the artist, if you picked one.
    func image(_ name: String) -> UIImage? {
        let key = MediaKey.normalise(name)
        _ = versions[key]   // so views reading this refresh when it changes
        guard !key.isEmpty else { return nil }
        if let hit = images[key] { return hit }
        if missing.contains(key) { return nil }
        guard let data = try? Data(contentsOf: file(key)), let img = UIImage(data: data) else { missing.insert(key); return nil }
        images[key] = img
        return img
    }

    /// Sets (or, with nil, removes) your poster for an artist.
    func set(_ data: Data?, blackAndWhite: Bool, for name: String) {
        let key = MediaKey.normalise(name)
        guard !key.isEmpty else { return }
        if let data, let picked = UIImage(data: data) {
            let upright = Self.upright(picked, longest: 1600)
            let final = blackAndWhite ? (ArtistImageStore.noir(upright) ?? upright) : upright
            try? final.jpegData(compressionQuality: 0.88)?.write(to: file(key), options: .atomic)
            images[key] = final
            missing.remove(key)
        } else {
            try? FileManager.default.removeItem(at: file(key))
            images[key] = nil
            missing.insert(key)
        }
        versions[key, default: 0] += 1
    }

    /// Every poster as JPEG data by artist key, for backups.
    func all() -> [String: Data] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var out: [String: Data] = [:]
        for f in files where f.pathExtension == "jpg" { out[f.deletingPathExtension().lastPathComponent] = try? Data(contentsOf: f) }
        return out
    }

    /// Puts back posters from a backup.
    func restore(_ posters: [String: Data]) {
        for (key, data) in posters where !key.isEmpty && !key.contains("/") {
            try? data.write(to: file(key), options: .atomic)
            images[key] = nil
            missing.remove(key)
            versions[key, default: 0] += 1
        }
    }

    /// Draws the photo the right way up (camera photos are often stored sideways) and no bigger than needed.
    private static func upright(_ image: UIImage, longest: CGFloat) -> UIImage {
        let scale = min(1, longest / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
