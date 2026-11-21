import CoreImage
import UIKit
import Vision

/// Gets a logo you picked ready to use: made a sensible size, its background taken away if you asked (a plain
/// background by colour, anything busier with on-device subject lifting), and trimmed to the lettering.
enum LogoCleaner {
    /// A PNG with transparency, or nil when the image can't be read.
    static func prepare(_ data: Data, removeBackground: Bool) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let source = UIImage(data: data), let cg = scaled(source, longest: 1400) else { return nil }
            var image = cg
            if removeBackground, !hasTransparency(cg) {
                image = plainCutOut(cg) ?? subjectCutOut(cg) ?? cg
            }
            return UIImage(cgImage: trimmed(image) ?? image).pngData()
        }.value
    }

    private static func scaled(_ image: UIImage, longest: CGFloat) -> CGImage? {
        let s = min(1, longest / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, (image.size.width * s).rounded()), height: max(1, (image.size.height * s).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }

    private struct Pixels {
        var data: [UInt8]
        let w: Int, h: Int
        func rgba(_ i: Int) -> (Double, Double, Double, Double) {
            (Double(data[i * 4]) / 255, Double(data[i * 4 + 1]) / 255, Double(data[i * 4 + 2]) / 255, Double(data[i * 4 + 3]) / 255)
        }
    }

    private static func pixels(_ image: CGImage) -> Pixels? {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Pixels(data: px, w: w, h: h) : nil
    }

    private static func image(_ p: Pixels) -> CGImage? {
        var data = p.data
        return data.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: p.w, height: p.h, bitsPerComponent: 8, bytesPerRow: p.w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    private static func hasTransparency(_ image: CGImage) -> Bool {
        guard let p = pixels(image) else { return false }
        var clear = 0
        for i in stride(from: 0, to: p.w * p.h, by: 7) where p.data[i * 4 + 3] < 250 { clear += 1 }
        return clear > (p.w * p.h / 7) / 50
    }

    /// Removes a plain background (the colour round the edge), keeping the lettering's own colours. Nil when the
    /// edge is too busy to be a plain background.
    private static func plainCutOut(_ cg: CGImage) -> CGImage? {
        guard var p = pixels(cg) else { return nil }
        let w = p.w, h = p.h
        var edge: [(Double, Double, Double)] = []
        for x in stride(from: 0, to: w, by: 3) {
            let a = p.rgba(x), b = p.rgba((h - 1) * w + x)
            edge.append((a.0, a.1, a.2)); edge.append((b.0, b.1, b.2))
        }
        for y in stride(from: 0, to: h, by: 3) {
            let a = p.rgba(y * w), b = p.rgba(y * w + w - 1)
            edge.append((a.0, a.1, a.2)); edge.append((b.0, b.1, b.2))
        }
        let n = Double(edge.count)
        let bg = edge.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.0 / n, $0.1 + $1.1 / n, $0.2 + $1.2 / n) }
        func dist(_ a: (Double, Double, Double)) -> Double {
            ((a.0 - bg.0) * (a.0 - bg.0) + (a.1 - bg.1) * (a.1 - bg.1) + (a.2 - bg.2) * (a.2 - bg.2)).squareRoot()
        }
        guard edge.reduce(0.0, { $0 + dist($1) / n }) < 0.14 else { return nil }
        for i in 0..<(w * h) {
            let c = p.rgba(i)
            let a = min(1, max(0, (dist((c.0, c.1, c.2)) - 0.08) / 0.18))
            // Un-mix the background from soft edges so they don't keep a halo of it.
            func channel(_ v: Double, _ b: Double) -> UInt8 {
                let pure = a > 0.01 ? min(1, max(0, (v - b * (1 - a)) / a)) : 0
                return UInt8((pure * a * 255).rounded())
            }
            p.data[i * 4] = channel(c.0, bg.0)
            p.data[i * 4 + 1] = channel(c.1, bg.1)
            p.data[i * 4 + 2] = channel(c.2, bg.2)
            p.data[i * 4 + 3] = UInt8((a * 255).rounded())
        }
        return image(p)
    }

    /// Lifts the subject off a busy background, the way Photos does.
    private static func subjectCutOut(_ cg: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        guard (try? handler.perform([request])) != nil, let result = request.results?.first,
              let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ci, from: ci.extent)
    }

    /// Crops away fully transparent edges, leaving a little room.
    private static func trimmed(_ cg: CGImage) -> CGImage? {
        guard let p = pixels(cg) else { return nil }
        var minX = p.w, minY = p.h, maxX = -1, maxY = -1
        for y in 0..<p.h {
            for x in 0..<p.w where p.data[(y * p.w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad = 4
        let rect = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                          width: min(p.w, maxX + pad + 1) - max(0, minX - pad), height: min(p.h, maxY + pad + 1) - max(0, minY - pad))
        return cg.cropping(to: rect)
    }
}
