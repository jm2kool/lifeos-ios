import SwiftUI
import UIKit

/// Pulls the colours out of a poster: the dominant vibrant "accent" plus a small palette.
struct PosterPalette: Equatable {
    var accent: Color
    var colors: [Color]
    var accentUI: UIColor
    var uiColors: [UIColor] = []

    /// A version of the accent dark enough that white text on top always reads well.
    var background: Color { Color(uiColor: accentUI.adjusted(maxBrightness: 0.36, minSaturation: 0.35)) }
    /// A slightly lighter tone for cards sitting on the background.
    var surface: Color { Color(uiColor: accentUI.adjusted(maxBrightness: 0.5, minSaturation: 0.3)).opacity(0.55) }
    /// A vivid version of the accent for glows behind posters and pages.
    var glow: Color { Color(uiColor: accentUI.adjusted(maxBrightness: 0.95, minSaturation: 0.5, minBrightness: 0.55)) }
    /// A bright tint for highlights (stars, links) on the background.
    var highlight: Color { Color(uiColor: accentUI.adjusted(maxBrightness: 1, minSaturation: 0.45, minBrightness: 0.85)) }
}

@MainActor
enum Palette {
    private static var cache: [URL: PosterPalette] = [:]

    static func cached(_ url: URL?) -> PosterPalette? { url.flatMap { cache[$0] } }

    static func of(_ url: URL?) async -> PosterPalette? {
        guard let url else { return nil }
        if let hit = cache[url] { return hit }
        guard let img = await ImageStore.shared.load(url), let cg = img.cgImage else { return nil }
        let swatches = await Task.detached(priority: .userInitiated) { Palette.extract(cg) }.value
        guard let first = swatches.first else { return nil }
        let accent = swatches.first { $0.saturation > 0.28 && $0.brightness > 0.2 } ?? first
        let p = PosterPalette(accent: Color(uiColor: accent.ui), colors: swatches.map { Color(uiColor: $0.ui) }, accentUI: accent.ui,
                              uiColors: [accent.ui] + swatches.filter { !($0.r == accent.r && $0.g == accent.g && $0.b == accent.b) }.map(\.ui))
        cache[url] = p
        return p
    }

    struct Swatch: Sendable {
        var r: Double, g: Double, b: Double, weight: Double
        var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        var saturation: Double { let mx = max(r, g, b), mn = min(r, g, b); return mx == 0 ? 0 : (mx - mn) / mx }
        var brightness: Double { max(r, g, b) }
    }

    /// Downsample, bucket pixels by hue, and rank buckets by how much — and how vividly — they appear.
    nonisolated static func extract(_ image: CGImage) -> [Swatch] {
        let w = 36, h = 54
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return [] }

        let bins = 13   // 12 hues + 1 neutral
        var acc = Array(repeating: (r: 0.0, g: 0.0, b: 0.0, n: 0.0, score: 0.0), count: bins)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            if mx < 0.1 { continue }                         // skip near-black
            let s = mx == 0 ? 0 : (mx - mn) / mx
            if s < 0.08 && mx > 0.92 { continue }            // skip near-white
            var hue = 0.0
            if mx != mn {
                let d = mx - mn
                if mx == r { hue = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
                else if mx == g { hue = (b - r) / d + 2 }
                else { hue = (r - g) / d + 4 }
                hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
            }
            let bin = s < 0.18 ? 12 : Int(hue / 30) % 12
            acc[bin].r += r; acc[bin].g += g; acc[bin].b += b; acc[bin].n += 1
            acc[bin].score += 0.35 + s * 1.6 + mx * 0.4
        }
        return acc.filter { $0.n > 4 }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map { Swatch(r: $0.r / $0.n, g: $0.g / $0.n, b: $0.b / $0.n, weight: $0.score) }
    }
}

extension Palette {
    /// True when a logo is mostly dark ink (made for light backgrounds), so we can draw it white instead.
    nonisolated static func isDark(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return false }
        var lum = 0.0, weight = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255
            guard a > 0.3 else { continue }
            let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
            lum += (0.299 * r + 0.587 * g + 0.114 * b) * a
            weight += a
        }
        // Anything that isn't already light gets drawn white, so it reads on poster-coloured backgrounds.
        return weight > 0 && lum / weight < 0.58
    }
}

@MainActor
enum Screen {
    /// The top safe-area inset (status bar / Dynamic Island) of the key window.
    static var safeTop: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }?.safeAreaInsets.top ?? 59
    }
}

extension UIColor {
    func adjusted(maxBrightness: CGFloat, minSaturation: CGFloat, minBrightness: CGFloat = 0.12) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s < 0.08 ? s : max(s, minSaturation), brightness: min(max(b, minBrightness), maxBrightness), alpha: 1)
    }
}

extension FilmRef {
    /// A big version of the poster for full-screen use.
    var largePoster: URL? {
        guard let p = poster?.absoluteString else { return nil }
        if p.contains("image.tmdb.org") { return URL(string: p.replacingOccurrences(of: "/w500/", with: "/original/")) }
        return poster
    }
}
