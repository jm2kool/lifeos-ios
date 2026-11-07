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
    private var song: (title: String, artist: String) = ("", "")
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
        song = (item.title, item.artist)
        let state = LyricsActivityAttributes.ContentState(title: item.title, artist: item.artist, previous: "", current: "",
                                                          next: lyrics?.lines.first?.text ?? "", isPlaying: true)
        if let activity {
            // The same activity carries on with the new song: nothing pops up again.
            let box = ActivityBox(activity: activity)
            Task.detached { await box.activity.update(Self.content(state)) }
        } else {
            for a in Activity<LyricsActivityAttributes>.activities { Self.end(a) }
            activity = try? Activity.request(attributes: LyricsActivityAttributes(), content: Self.content(state), pushType: nil)
        }
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
            title: song.title, artist: song.artist,
            previous: i.flatMap { $0 > 0 ? lines[$0 - 1].text : nil } ?? "",
            current: i.map { lines[$0].text } ?? "",
            next: (i.map { $0 + 1 } ?? 0) < lines.count ? lines[(i.map { $0 + 1 } ?? 0)].text : "",
            isPlaying: player.isPlaying)
        guard state != lastState else { return }
        lastState = state
        let box = ActivityBox(activity: activity)
        Task.detached { await box.activity.update(Self.content(state)) }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        keepAlive.stop()
        lyrics = nil
        lastState = nil
        if let a = activity { activity = nil; Self.end(a) }
        // End any left over from a previous launch.
        for a in Activity<LyricsActivityAttributes>.activities { Self.end(a) }
    }
}

extension LyricsLiveActivityController {
    /// Lowest relevance, so when the system's Now Playing is also live it gets the Dynamic Island, not us.
    nonisolated static func content(_ state: LyricsActivityAttributes.ContentState) -> ActivityContent<LyricsActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: nil, relevanceScore: 0)
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
