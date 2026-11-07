@preconcurrency import MediaPlayer

/// Library playback through `MPMusicPlayerController.applicationQueuePlayer` (no MusicKit, works on free signing).
/// The coordinator feeds it one contiguous run of library songs at a time.
@MainActor
final class MusicEngine {
    let player = MPMusicPlayerController.applicationQueuePlayer
    /// Fired when the engine moves to another song (nil when its run is over).
    var onItemChange: ((UInt64?) -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var runIDs: [UInt64] = []
    private var observing = false

    var isPlaying: Bool { player.playbackState == .playing }
    var currentTime: Double { let t = player.currentPlaybackTime; return t.isFinite ? t : 0 }
    var nowPlayingID: UInt64? { player.nowPlayingItem?.persistentID }
    var indexInRun: Int { player.indexOfNowPlayingItem }

    /// Starts a run straight away (no waiting for preparation, so a tap plays at once). A MediaPlayer error —
    /// for example no subscription for a cloud song — arrives later through `onError`.
    func load(_ items: [MPMediaItem], startTime: Double = 0, onError: @escaping @MainActor @Sendable (Error) -> Void) {
        observe()
        runIDs = items.map(\.persistentID)
        player.repeatMode = .none
        player.shuffleMode = .off
        player.setQueue(with: MPMediaItemCollection(items: items))
        if let first = items.first { player.nowPlayingItem = first }
        player.prepareToPlay { @Sendable error in
            if let error { Task { @MainActor in onError(error) } }
        }
        if startTime > 0 { player.currentPlaybackTime = startTime }
        player.play()
    }

    /// Wakes the system music player after an install or a recalibrate: stops whatever it held, then loads one
    /// library song without playing it, so the next tap plays straight away.
    func recalibrate(with item: MPMediaItem?) {
        observe()
        player.stop()
        runIDs = []
        guard let item else { return }
        player.setQueue(with: MPMediaItemCollection(items: [item]))
        player.prepareToPlay { @Sendable _ in }
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop(); runIDs = [] }
    func seek(_ t: Double) { player.currentPlaybackTime = t }
    func skipToNext() { player.skipToNextItem() }
    func skipToPrevious() { player.skipToPreviousItem() }
    func restartItem() { player.skipToBeginning() }

    private func observe() {
        guard !observing else { return }
        observing = true
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { MusicEngine.shared?.itemChanged() }
        }
        center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { MusicEngine.shared?.onStateChange?() }
        }
    }

    private func itemChanged() { onItemChange?(nowPlayingID) }

    /// The one engine, for notification callbacks.
    static weak var shared: MusicEngine?
    init() { Self.shared = self }
}
