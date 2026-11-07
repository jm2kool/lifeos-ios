import ActivityKit
@preconcurrency import AVFoundation
import Foundation

/// Live lyrics on the Lock Screen: while something plays, one Live Activity shows the song and the line being
/// sung, and carries on from song to song (iOS won't let an app start a new one from the background, so it's
/// never ended between songs). Setting: Settings → Listening → Live lyrics on the Lock Screen.
@MainActor
final class LyricsLiveActivityController {
    static let shared = LyricsLiveActivityController()

    private var activity: Activity<LyricsActivityAttributes>?
    private var lyrics: Lyrics?
    private var itemID: String?
    private var song: (title: String, artist: String) = ("", "")
    private var lastState: LyricsActivityAttributes.ContentState?
    private var loop: Task<Void, Never>?
    private let keepAlive = SilentKeepAlive()
    private var pausedSince: Date?
    /// Updates go out one at a time, newest wins, so an older line can never land after a newer one.
    private var queued: LyricsActivityAttributes.ContentState?
    private var sending = false
    private var sendStarted = Date.distantPast
    private var lastSent = Date.distantPast
    private var sender = 0

    static var enabled: Bool { UserDefaults.standard.object(forKey: "liveLyrics") as? Bool ?? true }

    /// Called when a new item starts: the activity switches to it straight away, then picks up its lyrics.
    func itemStarted(_ item: QueueItem) {
        guard Self.enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { stop(); return }
        itemID = item.id
        song = (item.title, item.artist)
        lyrics = nil
        ensureActivity()
        tick()
        Task {
            let found = await LyricsStore.lyrics(for: item)
            guard itemID == item.id else { return }
            lyrics = found?.isSynced == true ? found : nil
            tick()
            // Fetch the next song's lyrics now, so they're there even if the network is slow in the background.
            if let next = PlaybackCoordinator.shared?.upNext.first { _ = await LyricsStore.lyrics(for: next) }
        }
    }

    private func ensureActivity() {
        if let a = activity, a.activityState == .active || a.activityState == .stale { startLoop(); return }
        activity = nil
        for a in Activity<LyricsActivityAttributes>.activities { Self.end(a) }
        let state = makeState(index: -1, playing: true)
        activity = try? Activity.request(attributes: LyricsActivityAttributes(), content: Self.content(state), pushType: nil)
        lastState = state
        startLoop()
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func tick() {
        guard let player = PlaybackCoordinator.shared else { return }
        guard let current = player.current else { stop(); return }
        if current.id != itemID { itemStarted(current); return }   // a change we weren't told about
        // Swiped away on the Lock Screen: leave it gone until the next song starts in the app.
        if let a = activity, a.activityState == .dismissed || a.activityState == .ended { activity = nil }
        keepAwake(player)
        guard activity != nil else { return }
        let i = lyrics?.activeIndex(at: player.currentTime + 0.3) ?? -1
        let state = makeState(index: i, playing: player.isPlaying)
        // A heartbeat every 10 s even when nothing changed, which also keeps the card from being marked stale.
        guard state != lastState || Date.now.timeIntervalSince(lastSent) > 10 else { return }
        lastState = state
        send(state)
    }

    /// Apple Music songs play outside LINER., so iOS would freeze us in the background: silence keeps us awake,
    /// also for a while after a pause so a resume from the Lock Screen is noticed.
    private func keepAwake(_ player: PlaybackCoordinator) {
        if player.isPlaying { pausedSince = nil } else if pausedSince == nil { pausedSince = .now }
        let recentlyPaused = pausedSince.map { Date.now.timeIntervalSince($0) < 15 * 60 } ?? true
        if player.engine == .music && recentlyPaused { keepAlive.start() } else { keepAlive.stop() }
    }

    private func makeState(index i: Int, playing: Bool) -> LyricsActivityAttributes.ContentState {
        let lines = lyrics?.lines ?? []
        func line(_ k: Int) -> String { lines.indices.contains(k) ? lines[k].text : "" }
        return LyricsActivityAttributes.ContentState(
            title: song.title, artist: song.artist, index: i,
            previous: line(i - 1), current: line(i), next: i < 0 ? line(0) : line(i + 1), isPlaying: playing)
    }

    private func send(_ state: LyricsActivityAttributes.ContentState) {
        queued = state
        lastSent = .now
        // An update that hasn't come back in 3 s is stuck: stop waiting for it, so the card keeps moving.
        if sending && Date.now.timeIntervalSince(sendStarted) > 3 { sending = false }
        guard !sending, let activity else { return }
        sending = true
        sender += 1
        let me = sender
        let box = ActivityBox(activity: activity)
        Task {
            while let next = queued, me == sender {
                queued = nil
                sendStarted = .now
                await box.update(Self.content(next))
            }
            if me == sender { sending = false }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        keepAlive.stop()
        lyrics = nil
        lastState = nil
        itemID = nil
        queued = nil
        if let a = activity { activity = nil; Self.end(a) }
        // End any left over from a previous launch.
        for a in Activity<LyricsActivityAttributes>.activities { Self.end(a) }
    }
}

extension LyricsLiveActivityController {
    /// Lowest relevance, so when the system's Now Playing is also live it gets the Dynamic Island, not us. Stale
    /// after 45 s without news (the heartbeat is every 10 s), so a card that can't update says so.
    nonisolated static func content(_ state: LyricsActivityAttributes.ContentState) -> ActivityContent<LyricsActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: .now.addingTimeInterval(45), relevanceScore: 0)
    }

