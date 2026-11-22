import CoreText
import UIKit
@preconcurrency import Vision

/// Finds the font on the iPhone that looks most like a logo you added: it reads the logo's words, draws those
/// words in every font (and the system designs in several weights), and keeps the one whose letter shapes, width
/// and stroke weight come closest. Logos without readable words get no match.
enum FontMatcher {
    /// The closest font for this logo, ready to use as the album's font, or nil when the logo has no words.
    static func match(png: Data) async -> AlbumFace? {
        await Task.detached(priority: .userInitiated) { bestFace(png) }.value
    }

    // MARK: Matching

    private struct Candidate {
        let family: String
        let weight: Int
        let font: CTFont
    }

    /// The size every comparison is drawn at: wide and short, like a line of lettering.
    private static let gridW = 120, gridH = 28

    private static func bestFace(_ png: Data) -> AlbumFace? {
        guard let image = UIImage(data: png)?.cgImage, let ink = InkImage(image), let found = readWords(ink),
              let target = ink.cropped(to: found.box) else { return nil }
        let words = found.words
        let text = String(words.prefix(24))
        let targetGrid = target.grid(gridW, gridH)
        let targetAspect = target.aspect
        var best: (score: Double, candidate: Candidate)?
        for c in candidates() where covers(c.font, text) {
            guard let drawn = InkImage(text: text, font: c.font) else { continue }
            let score = distance(targetGrid, drawn.grid(gridW, gridH), aspectA: targetAspect, aspectB: drawn.aspect,
                                 densityA: target.density, densityB: drawn.density)
            if score < (best?.score ?? .infinity) { best = (score, c) }
        }
        guard let best else { return nil }
        var face = AlbumFace(family: best.candidate.family)
        face.weight = best.candidate.weight
        face.caps = caps(of: words)
        return face
    }

    /// Lower is closer: how much the letter shapes differ, plus how far apart width and stroke weight are.
    private static func distance(_ a: [Float], _ b: [Float], aspectA: Double, aspectB: Double,
                                             densityA: Double, densityB: Double) -> Double {
        var both: Float = 0, either: Float = 0
        for i in a.indices { both += min(a[i], b[i]); either += max(a[i], b[i]) }
        let shape = either > 0 ? 1 - Double(both / either) : 1
        return shape + 0.5 * abs(log(aspectA / max(aspectB, 0.01))) + 2.5 * abs(densityA - densityB)
    }

    /// The logo's biggest line of words and where it sits, read by Vision.
    private static func readWords(_ ink: InkImage) -> (words: String, box: CGRect)? {
        guard let cg = ink.blackOnWhite() else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        let lines = (request.results ?? []).compactMap { obs -> (String, CGRect)? in
            guard let s = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces), s.count >= 2 else { return nil }
            let r = obs.boundingBox
            // Vision's boxes start at the bottom left.
            return (s, CGRect(x: r.minX * Double(ink.width), y: (1 - r.maxY) * Double(ink.height),
                              width: r.width * Double(ink.width), height: r.height * Double(ink.height)))
        }
        guard let biggest = lines.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else { return nil }
        return (biggest.0, biggest.1)
    }

    private static func caps(of words: String) -> AlbumFace.Caps {
        let letters = words.filter(\.isLetter)
        guard letters.count >= 2 else { return .normal }
        if letters.allSatisfy(\.isUppercase) { return .upper }
        if letters.allSatisfy(\.isLowercase) { return .lower }
        return .normal
    }

    /// Every upright font on the iPhone (and the ones you imported), plus the system designs in five weights.
    private static func candidates() -> [Candidate] {
        var list: [Candidate] = []
        let designs: [(String, UIFontDescriptor.SystemDesign)] = [(AlbumFace.systemSans, .default), (AlbumFace.systemSerif, .serif),
                                                                  (AlbumFace.systemRounded, .rounded), (AlbumFace.systemMono, .monospaced)]
        for (name, design) in designs {
            for index in [1, 3, 5, 6, 8] {
                let base = UIFont.systemFont(ofSize: 60, weight: uiWeights[index])
                let font = base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: 60) } ?? base
                list.append(Candidate(family: name, weight: index, font: font as CTFont))
            }
        }
        for family in UIFont.familyNames where !family.hasPrefix(".") && !skipped.contains(where: { family.contains($0) }) {
            var seen = Set<Int>()
            for name in UIFont.fontNames(forFamilyName: family) {
                let font = CTFontCreateWithName(name as CFString, 60, nil)
                guard !CTFontGetSymbolicTraits(font).contains(.traitItalic) else { continue }
                let index = weightIndex(font)
                // SwiftUI picks a family's face by weight, so one face per weight is all that can be chosen.
                guard seen.insert(index).inserted else { continue }
                list.append(Candidate(family: family, weight: index, font: font))
            }
        }
        return list
    }

    /// Symbol and emoji families, which never look like lettering.
    private static let skipped = ["Emoji", "Dingbats", "Ornaments", "Symbol", "Webdings", "Wingdings"]

    private static var uiWeights: [UIFont.Weight] { [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black] }

    /// The nearest of `AlbumFace.weights` for a font face.
    private static func weightIndex(_ font: CTFont) -> Int {
        let traits = CTFontCopyTraits(font) as NSDictionary
        let w = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
        let values = uiWeights.map { Double($0.rawValue) }
        return values.indices.min { abs(values[$0] - w) < abs(values[$1] - w) } ?? 3
    }

    /// Whether the font has its own letters for all of the text (no stand-ins from another font).
    private static func covers(_ font: CTFont, _ text: String) -> Bool {
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        return CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
    }
}

