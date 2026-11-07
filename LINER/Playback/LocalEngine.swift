@preconcurrency import AVFoundation

/// Plays imported files (mixtape tracks) with our own AVPlayer, so we own Now Playing fully.
@MainActor
final class LocalEngine {
    let player = AVPlayer()
    var onEnd: (() -> Void)?
    private var endObserver: NSObjectProtocol?

    var isPlaying: Bool { player.rate != 0 }
    var currentTime: Double { let t = player.currentTime().seconds; return t.isFinite ? t : 0 }

    func load(_ url: URL, startTime: Double = 0) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { LocalEngine.shared?.onEnd?() }
        }
        if startTime > 0 { seek(startTime) }
        player.play()
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { player.pause(); player.replaceCurrentItem(with: nil) }
    func seek(_ t: Double) { player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }

    static weak var shared: LocalEngine?
    init() { Self.shared = self }
}
