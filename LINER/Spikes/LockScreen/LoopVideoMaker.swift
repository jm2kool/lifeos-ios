@preconcurrency import AVFoundation
import UIKit

/// A tiny Living Cover (SPEC §6.9 mode A) for the spikes: slow zoom and drift that loops seamlessly.
/// Draws the cover aspect-filled into any size, so it works for 3:4, 1:1 and 9:16.
enum LoopVideoMaker {
    struct Output: Sendable {
        let video: URL
        /// Exactly the first frame, at the same aspect ratio, as the lock screen needs.
        let preview: UIImage
    }

    static var folder: URL {
        let dir = URL.cachesDirectory.appending(path: "LINERSpike", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @concurrent
    static func make(from image: UIImage, width: Int, height: Int, seconds: Double = 8, fps: Int32 = 30, name: String) async throws -> Output {
        guard let cg = image.cgImage else { throw SpikeError("Cover has no bitmap") }
        let url = folder.appending(path: "\(name).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw SpikeError("Writer: \(writer.error?.localizedDescription ?? "?")") }
        writer.startSession(atSourceTime: .zero)

        let frames = Int(seconds * Double(fps))
        for f in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(4)) }
            guard let pool = adaptor.pixelBufferPool else { throw SpikeError("No pixel buffer pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw SpikeError("No pixel buffer") }
            draw(cg, into: buffer, width: width, height: height, phase: Double(f) / Double(frames))
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw SpikeError("Writer ended \(writer.status.rawValue): \(writer.error?.localizedDescription ?? "?")") }

        let preview = previewImage(cg, width: width, height: height)
        return Output(video: url, preview: preview)
    }

    /// Phase 0…1 around the loop. Both zoom and drift come back to where they started, so there's no jump.
    private static func transform(phase: Double, width: Int, height: Int) -> (scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        let angle = phase * 2 * .pi
        let zoom = 1.0 + 0.06 * (0.5 - 0.5 * cos(angle))
        let dx = 0.015 * Double(width) * sin(angle)
        let dy = 0.010 * Double(height) * sin(angle * 2) * 0.5
        return (zoom, dx, dy)
    }

    private static func fillRect(for cg: CGImage, width: Int, height: Int, phase: Double) -> CGRect {
        let w = CGFloat(width), h = CGFloat(height)
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let t = transform(phase: phase, width: width, height: height)
        let base = max(w / iw, h / ih) * t.scale
        let dw = iw * base, dh = ih * base
        // Centred horizontally; vertically biased up a little so faces near the top stay in frame.
        return CGRect(x: (w - dw) / 2 + t.dx, y: (h - dh) * 0.4 + t.dy, width: dw, height: dh)
    }

    private static func draw(_ cg: CGImage, into buffer: CVPixelBuffer, width: Int, height: Int, phase: Double) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: fillRect(for: cg, width: width, height: height, phase: phase))
    }

    private static func previewImage(_ cg: CGImage, width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { r in
            let ctx = r.cgContext
            // UIKit's context is top-left origin; flip so the rect math matches the CoreGraphics video frames.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.draw(cg, in: fillRect(for: cg, width: width, height: height, phase: 0))
        }
    }

    /// A stand-in cover when the test song has no artwork.
    @MainActor static func placeholderCover(title: String) -> UIImage {
        let size = CGSize(width: 1200, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { r in
            let colors = [UIColor(red: 0.95, green: 0.35, blue: 0.2, alpha: 1).cgColor, UIColor(red: 0.15, green: 0.1, blue: 0.4, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            r.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let text = NSAttributedString(string: title, attributes: [
                .font: UIFont(descriptor: UIFont.systemFont(ofSize: 150).fontDescriptor.withDesign(.serif)!, size: 150),
                .foregroundColor: UIColor.white,
            ])
            text.draw(at: CGPoint(x: 80, y: size.height - 280))
        }
    }
}

/// A plain error with a message, for spike logs.
struct SpikeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
