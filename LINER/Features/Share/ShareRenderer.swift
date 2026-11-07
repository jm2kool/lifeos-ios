@preconcurrency import AVFoundation
import Photos
import QuartzCore
import SwiftUI

/// Makes share cards (SPEC §6.13): a 1080 × 1920 still with ImageRenderer, and — when there's a motion cover or
/// Living Cover — a ≤ 20 s H.264 video with the card composited on top.
@MainActor
enum ShareRenderer {
    static func backgroundImage(for content: ShareContent) async -> UIImage? {
        if let name = content.portraitName, let p = await ArtistImageStore.shared.portrait(for: name) { return p }
        if let item = content.coverItem { return await CoverArt.image(for: item, pixels: 1600) }
        if let id = content.albumID { return await ArtworkCache.shared.image(album: id, pixels: 1600) }
        return nil
    }

    static func still(_ content: ShareContent, background: UIImage?) -> UIImage? {
        let r = ImageRenderer(content: ZStack { ShareBackground(image: background); ShareOverlay(content: content) }.frame(width: 1080, height: 1920))
        r.scale = 1
        return r.uiImage
    }

    static func overlay(_ content: ShareContent) -> UIImage? {
        let r = ImageRenderer(content: ShareOverlay(content: content))
        r.scale = 1
        r.isOpaque = false
        return r.uiImage
    }

    /// The 9:16 moving background: your motion cover cropped to 9:16, or a Living Cover.
    static func backgroundVideo(for content: ShareContent, image: UIImage?) async -> URL? {
        if let item = content.coverItem, let motion = MotionLookup.file(for: item) {
            return await MotionCrop.crop(MotionCoverFiles.url(motion), to: .story)
        }
        guard MotionSettings.livingCoversOn, let image, let key = content.artworkKey else { return nil }
        return await LivingCoverRenderer.video(for: image, key: content.portraitName.map { "artist-\($0)" } ?? key, aspect: .story)
    }

    /// Composites the overlay on the background video, looping it to about 16 s.
    @concurrent
    static func video(background: URL, overlay: UIImage) async -> URL? {
        let asset = AVURLAsset(url: background)
        guard let src = try? await asset.loadTracks(withMediaType: .video).first,
              let length = try? await asset.load(.duration), length.seconds > 0 else { return nil }
        let comp = AVMutableComposition()
        guard let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        var cursor = CMTime.zero
        let target = CMTime(seconds: min(20, max(length.seconds, 16)), preferredTimescale: 600)
        while cursor < target {
            let piece = CMTimeMinimum(length, target - cursor)
            try? track.insertTimeRange(CMTimeRange(start: .zero, duration: piece), of: src, at: cursor)
            cursor = cursor + piece
        }
        let size = CGSize(width: 1080, height: 1920)
        let natural = (try? await src.load(.naturalSize)) ?? size
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(CGAffineTransform(scaleX: size.width / natural.width, y: size.height / natural.height), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
        instruction.layerInstructions = [layer]

        let parent = CALayer(), videoLayer = CALayer(), top = CALayer()
        for l in [parent, videoLayer, top] { l.frame = CGRect(origin: .zero, size: size) }
        top.contents = overlay.cgImage
        top.contentsGravity = .resize
        parent.addSublayer(videoLayer)
        parent.addSublayer(top)

        let vc = AVMutableVideoComposition()
        vc.renderSize = size
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.instructions = [instruction]
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)

        let out = URL.temporaryDirectory.appending(path: "liner-share-\(UUID().uuidString).mp4")
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPreset1920x1080) else { return nil }
        export.videoComposition = vc
        do { try await export.export(to: out, as: .mp4); return out } catch { return nil }
    }

    // MARK: Destinations

    /// Instagram Stories through the pasteboard and `instagram-stories://` (Facebook app ID from Info.plist).
    static func instagram(image: UIImage?, video: URL?, top: Color, bottom: Color) async -> Bool {
        let id = AppBrand.facebookAppID.isEmpty ? (Bundle.main.bundleIdentifier ?? "") : AppBrand.facebookAppID
        guard let url = URL(string: "instagram-stories://share?source_application=\(id)"), UIApplication.shared.canOpenURL(url) else { return false }
        var item: [String: Any] = [
            "com.instagram.sharedSticker.backgroundTopColor": top.hex,
            "com.instagram.sharedSticker.backgroundBottomColor": bottom.hex,
        ]
        if let video, let data = try? Data(contentsOf: video) {
            item["com.instagram.sharedSticker.backgroundVideo"] = data
        } else if let data = image?.jpegData(compressionQuality: 0.92) {
            item["com.instagram.sharedSticker.backgroundImage"] = data
        }
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date.now.addingTimeInterval(5 * 60)])
        return await UIApplication.shared.open(url)
    }

    static func saveToPhotos(image: UIImage?, video: URL?) async -> Bool {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if let video { PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: video) }
                else if let image { PHAssetCreationRequest.creationRequestForAsset(from: image) }
            }
            return true
        } catch {
            return false
        }
    }
}

extension Color {
    /// "#RRGGBB" for Instagram's background colours.
    var hex: String {
        let c = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func n(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", n(r), n(g), n(b))
    }
}
