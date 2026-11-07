@preconcurrency import AVFoundation
import UIKit

/// Crops a user motion cover to the lock screen's exact aspect ratios (3:4 and 1:1), cached next to it.
enum MotionCrop {
    @concurrent
    static func crop(_ source: URL, to aspect: LivingCoverRenderer.Aspect) async -> URL? {
        let dest = source.deletingPathExtension().appendingPathExtension("\(aspect.rawValue).mp4")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let asset = AVURLAsset(url: source)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration) else { return nil }
        let oriented = natural.applying(transform)
        let src = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let (w, h) = aspect.size
        let target = CGSize(width: w, height: h)
        let scale = max(target.width / src.width, target.height / src.height)
        let tx = (target.width - src.width * scale) / 2, ty = (target.height - src.height * scale) / 2

        let t = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: tx, y: ty))
        guard let composition = try? await Composition.make(asset: asset, track: track, transform: t, duration: duration, renderSize: target),
              let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        export.videoComposition = composition
        do { try await export.export(to: dest, as: .mp4); return dest } catch { return nil }
    }

    /// First frame of a cropped motion cover (the preview must match its aspect exactly).
    static func preview(_ url: URL) async -> UIImage? { await MotionCoverImport.firstFrame(url) }
}
