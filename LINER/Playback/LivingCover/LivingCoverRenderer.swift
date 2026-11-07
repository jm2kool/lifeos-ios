@preconcurrency import AVFoundation
import UIKit

/// Living Covers (SPEC §6.9): an 8 s seamless 30 fps loop made from a still cover, for the lock screen and
/// share cards. Mode A drifts and zooms; mode B lifts the subject with gentle parallax and a slow light sweep.
/// Cached per album in Application Support/LINER/LivingCovers with a 300 MB LRU cap.
enum LivingCoverRenderer {
    enum Aspect: String, Sendable {
        case tall, square, story
        var size: (Int, Int) {
            switch self {
            case .tall: (1080, 1440)
            case .square: (1080, 1080)
            case .story: (1080, 1920)
            }
        }
    }

    enum Style: String, CaseIterable, Sendable {
        case drift, lift
        var label: String { self == .drift ? "Drift (slow zoom)" : "Lift (subject parallax)" }
        static var current: Style { Style(rawValue: UserDefaults.standard.string(forKey: "livingCoverStyle") ?? "") ?? .drift }
    }

    static var folder: URL {
        var dir = URL.applicationSupportDirectory.appending(path: "LINER/LivingCovers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    static func fileName(key: String, aspect: Aspect, style: Style) -> String { "living-\(style.rawValue)-\(aspect.rawValue)-\(key).mp4" }

    /// The cached video if it exists (touching it for the LRU).
    static func cached(key: String, aspect: Aspect, style: Style = .current) -> URL? {
        let url = folder.appending(path: fileName(key: key, aspect: aspect, style: style))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: url.path)
        return url
    }

    /// Makes (or returns the cached) Living Cover.
    @concurrent
    static func video(for image: UIImage, key: String, aspect: Aspect, style: Style = .current) async -> URL? {
        if let hit = cached(key: key, aspect: aspect, style: style) { return hit }
        guard let cg = image.cgImage else { return nil }
        let cut = style == .lift ? await SubjectMask.cutout(image, key: key)?.cgImage : nil
        let (w, h) = aspect.size
        let url = folder.appending(path: fileName(key: key, aspect: aspect, style: style))
        let ok = await VideoLoopWriter.write(to: url, width: w, height: h) { ctx, phase in
            draw(ctx, cover: cg, subject: cut, width: w, height: h, phase: phase)
        }
        guard ok else { return nil }
        evict()
        return url
    }

    /// The exact first frame, same aspect ratio: the lock screen's preview image.
    static func preview(for image: UIImage, aspect: Aspect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let (w, h) = aspect.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { r in
            let ctx = r.cgContext
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            draw(ctx, cover: cg, subject: nil, width: w, height: h, phase: 0)
        }
    }

    // MARK: Drawing (CoreGraphics, bottom-left origin)

    private static func draw(_ ctx: CGContext, cover: CGImage, subject: CGImage?, width: Int, height: Int, phase: Double) {
        let angle = phase * 2 * .pi
        let ease = 0.5 - 0.5 * cos(angle)               // 0 → 1 → 0, seamless
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        if let subject {
            // Background drifts one way, subject the other: a gentle depth effect.
            ctx.draw(cover, in: fill(cover, width, height, zoom: 1.04 + 0.03 * ease, dx: -0.012 * sin(angle), dy: 0))
            ctx.draw(subject, in: fill(subject, width, height, zoom: 1.04 + 0.05 * ease, dx: 0.012 * sin(angle), dy: 0.006 * ease))
            sweep(ctx, width: width, height: height, phase: phase)
        } else {
            ctx.draw(cover, in: fill(cover, width, height, zoom: 1.0 + 0.06 * ease, dx: 0.015 * sin(angle), dy: 0.005 * sin(2 * angle)))
        }
    }

    /// Aspect-fill rect, centred, biased so the upper part (faces) stays in frame. dx/dy are fractions of the frame.
    private static func fill(_ img: CGImage, _ w: Int, _ h: Int, zoom: Double, dx: Double, dy: Double) -> CGRect {
        let W = CGFloat(w), H = CGFloat(h)
        let s = max(W / CGFloat(img.width), H / CGFloat(img.height)) * zoom
        let dw = CGFloat(img.width) * s, dh = CGFloat(img.height) * s
        return CGRect(x: (W - dw) / 2 + dx * W, y: (H - dh) * 0.4 + dy * H, width: dw, height: dh)
    }

    /// A soft diagonal light band crossing once per loop, fading in and out so the loop stays seamless.
    private static func sweep(_ ctx: CGContext, width: Int, height: Int, phase: Double) {
        let strength = 0.10 * sin(phase * .pi)
        guard strength > 0.005 else { return }
        let x = CGFloat(phase) * CGFloat(width) * 1.6 - CGFloat(width) * 0.3
        let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: strength).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.5, 1]) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.drawLinearGradient(g, start: CGPoint(x: x - 220, y: 0), end: CGPoint(x: x + 220, y: CGFloat(height) * 0.35), options: [])
        ctx.restoreGState()
    }

    // MARK: Cache

    private static let cap: Int64 = 300 * 1024 * 1024

    static func evict() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, Int64(v?.fileSize ?? 0), v?.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        entries.sort { $0.2 < $1.2 }
        for e in entries where total > cap {
            try? fm.removeItem(at: e.0)
            total -= e.1
        }
    }

    static var cacheSize: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    static func clearCache() { try? FileManager.default.removeItem(at: folder) }
}

/// Writes a looping H.264 video frame by frame.
enum VideoLoopWriter {
    static func write(to url: URL, width: Int, height: Int, seconds: Double = 8, fps: Int32 = 30,
                      draw: (CGContext, Double) -> Void) async -> Bool {
        try? FileManager.default.removeItem(at: url)
        let tmp = url.deletingLastPathComponent().appending(path: "tmp-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: tmp, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        let frames = Int(seconds * Double(fps))
        for f in 0..<frames {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(4)) }
            guard let pool = adaptor.pixelBufferPool else { return false }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { return false }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                draw(ctx, Double(f) / Double(frames))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { try? FileManager.default.removeItem(at: tmp); return false }
        do { try FileManager.default.moveItem(at: tmp, to: url) } catch { return false }
        return true
    }
}
