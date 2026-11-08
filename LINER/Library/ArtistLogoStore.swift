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

    /// Whether we already know there's no logo (so the UI can skip a loading state). For a collaboration that
    /// means no logo of its own and no combined one either.
    func knownMissing(_ name: String) -> Bool {
        let key = MediaKey.normalise(name)
        func missed(_ k: String) -> Bool {
            guard let d = lookups.object(forKey: k) as? Date else { return false }
            return Date.now.timeIntervalSince(d) < 7 * 86_400
        }
        guard missed("miss.\(key)") else { return false }
        return Self.collaborators(name).count < 2 || missed("comboMiss.\(key)")
    }

    /// The artists in a collaboration credit ("Drake & PARTYNEXTDOOR", "A x B", "A, B and C", "A feat. B"), or
    /// just the name when it's one artist.
    static func collaborators(_ name: String) -> [String] {
        let pattern = #"\s+(?:&|\+|x|×|and|with|feat\.?|ft\.?|featuring|vs\.?)\s+|\s*,\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [name] }
        let ns = name as NSString
        var parts: [String] = [], last = 0
        for m in regex.matches(in: name, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: last))
        let clean = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return clean.count >= 2 && clean.count <= 3 ? clean : [name]
    }

    @concurrent
    func logo(for name: String) async -> UIImage? {
        let key = MediaKey.normalise(name)
        guard !key.isEmpty else { return nil }
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = folder.appending(path: "\(key).png")
        let parts = Self.collaborators(name)
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date.now.timeIntervalSince($0) } ?? 0
            if age > 60 * 86_400 && parts.count < 2 { Task { await self.fetch(name, key: key, file: file) } }   // refresh quietly
            return img
        }
        if knownMissing(name) { return nil }
        // A duo with a logo of its own uses it; otherwise each artist's logo, put together.
        if let own = await fetch(name, key: key, file: file) { return own }
        guard parts.count >= 2 else { return nil }
        var logos: [UIImage] = []
        for part in parts {
            guard let l = await logo(for: part) else { break }
            logos.append(l)
        }
        guard logos.count == parts.count, let combined = Self.combine(logos) else {
            lookups.set(Date.now, forKey: "comboMiss.\(key)")
            return nil
        }
        if let out = combined.pngData() { try? out.write(to: file, options: .atomic) }
        memory.setObject(combined, forKey: key as NSString)
        return combined
    }

    /// Several artists' logos as one: each scaled to the same height, side by side with a thin "&" between; if
    /// that's too long and thin, stacked instead, each the same width.
    static func combine(_ logos: [UIImage]) -> UIImage? {
        guard !logos.isEmpty else { return nil }
        let height: CGFloat = 160
        let sized = logos.map { CGSize(width: $0.size.width / max($0.size.height, 1) * height, height: height) }
        let amp = NSAttributedString(string: "&", attributes: [
            .font: UIFont.systemFont(ofSize: height * 0.45, weight: .ultraLight), .foregroundColor: UIColor.white,
        ])
        let ampSize = amp.size()
        let gap = height * 0.18
        let rowWidth = sized.reduce(0) { $0 + $1.width } + CGFloat(logos.count - 1) * (ampSize.width + gap * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        if rowWidth / height <= 7 {
            return UIGraphicsImageRenderer(size: CGSize(width: rowWidth, height: height), format: format).image { _ in
                var x: CGFloat = 0
                for (i, logo) in logos.enumerated() {
                    if i > 0 {
                        x += gap
                        amp.draw(at: CGPoint(x: x, y: (height - ampSize.height) / 2))
                        x += ampSize.width + gap
                    }
                    logo.draw(in: CGRect(origin: CGPoint(x: x, y: 0), size: sized[i]))
                    x += sized[i].width
                }
            }
        }
        // Stacked: same width each, the "&" on its own small line between.
        let width: CGFloat = 600
        let stacked = logos.map { CGSize(width: width, height: $0.size.height / max($0.size.width, 1) * width) }
        let total = stacked.reduce(0) { $0 + $1.height } + CGFloat(logos.count - 1) * (ampSize.height + gap)
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: total), format: format).image { _ in
            var y: CGFloat = 0
            for (i, logo) in logos.enumerated() {
                if i > 0 {
                    amp.draw(at: CGPoint(x: (width - ampSize.width) / 2, y: y + gap / 2))
                    y += ampSize.height + gap
                }
                logo.draw(in: CGRect(origin: CGPoint(x: 0, y: y), size: stacked[i]))
                y += stacked[i].height
            }
        }
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
