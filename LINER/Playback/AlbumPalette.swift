import SwiftUI
import UIKit

/// An album's page colours, picked from its cover the way iTunes 11 and the old Music app did: the background
/// is the most common colour along the cover's edges (so the art melts into the page), and the text colours
/// are the most common colours inside the cover that stay readable on it. LINER. goes further and keeps
/// things colourful: a black, white or grey edge gives way to the cover's strongest colour, deepened.
struct AlbumColours: Sendable, Equatable {
    var background: Color
    /// Titles and song names.
    var primary: Color
    /// Artist, numbers, durations and labels.
    var secondary: Color
    /// The song that's playing, buttons and highlights.
    var accent: Color
    /// The cover's main colours, strongest first, for moving backgrounds.
    var swatches: [Color]
    var isDark: Bool

    static let black = AlbumColours(background: .black, primary: .white, secondary: Color.white.opacity(0.55),
                                    accent: .white, swatches: [Color(white: 0.2), Color(white: 0.08)], isDark: true)
}

enum AlbumPalette {
    nonisolated(unsafe) private static var cache: [String: AlbumColours] = [:]
    private static let lock = NSLock()

    /// What Settings → Covers → Album colours asks for.
    enum Mode: String, CaseIterable, Sendable {
        case coloured, tinted, black
        var label: String { switch self { case .coloured: "Coloured"; case .tinted: "Tinted"; case .black: "Black" } }
        static var current: Mode { Mode(rawValue: UserDefaults.standard.string(forKey: "albumColours") ?? "") ?? .coloured }
    }

    static func cached(_ key: String) -> AlbumColours? { lock.withLock { cache[key] } }

    @concurrent
    static func colours(for image: UIImage, key: String) async -> AlbumColours {
        if let hit = lock.withLock({ cache[key] }) { return hit }
        let result = pick(image) ?? .black
        lock.withLock { cache[key] = result }
        return result
    }

    // MARK: Picking

    private struct RGB: Hashable {
        var r, g, b: Double
        var luminance: Double {
            func ch(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
        }
        var hsb: (h: Double, s: Double, v: Double) {
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            return (Double(h), Double(s), Double(v))
        }
        var color: Color { Color(red: r, green: g, blue: b) }
        func distance(_ o: RGB) -> Double { sqrt(pow(r - o.r, 2) * 2 + pow(g - o.g, 2) * 4 + pow(b - o.b, 2) * 3) / 3 }
        func contrast(_ o: RGB) -> Double {
            let a = luminance, b = o.luminance
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        static func hsb(_ h: Double, _ s: Double, _ v: Double) -> RGB {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(hue: h, saturation: min(1, max(0, s)), brightness: min(1, max(0, v)), alpha: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
            return RGB(r: Double(r), g: Double(g), b: Double(b))
        }
    }

    /// Pixels grouped into similar colours: (average colour, how many).
    private static func buckets(_ px: [RGB]) -> [(RGB, Int)] {
        var sums: [Int: (Double, Double, Double, Int)] = [:]
        for p in px {
            let k = Int(p.r * 15.99) << 8 | Int(p.g * 15.99) << 4 | Int(p.b * 15.99)
            let s = sums[k] ?? (0, 0, 0, 0)
            sums[k] = (s.0 + p.r, s.1 + p.g, s.2 + p.b, s.3 + 1)
        }
        var list = sums.values.map { (RGB(r: $0.0 / Double($0.3), g: $0.1 / Double($0.3), b: $0.2 / Double($0.3)), $0.3) }
            .sorted { $0.1 > $1.1 }
        // Merge near neighbours so one colour isn't split across buckets.
        var merged: [(RGB, Int)] = []
        for (c, n) in list {
            if let k = merged.firstIndex(where: { $0.0.distance(c) < 0.07 }) { merged[k].1 += n } else { merged.append((c, n)) }
        }
        list = merged.sorted { $0.1 > $1.1 }
        return list
    }

    private static func pick(_ image: UIImage) -> AlbumColours? {
        guard let cg = image.cgImage else { return nil }
        let side = 48
        var raw = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &raw, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        func px(_ x: Int, _ y: Int) -> RGB {
            let i = (y * side + x) * 4
            return RGB(r: Double(raw[i]) / 255, g: Double(raw[i + 1]) / 255, b: Double(raw[i + 2]) / 255)
        }
        var all: [RGB] = [], edge: [RGB] = []
        for y in 0..<side { for x in 0..<side {
            let p = px(x, y)
            all.append(p)
            // Rows are top-down in this buffer: the last rows are the bottom of the cover.
            if x < 3 || x >= side - 3 || y >= side - 4 { edge.append(p) }
        } }
        let colours = buckets(all)
        let vivid = colours.filter { $0.0.hsb.s > 0.28 && $0.0.hsb.v > 0.18 && Double($0.1) / Double(all.count) > 0.015 }

        var bg = buckets(edge).first?.0 ?? RGB(r: 0, g: 0, b: 0)
        let edgeHSB = bg.hsb
        // Keep it colourful: a black, white or grey edge takes the cover's strongest colour instead.
        if edgeHSB.s < 0.18, let strong = vivid.first?.0 {
            let h = strong.hsb
            bg = .hsb(h.h, max(0.55, h.s), edgeHSB.v > 0.75 ? 0.82 : 0.3)
        } else if edgeHSB.s < 0.18 {
            bg = edgeHSB.v > 0.75 ? RGB(r: 0.93, g: 0.92, b: 0.9) : RGB(r: 0.07, g: 0.07, b: 0.075)
        }
        let dark = bg.luminance < 0.4

        let candidates = colours.map(\.0).filter { $0.distance(bg) > 0.2 }
        func fallback(_ strength: Double) -> RGB {
            let h = bg.hsb
            return dark ? .hsb(h.h, 0.18 * strength, 1) : .hsb(h.h, 0.85, 0.18 + 0.12 * (1 - strength))
        }
        let primary = candidates.first { $0.contrast(bg) >= 4.5 } ?? fallback(0.6)
        let secondary = candidates.first { $0.contrast(bg) >= 3 && $0.distance(primary) > 0.15 }
            ?? mix(primary, bg, 0.35)
        let accent = candidates.filter { $0.contrast(bg) >= 3 }.max { $0.hsb.s < $1.hsb.s }.flatMap { $0.hsb.s > 0.3 ? $0 : nil }
            ?? (dark ? .hsb(bg.hsb.h, 0.45, 1) : .hsb(bg.hsb.h, 1, 0.45))

        var swatches = vivid.prefix(5).map { c -> Color in
            let h = c.0.hsb
            return RGB.hsb(h.h, min(1, h.s * 1.15), max(0.35, h.v)).color
        }
        if swatches.count < 3 { swatches += [bg.color, mix(bg, accent, 0.5).color, accent.color].prefix(3 - swatches.count) }
        return AlbumColours(background: bg.color, primary: primary.color, secondary: secondary.color, accent: accent.color,
                            swatches: swatches, isDark: dark)
    }

    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }
}

extension AlbumColours {
    /// Tinted: a black page with the cover's colours on the words.
    var tinted: AlbumColours {
        let bright = (swatches.first ?? accent).mix(with: .white, by: 0.2)
        var c = self
        c.background = .black
        c.primary = .white
        c.secondary = bright.opacity(0.8)
        c.accent = bright
        c.isDark = true
        return c
    }
}

extension EnvironmentValues {
    /// Set by a coloured album page, so its song rows draw in the album's colours.
    @Entry var albumColours: AlbumColours? = nil
}
