import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import Vision

/// Colours and the point of interest of a cover, worked out once per cover and cached.
struct ArtworkLook: Sendable, Equatable {
    var dominant: Color
    var secondary: Color
    /// Where the subject is, in unit coordinates (0,0 top-left). Used to aim aspect-fill crops.
    var focus: CGPoint

    static let neutral = ArtworkLook(dominant: Color(white: 0.2), secondary: Color(white: 0.08), focus: CGPoint(x: 0.5, y: 0.4))
}

enum ArtworkAnalysis {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    nonisolated(unsafe) private static var cache: [String: ArtworkLook] = [:]
    private static let lock = NSLock()

    @concurrent
    static func look(for image: UIImage, key: String) async -> ArtworkLook {
        if let hit = lock.withLock({ cache[key] }) { return hit }
        guard let cg = image.cgImage else { return .neutral }
        let ci = CIImage(cgImage: cg)
        let e = ci.extent
        // Dominant: the whole image; secondary: the bottom third, which sits behind the controls.
        let dominant = average(ci, e) ?? Color(white: 0.2)
        let secondary = average(ci, CGRect(x: e.minX, y: e.minY, width: e.width, height: e.height / 3)) ?? Color(white: 0.08)
        let result = ArtworkLook(dominant: dominant, secondary: secondary, focus: focus(cg))
        lock.withLock { cache[key] = result }
        return result
    }

    private static func average(_ image: CIImage, _ rect: CGRect) -> Color? {
        let f = CIFilter.areaAverage()
        f.inputImage = image
        f.extent = rect
        guard let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return Color(red: Double(px[0]) / 255, green: Double(px[1]) / 255, blue: Double(px[2]) / 255)
    }

    /// Vision's attention saliency: the centre of the salient regions (faces and subjects draw attention).
    private static func focus(_ cg: CGImage) -> CGPoint {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        guard (try? handler.perform([request])) != nil,
              let boxes = request.results?.first?.salientObjects, !boxes.isEmpty else { return ArtworkLook.neutral.focus }
        let union = boxes.map(\.boundingBox).reduce(boxes[0].boundingBox) { $0.union($1) }
        // Vision is bottom-left origin; flip to top-left. Bias up a little towards faces.
        return CGPoint(x: union.midX, y: max(0, min(1, 1 - union.midY - union.height * 0.15)))
    }
}

/// An image that fills its frame (never letterboxed), with the crop aimed at a focus point.
struct FocusedFillImage: View {
    let image: UIImage
    var focus = CGPoint(x: 0.5, y: 0.4)

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            let s = max(box.width / max(image.size.width, 1), box.height / max(image.size.height, 1))
            let w = image.size.width * s, h = image.size.height * s
            let x = clamp(box.width / 2 - focus.x * w, lower: box.width - w)
            let y = clamp(box.height * 0.42 - focus.y * h, lower: box.height - h)
            Image(uiImage: image).resizable().frame(width: w, height: h).offset(x: x, y: y)
        }
        .clipped()
    }

    private func clamp(_ v: CGFloat, lower: CGFloat) -> CGFloat { min(0, max(lower, v)) }
}
