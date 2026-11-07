@preconcurrency import MediaPlayer

/// Library and Apple Music playback through `MPMusicPlayerController.applicationQueuePlayer` (no MusicKit, works
/// on free signing). The coordinator feeds it one contiguous run of songs at a time.
///
/// Downloaded songs are queued as library items. Songs in iCloud (and Apple Music songs that aren't in the library)
/// are queued by their Apple Music ID instead, which streams them with your subscription — queueing an iCloud
/// item as a library item often fails as if it needed downloading.
@MainActor
final class MusicEngine {
    let player = MPMusicPlayerController.applicationQueuePlayer
    /// Fired when the engine moves to another song (nil when its run is over).
    var onItemChange: ((UInt64?) -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var run: [Song] = []
    private(set) var streaming = false
    private var observing = false
    private var attempt = 0

    var runIDs: [UInt64] { run.map(\.id) }
    var isPlaying: Bool { player.playbackState == .playing }
    var currentTime: Double { let t = player.currentPlaybackTime; return t.isFinite ? t : 0 }
    var indexInRun: Int { player.indexOfNowPlayingItem }

    /// The song playing, as one of the run's songs: by library ID, then Apple Music ID, then position.
    var nowPlayingID: UInt64? {
        guard let item = player.nowPlayingItem else { return nil }
        if let s = run.first(where: { $0.id == item.persistentID }) { return s.id }
        if !item.playbackStoreID.isEmpty, let s = run.first(where: { $0.storeID == item.playbackStoreID }) { return s.id }
        let i = player.indexOfNowPlayingItem
        return run.indices.contains(i) ? run[i].id : item.persistentID
    }

    /// Whether a run starting with this song should stream it by its Apple Music ID.
    static func streams(_ song: Song, item: MPMediaItem?) -> Bool {
        song.hasStoreID && (song.isCloudOnly || item == nil)
    }

    /// Starts a run straight away (no waiting for preparation, so a tap plays at once). If MediaPlayer reports a
    /// problem, it checks whether the music is playing anyway, then tries the other way of queueing once, and
    /// only then calls `onError`.
    func load(_ songs: [Song], items: MediaItemIndex, stream: Bool, startTime: Double = 0, isRetry: Bool = false,
              onError: @escaping @MainActor @Sendable (Error) -> Void) {
        observe()
        if !isRetry { retried = false }
        run = songs
        streaming = stream
        attempt += 1
        let thisAttempt = attempt
        player.repeatMode = .none
        player.shuffleMode = .off
        if stream {
            player.setQueue(with: MPMusicPlayerStoreQueueDescriptor(storeIDs: songs.map(\.storeID)))
        } else {
            let list = songs.compactMap { items[$0.id] }
            player.setQueue(with: MPMediaItemCollection(items: list))
            if let first = list.first { player.nowPlayingItem = first }
        }
        player.prepareToPlay { @Sendable error in
            guard let error else { return }
            Task { @MainActor in await MusicEngine.shared?.recover(error, attempt: thisAttempt, items: items, startTime: startTime, onError: onError) }
        }
        if startTime > 0 { player.currentPlaybackTime = startTime }
        player.play()
    }

    /// A start that reported an error: ignore it if the music is playing after all; otherwise queue the other way.
    private func recover(_ error: Error, attempt failed: Int, items: MediaItemIndex, startTime: Double,
                         onError: @escaping @MainActor @Sendable (Error) -> Void) async {
        guard failed == attempt else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard failed == attempt, !isPlaying else { return }
        let canStream = run.allSatisfy(\.hasStoreID)
        let canQueueItems = run.allSatisfy { items[$0.id] != nil }
        if !retried && !streaming && canStream {
            retried = true
            load(run, items: items, stream: true, startTime: startTime, isRetry: true, onError: onError)
        } else if !retried && streaming && canQueueItems {
            retried = true
            load(run, items: items, stream: false, startTime: startTime, isRetry: true, onError: onError)
        } else {
            onError(error)
        }
    }

    /// One retry per run, so a song that really can't play doesn't bounce forever.
    private var retried = false

    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop(); run = []; retried = false; attempt += 1 }
    func seek(_ t: Double) { player.currentPlaybackTime = t }
    func skipToNext() { player.skipToNextItem() }
    func skipToPrevious() { player.skipToPreviousItem() }
    func restartItem() { player.skipToBeginning() }

    /// Wakes the system music player after an install or a recalibrate: stops whatever it held, then loads one
    /// library song without playing it, so the next tap plays straight away.
    func recalibrate(with item: MPMediaItem?) {
        observe()
        stop()
        guard let item else { return }
        player.setQueue(with: MPMediaItemCollection(items: [item]))
        player.prepareToPlay { @Sendable _ in }
    }

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

extension Song {
    /// Has an Apple Music ID it can be streamed by.
    var hasStoreID: Bool { !storeID.isEmpty && storeID != "0" }
    /// A song from the Apple Music catalogue that isn't in the library (an artist page's Top Songs).
    var isCatalog: Bool { id & Song.catalogFlag != 0 }
    static let catalogFlag: UInt64 = 1 << 62
}