/// A picture as "ink": how much lettering covers each pixel, 0…1.
private struct InkImage {
    let width: Int, height: Int
    var pixels: [Float]

    init(width: Int, height: Int, pixels: [Float]) {
        self.width = width; self.height = height; self.pixels = pixels
    }

    /// A logo: its opaque parts, or, when it has no transparency, whatever differs from the colour in its corners.
    init?(_ image: CGImage) {
        let scale = min(1, 700 / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drew = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { Float(rgba[$0]) / 255 }
        let clear = alpha.filter { $0 < 0.5 }.count
        if Double(clear) > Double(alpha.count) * 0.05 {
            self.init(width: w, height: h, pixels: alpha)
        } else {
            func lum(_ i: Int) -> Float { (0.3 * Float(rgba[i * 4]) + 0.59 * Float(rgba[i * 4 + 1]) + 0.11 * Float(rgba[i * 4 + 2])) / 255 }
            let corners = [0, w - 1, (h - 1) * w, h * w - 1].map(lum)
            let bg = corners.reduce(0, +) / 4
            self.init(width: w, height: h, pixels: (0..<(w * h)).map { min(1, max(0, (abs(lum($0) - bg) - 0.1) * 3)) })
        }
        guard pixels.contains(where: { $0 > 0.5 }) else { return nil }
    }

    /// Text drawn in a font.
    init?(text: String, font: CTFont) {
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let w = Int(bounds.width) + 8, h = Int(bounds.height) + 8
        var gray = [UInt8](repeating: 0, count: w * h)
        let drew = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.textPosition = CGPoint(x: 4 - bounds.minX, y: 4 - bounds.minY)
            CTLineDraw(line, ctx)
            return true
        }
        guard drew else { return nil }
        self.init(width: w, height: h, pixels: gray.map { Float($0) / 255 })
    }

    /// Width over height of the inked area.
    var aspect: Double { Double(width) / Double(max(height, 1)) }

    /// How much of the inked area is ink: thin strokes are low, heavy ones high.
    var density: Double { Double(pixels.reduce(0, +)) / Double(max(pixels.count, 1)) }

    /// The ink inside a box (in pixels from the top left), trimmed to where the ink starts and ends.
    func cropped(to box: CGRect) -> InkImage? {
        let x0 = max(0, Int(box.minX) - 2), x1 = min(width, Int(box.maxX) + 2)
        let y0 = max(0, Int(box.minY) - 2), y1 = min(height, Int(box.maxY) + 2)
        var minX = x1, maxX = x0 - 1, minY = y1, maxY = y0 - 1
        for y in y0..<max(y0, y1) { for x in x0..<max(x0, x1) where pixels[y * width + x] > 0.5 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX > minX, maxY > minY else { return nil }
        let w = maxX - minX + 1, h = maxY - minY + 1
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { out[y * w + x] = pixels[(y + minY) * width + x + minX] } }
        return InkImage(width: w, height: h, pixels: out)
    }

    /// The ink squeezed into a small grid, each cell the average of the pixels it covers.
    func grid(_ gw: Int, _ gh: Int) -> [Float] {
        var cells = [Float](repeating: 0, count: gw * gh), counts = [Float](repeating: 0, count: gw * gh)
        for y in 0..<height {
            let gy = min(gh - 1, y * gh / height)
            for x in 0..<width {
                let i = gy * gw + min(gw - 1, x * gw / width)
                cells[i] += pixels[y * width + x]; counts[i] += 1
            }
        }
        return zip(cells, counts).map { $1 > 0 ? $0 / $1 : 0 }
    }

    /// Black lettering on white, which Vision reads best whatever colour the logo is.
    func blackOnWhite() -> CGImage? {
        var gray = pixels.map { UInt8(255 - min(255, max(0, $0 * 255))) }
        return gray.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
    }
}
