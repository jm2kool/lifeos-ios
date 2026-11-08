@preconcurrency import MediaPlayer

/// Library and Apple Music playback through MediaPlayer (no MusicKit, works on free signing). The coordinator
/// feeds it one contiguous run of songs at a time.
///
/// Downloaded songs are queued as library items on `applicationQueuePlayer`. Songs in iCloud and Apple Music songs
/// that aren't in the library are queued by their Apple Music ID. The app's own queue player often refuses Apple
/// Music songs that aren't in the library, so if it does, the run goes to the system music player instead (the
/// same player the Music app uses), and LINER. remembers to send streams there from then on.
@MainActor
final class MusicEngine {
    private let appPlayer = MPMusicPlayerController.applicationQueuePlayer
    private let systemPlayer = MPMusicPlayerController.systemMusicPlayer
    /// The player holding the current run.
    private(set) var player: MPMusicPlayerController
    /// Fired when the engine moves to another song (nil when its run is over).
    var onItemChange: ((UInt64?) -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var run: [Song] = []
    private(set) var streaming = false
    /// A stream is still being prepared (it starts playing once ready), so its state notifications mean nothing yet.
    private(set) var preparing = false
    private var observing = false
    private var attempt = 0
    /// The ways this run has already been tried, so a song that really can't play doesn't bounce forever.
    private var tried: Set<Route> = []

    private enum Route: Hashable { case appItems, appStream, systemStream }

    /// Streams go to the system music player (set once the app's queue player has refused a stream that the
    /// system player then played).
    private static var streamsViaSystem: Bool {
        get { UserDefaults.standard.bool(forKey: "streamsViaSystemPlayer") }
        set { UserDefaults.standard.set(newValue, forKey: "streamsViaSystemPlayer") }
    }

    var runIDs: [UInt64] { run.map(\.id) }
    var isPlaying: Bool { player.playbackState == .playing }
    var currentTime: Double { let t = player.currentPlaybackTime; return t.isFinite ? t : 0 }
    var indexInRun: Int { player.indexOfNowPlayingItem }

    /// The song playing, as one of the run's songs: by library ID, then Apple Music ID, then position.
    var nowPlayingID: UInt64? {
        guard let item = player.nowPlayingItem else { return nil }
        if let s = run.first(where: { $0.id == item.persistentID }) { return s.id }
        if !item.playbackStoreID.isEmpty, let s = run.first(where: { $0.storeID == item.playbackStoreID }) { return s.id }
        // Streams are matched by Apple Music ID or, when Apple plays another version of a song (clean, another
        // album), by title, the next one along first; never by position, which could take a song left over from
        // the Music app's own queue for one of ours.
        if streaming {
            let title = MediaKey.normalise(item.title ?? "")
            guard !title.isEmpty else { return item.persistentID }
            let i = max(0, player.indexOfNowPlayingItem)
            let order = run.indices.sorted { abs($0 - i) < abs($1 - i) }
            return order.first { MediaKey.normalise(run[$0].title) == title }.map { run[$0].id } ?? item.persistentID
        }
        let i = player.indexOfNowPlayingItem
        return run.indices.contains(i) ? run[i].id : item.persistentID
    }

    /// Whether a run starting with this song should stream it by its Apple Music ID.
    static func streams(_ song: Song, item: MPMediaItem?) -> Bool {
        song.hasStoreID && (song.isCloudOnly || item == nil)
    }

    /// Starts a run. Library items play at once (no waiting, so a tap plays straight away); streams wait for
    /// MediaPlayer to finish preparing, since asking a stream to play early can cancel it. If a start reports a
    /// problem, the music is checked (it sometimes plays anyway), then the run is tried another way before
    /// `onError` is called.
    func load(_ songs: [Song], items: MediaItemIndex, stream: Bool, startTime: Double = 0,
              onError: @escaping @MainActor @Sendable (Error) -> Void) {
        tried = []
        let route: Route = stream ? (Self.streamsViaSystem ? .systemStream : .appStream) : .appItems
        start(songs, route: route, items: items, startTime: startTime, onError: onError)
    }

    private func start(_ songs: [Song], route: Route, items: MediaItemIndex, startTime: Double,
                       onError: @escaping @MainActor @Sendable (Error) -> Void) {
        observe()
        tried.insert(route)
        run = songs
        streaming = route != .appItems
        attempt += 1
        let thisAttempt = attempt
        let next = route == .systemStream ? systemPlayer : appPlayer
        if next !== player { player.stop() }
        // The system player keeps the Music app's queue; clear it so a queue that doesn't take can't resume it.
        if route == .systemStream { next.stop() }
        player = next
        player.repeatMode = .none
        player.shuffleMode = .off
        if streaming {
            let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: songs.map(\.storeID))
            descriptor.startItemID = songs.first?.storeID
            player.setQueue(with: descriptor)
        } else {
            let list = songs.compactMap { items[$0.id] }
            player.setQueue(with: MPMediaItemCollection(items: list))
            if let first = list.first { player.nowPlayingItem = first }
        }
        let waits = streaming
        preparing = waits
        player.prepareToPlay { @Sendable error in
            Task { @MainActor in
                guard let engine = MusicEngine.shared, engine.attempt == thisAttempt else { return }
                if let error {
                    engine.preparing = true
                    await engine.recover(error, attempt: thisAttempt, items: items, startTime: startTime, onError: onError)
                } else if waits {
                    engine.preparing = false
                    if startTime > 0 { engine.player.currentPlaybackTime = startTime }
                    engine.player.play()
                    await engine.verify(attempt: thisAttempt, route: route, items: items, startTime: startTime, onError: onError)
                }
            }
        }
        if !waits {
            if startTime > 0 { player.currentPlaybackTime = startTime }
            player.play()
        } else {
            // A stream that never reports back: treat it as failed after a while and try the next way.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, self.attempt == thisAttempt, self.preparing else { return }
                await self.recover(StreamTimeout(), attempt: thisAttempt, items: items, startTime: startTime, onError: onError)
            }
        }
    }

    /// After a stream starts: make sure it's one of ours. If the player went back to something else (the Music app's
    /// last song, when Apple Music wouldn't queue this one), stop it and try the next way.
    private func verify(attempt: Int, route: Route, items: MediaItemIndex, startTime: Double,
                        onError: @escaping @MainActor @Sendable (Error) -> Void) async {
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(500))
            guard attempt == self.attempt else { return }
            guard let item = player.nowPlayingItem else { continue }
            // Apple sometimes plays another version of the same song (clean, another album): the title counts too.
            let title = MediaKey.normalise(item.title ?? "")
            if run.contains(where: { $0.storeID == item.playbackStoreID || $0.id == item.persistentID
                || (!title.isEmpty && MediaKey.normalise($0.title) == title) }) {
                if route == .systemStream && tried.contains(.appStream) { Self.streamsViaSystem = true }
                return
            }
            player.pause()
            preparing = true
            await recover(WrongSong(), attempt: attempt, items: items, startTime: startTime, onError: onError)
            return
        }
    }

    private struct WrongSong: LocalizedError {
        var errorDescription: String? { "Apple Music played a different song." }
    }

    private struct StreamTimeout: LocalizedError {
        var errorDescription: String? { "Apple Music took too long to start the song." }
    }

    /// A start that reported an error: ignore it if the music is playing after all; otherwise try the next way.
    private func recover(_ error: Error, attempt failed: Int, items: MediaItemIndex, startTime: Double,
                         onError: @escaping @MainActor @Sendable (Error) -> Void) async {
        guard failed == attempt else { return }
        try? await Task.sleep(for: .seconds(1.2))
        guard failed == attempt else { return }
        preparing = false
        guard !isPlaying else { return }
        let canStream = run.allSatisfy(\.hasStoreID)
        let canQueueItems = run.allSatisfy { items[$0.id] != nil }
        let order: [Route] = [.appStream, .systemStream, .appItems]
        let next = order.first { r in
            !tried.contains(r) && (r == .appItems ? canQueueItems : canStream)
        }
        if let next {
            start(run, route: next, items: items, startTime: startTime, onError: onError)
        } else {
            onError(error)
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop(); run = []; tried = []; preparing = false; attempt += 1 }
    func seek(_ t: Double) { player.currentPlaybackTime = t }
    func skipToNext() { player.skipToNextItem() }
    func skipToPrevious() { player.skipToPreviousItem() }
    func restartItem() { player.skipToBeginning() }

    /// Wakes the system music player after an install or a recalibrate: stops whatever it held, then loads one
    /// library song without playing it, so the next tap plays straight away. Streams go back to trying the app's
    /// own player first.
    func recalibrate(with item: MPMediaItem?) {
        observe()
        stop()
        Self.streamsViaSystem = false
        player = appPlayer
        guard let item else { return }
        player.setQueue(with: MPMediaItemCollection(items: [item]))
        player.prepareToPlay { @Sendable _ in }
    }

    private func observe() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        for p: MPMusicPlayerController in [appPlayer, systemPlayer] {
            p.beginGeneratingPlaybackNotifications()
            let sender = ObjectIdentifier(p)
            center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: p, queue: .main) { @Sendable _ in
                MainActor.assumeIsolated { MusicEngine.shared?.itemChanged(from: sender) }
            }
            center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: p, queue: .main) { @Sendable _ in
                MainActor.assumeIsolated { MusicEngine.shared?.stateChanged(from: sender) }
            }
        }
    }

    private func itemChanged(from sender: ObjectIdentifier) {
        guard sender == ObjectIdentifier(player) else { return }
        onItemChange?(nowPlayingID)
    }

    private func stateChanged(from sender: ObjectIdentifier) {
        guard sender == ObjectIdentifier(player) else { return }
        onStateChange?()
    }

    /// The one engine, for notification callbacks.
    static weak var shared: MusicEngine?
    init() {
        player = MPMusicPlayerController.applicationQueuePlayer
        Self.shared = self
    }
}

extension Song {
    /// Has an Apple Music ID it can be streamed by.
    var hasStoreID: Bool { !storeID.isEmpty && storeID != "0" }
    /// A song from the Apple Music catalogue that isn't in the library (an artist page's Top Songs).
    var isCatalog: Bool { id & Song.catalogFlag != 0 }
    static let catalogFlag: UInt64 = 1 << 62
}
