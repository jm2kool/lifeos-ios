@preconcurrency import AVFoundation
import UIKit

/// Keeps LINER. running in the background while Apple Music songs play in the system's player, so the live
/// lyrics card keeps moving and keeps up with song changes. Adapted from Lyricar's `BackgroundKeepAlive`
/// (Copyright 2026 Alperen Adatepe, Apache License 2.0 — see LINER/NOTICE).
///
/// It plays digital silence with `.mixWithOthers`: the music keeps playing and keeps Now Playing, nothing is
/// audible. The mixer runs at full volume (the buffer is zeros), so the system sees a normally playing render
/// path rather than a muted one. Staying alive is the fragile part: a route change (AirPods, CarPlay), an
/// interruption (a call, Siri, an alarm) or a media services reset stops the engine silently, and iOS then
/// suspends the app. Each of those restarts it; a 10 s watchdog catches stops nobody announced; and while the
/// engine is down in the background, a background task holds LINER. up so the restart can happen at all.
@MainActor
final class SilentKeepAlive {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private(set) var isRunning = false
    private(set) var wanted = false
    private var observers: [NSObjectProtocol] = []
    private var watchdog: Timer?
    private var hold: UIBackgroundTaskIdentifier = .invalid

    init() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                let ended = (info[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
                MainActor.assumeIsolated { self?.interrupted(ended: ended) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartIfNeeded(reason: "route change") }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild(reason: "iOS restarted its media services") }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartIfNeeded(reason: "audio configuration change") }
            },
        ]
    }

    /// Turns it on (cheap to call every tick: it only acts when it isn't running).
    func start() {
        wanted = true
        // Armed before the attempt, so a start that fails is retried instead of forgotten.
        startWatchdog()
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let format = engine.outputNode.inputFormat(forBus: 0)
            guard format.sampleRate > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else {
                report("Keep-alive: no audio output yet, will retry")
                holdIfBackground()
                return
            }
            buffer.frameLength = buffer.frameCapacity   // zero-filled: silence
            if player.engine == nil { engine.attach(player) }
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 1
            engine.prepare()
            try engine.start()
            // play() on a stopped engine or an unconnected node raises an exception Swift can't catch.
            guard engine.isRunning, player.engine === engine, !engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty else {
                report("Keep-alive: audio engine not ready, will retry")
                holdIfBackground()
                return
            }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            isRunning = true
            report("Keep-alive on")
            releaseHold()
        } catch {
            isRunning = false
            report("⚠︎ Keep-alive failed to start (\((error as NSError).code)): \(error.localizedDescription)")
            holdIfBackground()
        }
    }

    func stop() {
        wanted = false
        watchdog?.invalidate()
        watchdog = nil
        releaseHold()
        guard isRunning else { return }
        player.stop()
        engine.stop()
        isRunning = false
        // Back to the normal (non-mixing) session for our own player.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        report("Keep-alive off")
    }

    /// The engine can also stop without any notice: checked every 10 s, which is also the retry pace.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartIfNeeded(reason: "watchdog") }
        }
    }

    private func interrupted(ended: Bool) {
        if ended {
            report("Audio interruption ended")
            restartIfNeeded(reason: "interruption ended")
        } else {
            isRunning = false
            report("Audio interrupted (call, Siri, an alarm or another app)")
            // No end notice is guaranteed; without a hold iOS suspends us as soon as the audio stops.
            holdIfBackground()
        }
    }

    private func restartIfNeeded(reason: String) {
        guard wanted else { return }
        if isRunning, engine.isRunning, player.isPlaying { return }
        report("Keep-alive restarting after \(reason)")
        isRunning = false
        start()
    }

    private func rebuild(reason: String) {
        guard wanted else { return }
        report("Keep-alive rebuilt: \(reason)")
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        isRunning = false
        start()
    }

    // MARK: Background hold

    /// While the engine is down in the background, a background task (about 30 s) keeps LINER. running for the
    /// retries.
    private func holdIfBackground() {
        guard wanted, hold == .invalid, UIApplication.shared.applicationState == .background else { return }
        hold = UIApplication.shared.beginBackgroundTask(withName: "KeepAliveRestart") { [weak self] in
            MainActor.assumeIsolated {
                self?.report("Keep-alive: iOS's grace period ran out (running: \(self?.isRunning == true))")
                self?.releaseHold()
            }
        }
        guard hold != .invalid else { report("⚠︎ Keep-alive: iOS gave no time to restart"); return }
        Task { [weak self] in
            for _ in 0..<5 {
                try? await Task.sleep(for: .seconds(4))
                guard let self, self.wanted, !self.isRunning else { return }
                self.restartIfNeeded(reason: "a retry")
            }
        }
    }

    private func releaseHold() {
        guard hold != .invalid else { return }
        UIApplication.shared.endBackgroundTask(hold)
        hold = .invalid
    }

    private func report(_ line: String) { LiveLyricsLog.add(line) }
}
