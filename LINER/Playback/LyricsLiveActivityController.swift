import ActivityKit
@preconcurrency import AVFoundation
import Foundation

/// Live lyrics on the Lock Screen: while a song with synced lyrics plays, a Live Activity shows the line being
/// sung, updated as the song goes. Setting: Settings → Listening → Live lyrics on the Lock Screen.
@MainActor
final class LyricsLiveActivityController {
    static let shared = LyricsLiveActivityController()

    private var activity: Activity<LyricsActivityAttributes>?
    private var lyrics: Lyrics?
    private var itemID: String?
    private var lastState: LyricsActivityAttributes.ContentState?
    private var loop: Task<Void, Never>?
    private let keepAlive = SilentKeepAlive()

    static var enabled: Bool { UserDefaults.standard.object(forKey: "liveLyrics") as? Bool ?? true }

    /// Called when a new item starts.
    func itemStarted(_ item: QueueItem) {
        guard Self.enabled, ActivityAuthorizationInfo().areActivitiesEnabled else { stop(); return }
        itemID = item.id
        Task {
            let found = await LyricsStore.lyrics(for: item)
            guard itemID == item.id else { return }
            guard let found, found.isSynced else { stop(); return }
            lyrics = found
            start(item)
        }
    }

    private func start(_ item: QueueItem) {
        let attributes = LyricsActivityAttributes(title: item.title, artist: item.artist)
        let state = LyricsActivityAttributes.ContentState(previous: "", current: "", next: lyrics?.lines.first?.text ?? "", isPlaying: true)
        // A new song gets a fresh activity (the title is part of its attributes).
        let old = activity
        activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil), pushType: nil)
        if let old { Task { await old.end(nil, dismissalPolicy: .immediate) } }
        lastState = state
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private func tick() {
        guard let activity, let lyrics, let player = PlaybackCoordinator.shared else { return }
        guard player.current?.id == itemID else { stop(); return }
        // Apple Music songs play outside LINER., so iOS would pause us in the background: keep awake with silence.
        if player.isPlaying && player.engine == .music { keepAlive.start() } else { keepAlive.stop() }
        let i = lyrics.activeIndex(at: player.currentTime + 0.3)
        let lines = lyrics.lines
        let state = LyricsActivityAttributes.ContentState(
            previous: i.flatMap { $0 > 0 ? lines[$0 - 1].text : nil } ?? "",
            current: i.map { lines[$0].text } ?? "",
            next: (i.map { $0 + 1 } ?? 0) < lines.count ? lines[(i.map { $0 + 1 } ?? 0)].text : "",
            isPlaying: player.isPlaying)
        guard state != lastState else { return }
        lastState = state
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        keepAlive.stop()
        lyrics = nil
        lastState = nil
        if let a = activity { activity = nil; Task { await a.end(nil, dismissalPolicy: .immediate) } }
        // End any left over from a previous launch.
        for a in Activity<LyricsActivityAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}

/// Plays silence, mixed with other audio, so LINER. keeps running in the background while Apple Music songs
/// play in the system player (it never interrupts the music or takes over Now Playing).
@MainActor
final class SilentKeepAlive {
    private var engine: AVAudioEngine?

    func start() {
        guard engine == nil, PlaybackCoordinator.shared?.engine == .music else { return }
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

    func stop() {
        guard let e = engine else { return }
        e.stop()
        engine = nil
        // Back to the normal (non-mixing) session for our own player.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }
}
