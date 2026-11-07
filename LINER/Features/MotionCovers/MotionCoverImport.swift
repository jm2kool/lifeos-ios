@preconcurrency import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A video picked from Photos or Files, copied somewhere we can read it.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// Turns a user's video (mp4/mov, or a GIF) into a motion cover: H.264, a loop of at most 20 s.
enum MotionCoverImport {
    /// Imports from Photos. Returns the file name in MotionCoverFiles, or nil.
    static func importVideo(_ item: PhotosPickerItem, id: String) async -> String? {
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return nil }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        return await importFile(movie.url, id: id)
    }

    /// Imports a file (video or GIF). Returns the file name in MotionCoverFiles, or nil.
    static func importFile(_ url: URL, id: String) async -> String? {
        let name = "\(id)-\(Int(Date.now.timeIntervalSince1970)).mp4"
        let dest = MotionCoverFiles.url(name)
        let ok: Bool
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .gif) == true {
            ok = await GIFToVideo.convert(url, to: dest)
        } else {
            ok = await reencode(url, to: dest)
        }
        return ok ? name : nil
    }

    @concurrent
    static func reencode(_ source: URL, to dest: URL) async -> Bool {
        let asset = AVURLAsset(url: source)
        // Video only: a motion cover must never make a sound or take over the music's audio session.
        guard let duration = try? await asset.load(.duration),
              let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else { return false }
        let length = CMTimeMinimum(duration, CMTime(seconds: 20, preferredTimescale: 600))
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: videoTrack, at: .zero)) != nil else { return false }
        track.preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else { return false }
        export.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: dest)
        do {
            try await export.export(to: dest, as: .mp4)
            return true
        } catch {
            return false
        }
    }

    /// The first frame, as a still cover and lock screen preview.
    static func firstFrame(_ url: URL) -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        guard let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Writes a GIF's frames into an H.264 video so it can loop with AVPlayer.
enum GIFToVideo {
    @concurrent
    static func convert(_ gif: URL, to dest: URL) async -> Bool {
        guard let src = CGImageSourceCreateWithURL(gif as CFURL, nil) else { return false }
        let count = CGImageSourceGetCount(src)
        guard count > 0, let first = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        let w = first.width / 2 * 2, h = first.height / 2 * 2
        try? FileManager.default.removeItem(at: dest)
        guard let writer = try? AVAssetWriter(outputURL: dest, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        var time = 0.0
        for i in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gifProps = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gifProps?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gifProps?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(4)) }
            guard let pool = adaptor.pixelBufferPool else { return false }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { return false }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
            time += max(0.02, delay)
            if time > 20 { break }
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }
}
