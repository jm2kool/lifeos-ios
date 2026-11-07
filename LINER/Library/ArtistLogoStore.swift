import UIKit

/// Stylised artist names (the iOS 27-style artist titles): transparent logos from TheAudioDB's free API,
/// turned white so they sit in the monochrome design. Cached on disk; artists without a logo are re-checked monthly.
final class ArtistLogoStore: @unchecked Sendable {
    static let shared = ArtistLogoStore()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private let lookups = UserDefaults(suiteName: "liner.artistLogos") ?? .standard
    private static let limiter = RateLimiter(gap: .milliseconds(500))

    private struct Response: Decodable {
        struct Artist: Decodable { let strArtist: String?; let strArtistLogo: String? }
        let artists: [Artist]?
    }

    private init() {
        folder = URL.cachesDirectory.appending(path: "LINER/ArtistLogos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cached(_ name: String) -> UIImage? { memory.object(forKey: MediaKey.normalise(name) as NSString) }

    /// Whether we already know there's no logo (so the UI can skip a loading state).
    func knownMissing(_ name: String) -> Bool {
        guard let d = lookups.object(forKey: "miss.\(MediaKey.normalise(name))") as? Date else { return false }
        return Date.now.timeIntervalSince(d) < 30 * 86_400
    }

    @concurrent
    func logo(for name: String) async -> UIImage? {
        let key = MediaKey.normalise(name)
        guard !key.isEmpty else { return nil }
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = folder.appending(path: "\(key).png")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            return img
        }
        if knownMissing(name) { return nil }

        var parts = URLComponents(string: "https://www.theaudiodb.com/api/v1/json/123/search.php")!
        parts.queryItems = [URLQueryItem(name: "s", value: name)]
        await Self.limiter.wait()
        guard let url = parts.url, let result = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(Response.self, from: result.0),
              let match = decoded.artists?.first(where: { MediaKey.normalise($0.strArtist ?? "") == key }),
              let logoString = match.strArtistLogo, let logoURL = URL(string: logoString),
              let png = try? await URLSession.shared.data(from: logoURL).0,
              let original = UIImage(data: png), let white = Self.whiten(original) else {
            lookups.set(Date.now, forKey: "miss.\(key)")
            return nil
        }
        if let out = white.pngData() { try? out.write(to: file, options: .atomic) }
        memory.setObject(white, forKey: key as NSString)
        return white
    }

    /// Keeps the logo's shape (alpha) and paints it white, trimming empty edges.
    static func whiten(_ image: UIImage) -> UIImage? {
        let rect = CGRect(origin: .zero, size: image.size)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let white = UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(rect)
            image.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
        return trimmed(white)
    }

    private static func trimmed(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data),
              cg.bitsPerPixel == 32 else { return image }
        let w = cg.width, h = cg.height, row = cg.bytesPerRow
        let first = cg.alphaInfo == .premultipliedFirst || cg.alphaInfo == .first
        let little = cg.bitmapInfo.contains(.byteOrder32Little)
        let alphaOffset = first ? (little ? 3 : 0) : (little ? 0 : 3)
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) where ptr[y * row + x * 4 + alphaOffset] > 12 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY, let crop = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 2, height: maxY - minY + 2)) else { return image }
        return UIImage(cgImage: crop)
    }
}
