import simd
import SwiftUI
import UIKit

/// The colours of a piece of artwork, toned for painting a whole page behind white text. Artist, album,
/// release, playlist and mixtape pages use them for their moving colour canvas (`ArtCanvas`).
enum ArtPalette {
    typealias RGB = SIMD3<Float>

    nonisolated(unsafe) private static var cache: [String: [RGB]] = [:]
    private static let lock = NSLock()

    static func cached(_ key: String) -> [RGB]? { lock.withLock { cache[key] } }

    /// Up to six colours from these images. Each image takes a turn, so a page of several covers mixes them all.
    @concurrent
    static func colours(of images: [UIImage], key: String) async -> [RGB] {
        if let hit = cached(key) { return hit }
        let perImage = images.compactMap(\.cgImage).map(swatches)
        var picked: [RGB] = []
        var round = 0
        while picked.count < 6, perImage.contains(where: { $0.count > round }) {
            for list in perImage where list.count > round && picked.count < 6 {
                let c = list[round]
                if picked.allSatisfy({ simd_distance($0, c) > 0.12 }) { picked.append(c) }
            }
            round += 1
        }
        let toned = canvas(picked)
        if !toned.isEmpty { lock.withLock { cache[key] = toned } }
        return toned
    }

    /// One colour from a photo, in a few close shades: the page reads as a single colour that gently breathes
    /// (the artist page, painted from the artist's photo).
    @concurrent
    static func tint(of image: UIImage, key: String) async -> [RGB] {
        if let hit = cached(key) { return hit }
        guard let cg = image.cgImage, let lead = swatches(cg).first else { return [] }
        let (h, s0, v0) = hsv(lead)
        let neutral = s0 < 0.15
        let s = neutral ? s0 : min(1, max(s0, 0.6))
        let v = neutral ? min(max(v0, 0.18), 0.32) : min(max(v0, 0.34), 0.52)
        let near = { (shift: Float) in (h + shift + 1).truncatingRemainder(dividingBy: 1) }
        let out = [rgb(h, s, v), rgb(near(0.015), s, v * 0.8), rgb(near(-0.015), s * 0.92, min(1, v * 1.15)), rgb(h, s, v * 0.62)]
        lock.withLock { cache[key] = out }
        return out
    }

    /// Colours from library album covers (your own cover where you set one).
    @MainActor
    static func albums(_ ids: [UInt64]) async -> [RGB] {
        let key = "albums-" + ids.map(String.init).joined(separator: ",")
        if let hit = cached(key) { return hit }
        var images: [UIImage] = []
        for id in ids {
            if let own = CoverOverrides.shared.image(id) { images.append(own) }
            else if let img = await ArtworkCache.shared.image(album: id, pixels: 160) { images.append(img) }
        }
        return await colours(of: images, key: key)
    }

    /// Colours from covers on the web (Apple Music releases).
    @MainActor
    static func web(_ urls: [URL], key: String) async -> [RGB] {
        if let hit = cached(key) { return hit }
        var images: [UIImage] = []
        for url in urls {
            if let data = try? await URLSession.shared.data(from: url).0, let img = UIImage(data: data) { images.append(img) }
        }
        return await colours(of: images, key: key)
    }

    // MARK: - Extraction

    /// Downsample, bucket pixels by hue, and rank the buckets by how much — and how vividly — they appear.
    private static func swatches(_ image: CGImage) -> [RGB] {
        let w = 40, h = 40
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }
        let bins = 13   // 12 hues + 1 neutral
        var sum = [RGB](repeating: .zero, count: bins)
        var count = [Float](repeating: 0, count: bins)
        var score = [Float](repeating: 0, count: bins)
        for i in stride(from: 0, to: px.count, by: 4) {
            let c = RGB(Float(px[i]), Float(px[i + 1]), Float(px[i + 2])) / 255
            let (hue, s, v) = hsv(c)
            if v < 0.08 { continue }                 // near-black
            if s < 0.08 && v > 0.93 { continue }     // near-white
            let bin = s < 0.18 ? 12 : Int(hue * 12) % 12
            sum[bin] += c; count[bin] += 1
            score[bin] += 0.35 + s * 1.6 + v * 0.4
        }
        return (0..<bins).filter { count[$0] >= 12 }
            .sorted { score[$0] > score[$1] }
            .prefix(5)
            .map { sum[$0] / count[$0] }
    }

    /// Tones colours for a page background: vivid but never so bright that white text stops reading,
    /// plus a deep shade of the leading colour so the blend has light and dark moving through it.
    private static func canvas(_ colours: [RGB]) -> [RGB] {
        guard let lead = colours.first else { return [] }
        var out = colours.map { c -> RGB in
            let (h, s, v) = hsv(c)
            return s < 0.15 ? rgb(h, s, min(max(v, 0.16), 0.5)) : rgb(h, min(1, max(s, 0.55)), min(max(v, 0.32), 0.74))
        }
        let (h, s, v) = hsv(out[0])
        if colours.count == 1 { out.append(rgb((h + 0.06).truncatingRemainder(dividingBy: 1), s, v * 0.8)) }
        out.append(rgb(h, min(1, s * 1.1), max(0.08, hsv(lead).2 * 0.3)))
        return out
    }

    private static func hsv(_ c: RGB) -> (Float, Float, Float) {
        let mx = c.max(), mn = c.min(), d = mx - mn
        let s = mx == 0 ? 0 : d / mx
        guard d > 0 else { return (0, s, mx) }
        var h: Float
        if mx == c.x { h = ((c.y - c.z) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.y { h = (c.z - c.x) / d + 2 }
        else { h = (c.x - c.y) / d + 4 }
        h /= 6
        return (h < 0 ? h + 1 : h, s, mx)
    }

    private static func rgb(_ h: Float, _ s: Float, _ v: Float) -> RGB {
        let i = Int(h * 6) % 6, f = h * 6 - Float(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return RGB(v, t, p)
        case 1: return RGB(q, v, p)
        case 2: return RGB(p, v, t)
        case 3: return RGB(p, q, v)
        case 4: return RGB(t, p, v)
        default: return RGB(v, p, q)
        }
    }
}
