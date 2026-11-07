@preconcurrency import AVFoundation
import SwiftUI

/// A silent, endlessly looping video that fills its frame (motion covers and Living Covers).
/// Keeps playing in Low Power Mode unless "Respect Low Power Mode" is on (SPEC §6.5).
struct LoopingVideo: UIViewRepresentable {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> LoopingPlayerView { LoopingPlayerView(url: url, gravity: gravity) }

    func updateUIView(_ view: LoopingPlayerView, context: Context) {
        if view.url != url { view.load(url) }
    }

    static func dismantleUIView(_ view: LoopingPlayerView, coordinator: ()) { view.stop() }
}

final class LoopingPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private(set) var url: URL?

    init(url: URL, gravity: AVLayerVideoGravity) {
        super.init(frame: .zero)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // Never take over the audio session from the music.
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        playerLayer.player = player
        playerLayer.videoGravity = gravity
        load(url)
    }

    required init?(coder: NSCoder) { fatalError() }

    func load(_ url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        if MotionSettings.shouldAnimate { player.play() }
    }

    func stop() { player.pause(); looper = nil }
}

/// The animation settings (SPEC §6.5, §6.17).
enum MotionSettings {
    static var livingCoversOn: Bool { UserDefaults.standard.object(forKey: "livingCovers") as? Bool ?? true }
    static var respectLowPower: Bool { UserDefaults.standard.bool(forKey: "respectLowPower") }
    static var shouldAnimate: Bool { !(respectLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled) }
}
