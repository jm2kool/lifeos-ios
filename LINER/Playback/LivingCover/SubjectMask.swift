import CoreImage
import UIKit
import Vision

/// Lifts the subject (people, objects) off a cover with Vision's foreground instance mask, for Living Cover mode B.
enum SubjectMask {
    private static let context = CIContext()
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    /// The cover with everything but the subject made transparent, same size as the input; nil if no subject.
    @concurrent
    static func cutout(_ image: UIImage, key: String) async -> UIImage? {
        if let hit = lock.withLock({ cache[key] }) { return hit }
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        guard (try? handler.perform([request])) != nil, let obs = request.results?.first,
              let buffer = try? obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let out = context.createCGImage(ci, from: ci.extent) else { return nil }
        let result = UIImage(cgImage: out)
        lock.withLock { cache[key] = result }
        return result
    }
}