    /// Ends an activity off the main actor.
    nonisolated static func end(_ activity: Activity<LyricsActivityAttributes>) {
        let box = ActivityBox(activity: activity)
        Task.detached { await box.activity.end(nil, dismissalPolicy: .immediate) }
    }
}

/// Carries a Live Activity into a background task (ActivityKit's handle is safe to use from any thread).
struct ActivityBox: @unchecked Sendable {
    let activity: Activity<LyricsActivityAttributes>

    nonisolated func update(_ content: ActivityContent<LyricsActivityAttributes.ContentState>) async {
        await activity.update(content)
    }
}

/// Plays silence, mixed with other audio, so LINER. keeps running in the background while Apple Music songs
/// play in the system player (it never interrupts the music or takes over Now Playing).
@MainActor
final class SilentKeepAlive {
    private var engine: AVAudioEngine?

    private var observers: [NSObjectProtocol] = []

    func start() {
        // An interruption (a call, Siri) or a route change (AirPods) stops the engine: start a fresh one.
        if let e = engine, !e.isRunning { e.stop(); engine = nil }
        guard engine == nil, PlaybackCoordinator.shared?.engine == .music else { return }
        observe()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        let e = AVAudioEngine()
        let player = AVAudioPlayerNode()
        e.attach(player)
        let format = e.mainMixerNode.outputFormat(forBus: 0)
        e.connect(player, to: e.mainMixerNode, format: format)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else { return }
        buffer.frameLength = buffer.frameCapacity   // zero-filled: silence
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        e.mainMixerNode.outputVolume = 0
        do { try e.start(); player.play(); engine = e } catch { engine = nil }
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [AVAudioSession.interruptionNotification, Notification.Name.AVAudioEngineConfigurationChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { @Sendable _ in
                MainActor.assumeIsolated { SilentKeepAlive.restartIfNeeded() }
            })
        }
    }

    /// The running keep-alive, for the notification hooks.
    private static weak var current: SilentKeepAlive?
    private static func restartIfNeeded() {
        guard let k = current, let e = k.engine, !e.isRunning else { return }
        k.engine = nil
        k.start()
    }

    init() { Self.current = self }

    func stop() {
        guard let e = engine else { return }
        e.stop()
        engine = nil
        // Back to the normal (non-mixing) session for our own player.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }
}
