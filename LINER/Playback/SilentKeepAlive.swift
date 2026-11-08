@preconcurrency import AVFoundation
import UIKit

/// Keeps LINER. running in the background while Apple Music songs play in the system's player, so the live
/// lyrics card can keep moving. It loops a second of silence, mixed with other audio (it never interrupts the music
/// or takes over Now Playing), and checks itself on every tick: if iOS stopped it (a call, Siri, AirPods, the
/// media server restarting, a song change in the system player), it starts again at once.
@MainActor
final class SilentKeepAlive {
    private var player: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private(set) var wanted = false

    init() { Self.current = self }

    /// Turns it on, or restarts it if it was stopped behind our back. Cheap to call every tick.
    func start() {
        wanted = true
        observe()
        if let p = player, p.isPlaying { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback || !session.categoryOptions.contains(.mixWithOthers) {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)
        if player == nil { player = Self.makePlayer() }
        guard let p = player else { return }
        if !p.play() {
            // A player that won't resume is replaced with a fresh one.
            player = Self.makePlayer()
            player?.play()
        }
    }

    func stop() {
        wanted = false
        guard let p = player else { return }
        p.stop()
        player = nil
        // Back to the normal (non-mixing) session for our own player.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    var isRunning: Bool { player?.isPlaying == true }

    private static func makePlayer() -> AVAudioPlayer? {
        guard let p = try? AVAudioPlayer(data: silence, fileTypeHint: AVFileType.wav.rawValue) else { return nil }
        p.numberOfLoops = -1
        p.volume = 0.01
        p.prepareToPlay()
        return p
    }

    /// One second of 8 kHz, 16-bit mono silence as a WAV file.
    private static let silence: Data = {
        let rate: UInt32 = 8000
        let bytes = rate * 2
        var d = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + bytes))
        d.append(contentsOf: Array("WAVE".utf8)); d.append(contentsOf: Array("fmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(rate); put(rate * 2); put(UInt16(2)); put(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); put(bytes)
        d.append(Data(count: Int(bytes)))
        return d
    }()

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
            AVAudioSession.mediaServicesWereResetNotification, UIApplication.didEnterBackgroundNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { @Sendable note in
                let reset = note.name == AVAudioSession.mediaServicesWereResetNotification
                MainActor.assumeIsolated { SilentKeepAlive.restartIfNeeded(rebuild: reset) }
            })
        }
    }

    /// The keep-alive, for the notification hooks.
    private static weak var current: SilentKeepAlive?
    private static func restartIfNeeded(rebuild: Bool) {
        guard let k = current, k.wanted else { return }
        if rebuild { k.player = nil }
        k.start()
    }
}
