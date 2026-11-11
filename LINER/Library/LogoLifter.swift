import UIKit
import Vision

/// Cuts an album's printed title out of its cover (see `AlbumLogoStore`). Runs off the main actor.
enum LogoLifter {
    /// A transparent PNG of the title's lettering, or nil when the title can't be found or cut out cleanly.
    static func lift(_ cover: UIImage, title: String) -> Data? {
        guard let image = cover.cgImage else { return nil }
        let wanted = normalise(plainTitle(title))
        guard wanted.count >= 2, let box = titleBox(lines(in: image), wanted: wanted) else { return nil }
        // Vision's boxes are normalised with the origin at the bottom left.
        let w = CGFloat(image.width), h = CGFloat(image.height)
        var rect = CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h)
        rect = rect.insetBy(dx: -rect.height * 0.25, dy: -rect.height * 0.22).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard rect.width > 20, rect.height > 8, let crop = image.cropping(to: rect.integral) else { return nil }
        return cutOut(crop)
    }

    /// Whether the album's name is printed on its cover (on one line, across neighbouring lines, or inside a
    /// longer line such as "ARTIST – TITLE"), however busy the background is.
    static func coverShowsTitle(_ cover: UIImage, title: String) -> Bool {
        guard let image = cover.cgImage else { return false }
        let wanted = normalise(plainTitle(title))
        guard wanted.count >= 2 else { return false }
        let found = lines(in: image)
        if titleBox(found, wanted: wanted) != nil { return true }
        return wanted.count >= 4 && found.contains { $0.text.contains(wanted) }
    }

    /// The text Vision reads on the cover, each line normalised to bare letters and digits.
    private static func lines(in image: CGImage) -> [(text: String, box: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { o in
            guard let c = o.topCandidates(1).first, c.confidence > 0.3 else { return nil }
            let t = normalise(c.string)
            return t.isEmpty ? nil : (t, o.boundingBox)
        }
    }

    /// The box round the title: one line that reads it, or neighbouring lines that spell it out together.
    private static func titleBox(_ lines: [(text: String, box: CGRect)], wanted: String) -> CGRect? {
        if let line = lines.first(where: { $0.text == wanted }) { return line.box }
        let parts = lines.filter { $0.text.count >= 2 && wanted.contains($0.text) }
            .sorted { (-($0.box.midY * 20).rounded(), $0.box.minX) < (-($1.box.midY * 20).rounded(), $1.box.minX) }
        guard parts.count > 1, parts.map(\.text).joined() == wanted else { return nil }
        return parts.dropFirst().reduce(parts[0].box) { $0.union($1.box) }
    }

    /// Lifts the lettering off a plain background: pixels far from the background colour stay, the rest go.
    static func cutOut(_ crop: CGImage) -> Data? {
        let scale = min(1, 900 / CGFloat(crop.width))
        let w = max(1, Int(CGFloat(crop.width) * scale)), h = max(1, Int(CGFloat(crop.height) * scale))
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: info) else { return false }
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        func rgb(_ i: Int) -> (Double, Double, Double) { (Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255) }

        // The background is the colour round the edge; a busy edge (a photo) means no clean cut-out.
        var edge: [(Double, Double, Double)] = []
        for x in stride(from: 0, to: w, by: 2) { edge.append(rgb(x * 4)); edge.append(rgb(((h - 1) * w + x) * 4)) }
        for y in stride(from: 0, to: h, by: 2) { edge.append(rgb(y * w * 4)); edge.append(rgb((y * w + w - 1) * 4)) }
        let n = Double(edge.count)
        let bg = edge.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.0 / n, $0.1 + $1.1 / n, $0.2 + $1.2 / n) }
        let spread = edge.reduce(0.0) { $0 + dist($1, bg) / n }
        guard spread < 0.12 else { return nil }

        var coverage = 0.0, ink = 0.0
        var alphas = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let a = min(1, max(0, (dist(rgb(i * 4), bg) - 0.12) / 0.2))
            alphas[i] = a
            coverage += a
            let c = rgb(i * 4)
            ink += a * (0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2)
        }
        let fraction = coverage / Double(w * h)
        guard fraction > 0.03, fraction < 0.6 else { return nil }
        let whiten = ink / max(coverage, 1) < 0.45
        for i in 0..<(w * h) {
            let a = alphas[i]
            let c = whiten ? (1.0, 1.0, 1.0) : rgb(i * 4)
            px[i * 4] = UInt8(c.0 * a * 255)
            px[i * 4 + 1] = UInt8(c.1 * a * 255)
            px[i * 4 + 2] = UInt8(c.2 * a * 255)
            px[i * 4 + 3] = UInt8(a * 255)
        }
        let image: CGImage? = px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: space, bitmapInfo: info)?.makeImage()
        }
        return image.flatMap { UIImage(cgImage: $0).pngData() }
    }

    private static func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
    }

    /// The title without "(Deluxe Edition)", "[Remastered]", " - Single" and the like.
    private static func plainTitle(_ title: String) -> String {
        var t = title
        for suffix in [" - Single", " - EP"] where t.hasSuffix(suffix) { t = String(t.dropLast(suffix.count)) }
        if let r = t.range(of: #"\s*[\(\[].*$"#, options: .regularExpression) { t.removeSubrange(r) }
        return t
    }

    private static func normalise(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }
}
