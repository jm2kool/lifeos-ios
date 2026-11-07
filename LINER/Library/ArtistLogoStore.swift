import UIKit

/// Stylised artist names (the iOS 27-style artist titles): logos fetched automatically from TheAudioDB's free API
/// on each phone, turned white so they sit in the monochrome design, and cached. Artists without a logo are
/// re-checked weekly (so new logos turn up on their own), and saved logos refresh every two months.
final class ArtistLogoStore: @unchecked Sendable {
    static let shared = ArtistLogoStore()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private let lookups = UserDefaults(suiteName: "liner.artistLogos.v2") ?? .standard
    private static let limiter = RateLimiter(gap: .milliseconds(500))

    private struct Response: Decodable {
        struct Artist: Decodable { let strArtist: String?; let strArtistLogo: String? }
        let artists: [Artist]?
    }

    private init() {
        folder = URL.cachesDirectory.appending(path: "LINER/ArtistLogos2", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cached(_ name: String) -> UIImage? { memory.object(forKey: MediaKey.normalise(name) as NSString) }

    /// Whether we already know there's no logo (so the UI can skip a loading state).
    func knownMissing(_ name: String) -> Bool {
        guard let d = lookups.object(forKey: "miss.\(MediaKey.normalise(name))") as? Date else { return false }
        return Date.now.timeIntervalSince(d) < 7 * 86_400
    }

    @concurrent
    func logo(for name: String) async -> UIImage? {
        let key = MediaKey.normalise(name)
        guard !key.isEmpty else { return nil }
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = folder.appending(path: "\(key).png")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date.now.timeIntervalSince($0) } ?? 0
            if age > 60 * 86_400 { Task { await self.fetch(name, key: key, file: file) } }   // refresh quietly
            return img
        }
        if knownMissing(name) { return nil }
        return await fetch(name, key: key, file: file)
    }

    /// Downloads and processes the logo; nil if there isn't one (remembered for a week) or the request failed.
    @concurrent
    private func fetch(_ name: String, key: String, file: URL) async -> UIImage? {

        var parts = URLComponents(string: "https://www.theaudiodb.com/api/v1/json/123/search.php")!
        parts.queryItems = [URLQueryItem(name: "s", value: name)]
        await Self.limiter.wait()
        guard let url = parts.url, let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }   // offline: try again later
        guard let decoded = try? JSONDecoder().decode(Response.self, from: result.0),
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

    /// Turns a logo into white lettering on transparency. Logos with a real transparent background keep their
    /// shape; logos on a solid background (white or black) are cut out by their contrast with that background.
    /// Returns nil when the result wouldn't read as lettering (for example, a photo), so the app uses type instead.
    static func whiten(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 8, h > 8, w * h < 12_000_000 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drew = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }

        let n = w * h
        var alpha = [Double](repeating: 0, count: n), lum = [Double](repeating: 0, count: n)
        for p in 0..<n {
            let o = p * 4
            let a = Double(px[o + 3]) / 255
            alpha[p] = a
            lum[p] = a > 0.01 ? (0.299 * Double(px[o]) + 0.587 * Double(px[o + 1]) + 0.114 * Double(px[o + 2])) / 255 / a : 0
        }
        func coverage(_ m: [Double]) -> Double { Double(m.reduce(0) { $0 + ($1 > 0.5 ? 1 : 0) }) / Double(n) }
        /// How much each pixel stands out from a reference brightness (the plate or background).
        func contrast(_ ref: Double, weighted: Bool) -> [Double] {
            (0..<n).map { p in (weighted ? alpha[p] * alpha[p] : 1) * min(1, max(0, (abs(lum[p] - ref) - 0.12) / 0.35)) }
        }

        var candidates: [[Double]] = []
        let opaque = (0..<n).filter { alpha[$0] > 0.78 }
        if Double(n - opaque.count) / Double(n) > 0.08 {
            // Transparent background. If the visible part is two-tone (lettering printed on a plate, like a
            // sticker), keep only what stands out from the plate; otherwise keep the logo's own shape.
            if !opaque.isEmpty {
                let dark = opaque.filter { lum[$0] < 0.3 }, light = opaque.filter { lum[$0] > 0.7 }
                let total = Double(opaque.count), middle = total - Double(dark.count + light.count)
                if Double(dark.count) / total >= 0.15, Double(light.count) / total >= 0.15, middle / total < 0.15 {
                    let plate = light.count >= dark.count ? light : dark
                    candidates.append(contrast(plate.reduce(0) { $0 + lum[$1] } / Double(plate.count), weighted: true))
                }
            }
            candidates.append(alpha)
        } else {
            // Solid background: cut the lettering out by its contrast with the corners.
            let corners = [lum[0], lum[w - 1], lum[(h - 1) * w], lum[n - 1]]
            candidates.append(contrast(corners.reduce(0, +) / 4, weighted: false))
        }
        // Lettering covers a modest part of its box; a solid slab or a photo doesn't.
        guard let chosen = candidates.first(where: { (0.01..<0.6).contains(coverage($0)) }) else { return nil }
        let mask = chosen.map { UInt8(min(255, max(0, $0 * 255))) }

        var out = [UInt8](repeating: 0, count: w * h * 4)
        for p in 0..<n {
            let v = mask[p]
            out[p * 4] = v; out[p * 4 + 1] = v; out[p * 4 + 2] = v; out[p * 4 + 3] = v   // premultiplied white
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let made = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return trimmed(UIImage(cgImage: made))
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
