@preconcurrency import AVFoundation
import QuartzCore

/// Builds a one-track video composition with the iOS 26 configuration API (scale/crop transform,
/// optional Core Animation overlay).
enum Composition {
    static func make(asset: AVAsset, track: AVAssetTrack, transform: CGAffineTransform, duration: CMTime,
                     renderSize: CGSize, animationTool: AVVideoCompositionCoreAnimationTool? = nil) async throws -> AVVideoComposition {
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: CMTimeRange(start: .zero, duration: duration)))
        var config = try await AVVideoComposition.Configuration(for: asset, prototypeInstruction: nil)
        config.renderSize = renderSize
        config.frameDuration = CMTime(value: 1, timescale: 30)
        config.instructions = [instruction]
        config.animationTool = animationTool
        return AVVideoComposition(configuration: config)
    }
}
