@preconcurrency import MediaPlayer
import SwiftUI

/// The single source of truth for playback (SPEC §5). Owns the queue, shuffle and repeat, and hands each
/// item to the right engine: library songs to `MusicEngine`, imported files to `LocalEngine`.
@MainActor @Observable
final class PlaybackCoordinator {
    enum Engine { case none, music, local }

    private(set) var queue: [QueueItem] = []
    private var unshuffled: [QueueItem] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var shuffle = false
    var repeatMode: RepeatMode = .off
    private(set) var engine: Engine = .none
    var errorMessage: String?
    /// A friendly confirmation (imports and saves), shown in the same banner.
    var notice: String?
    var showFullPlayer = false
    /// Bumped on every seek, so views reading time refresh at once.
    private(set) var seekGeneration = 0

    @ObservationIgnored let music = MusicEngine()
    @ObservationIgnored let local = LocalEngine()
    @ObservationIgnored let nowPlaying = NowPlayingManager()
    @ObservationIgnored private let library: LibraryService

    /// Hooks for the play log and anything else that cares when songs start and end.
    @ObservationIgnored var onFinished: ((PlayRecord) -> Void)?
    @ObservationIgnored var onStarted: ((QueueItem) -> Void)?

    @ObservationIgnored private var startedAt = Date.now
    @ObservationIgnored private var listened: Double = 0
    @ObservationIgnored private var lastTick: Date?
    /// The system player's position at the last tick, to tell a real end from a blip.
    @ObservationIgnored private var lastMusicTime: Double = 0
    /// A song the system player skipped without playing (it couldn't play the library copy): it's tried once
    /// more by streaming it from Apple Music instead of moving on.
    @ObservationIgnored private var forceStreamID: UInt64?
    @ObservationIgnored private var settleUntil = Date.distantPast
    private var settling: Bool { Date.now < settleUntil || music.preparing || awaitingStart }
    /// A new run was handed to the system player and it hasn't yet said it's playing our song. Until it does
    /// (or a few seconds pass), its notifications describe the old queue, and acting on them skipped songs —
    /// shuffling an album used to run through several before one played.
    @ObservationIgnored private var awaitingStartUntil = Date.distantPast
    private var awaitingStart: Bool {
        guard engine == .music, Date.now < awaitingStartUntil else { return false }
        if music.isPlaying, let id = current?.libraryID, music.nowPlayingID == id { awaitingStartUntil = .distantPast; return false }
        return true
    }

    static weak var shared: PlaybackCoordinator?

    init(library: LibraryService) {
        self.library = library
        Self.shared = self
        music.onItemChange = { [weak self] id in self?.musicItemChanged(id) }
        music.onStateChange = { [weak self] in self?.musicStateChanged() }
        local.onEnd = { [weak self] in self?.itemEnded() }
        nowPlaying.coordinator = self
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    var current: QueueItem? { queue.indices.contains(index) ? queue[index] : nil }
    var upNext: [QueueItem] { index + 1 < queue.count ? Array(queue[(index + 1)...]) : [] }
    var duration: Double { current?.duration ?? 0 }
    var currentTime: Double {
        switch engine {
        case .music: music.currentTime
        case .local: local.currentTime
        case .none: 0
        }
    }

    // MARK: Starting

    /// Replaces the queue and starts playing; opens the full player too (Settings → Listening), unless the
    /// caller is a player of its own, like the turntable.
    func play(_ items: [QueueItem], startAt: Int = 0, shuffled: Bool = false, openPlayer: Bool = true) {
        guard !items.isEmpty else { return }
        unshuffled = items
        shuffle = shuffled
        if openPlayer && Self.opensPlayer { showFullPlayer = true }
        if shuffled {
            queue = items.shuffled()
            // Start on a song that plays straight away (a downloaded or imported one) when there is one.
            if let k = queue.firstIndex(where: startsInstantly) { queue.swapAt(0, k) }
            start(at: 0)
        } else {
            queue = items
            start(at: min(max(0, startAt), items.count - 1))
        }
    }

    /// Plays without waiting on Apple Music's servers.
    private func startsInstantly(_ item: QueueItem) -> Bool {
        guard case .library(let s) = item else { return true }
        if s.playsInLINER { return true }
        let mediaItem = library.snapshot.items[s.id]
        return mediaItem != nil && !MusicEngine.streams(s, item: mediaItem)
    }

    func play(songs: [Song], startAt: Int = 0, shuffled: Bool = false) {
        play(songs.map(QueueItem.library), startAt: startAt, shuffled: shuffled)
    }

    /// Starts an item at once. Synchronous on purpose: the tap, the highlight and the sound happen together.
    private func start(at i: Int, time: Double = 0) {
        guard queue.indices.contains(i) else { stopAll(); return }
        finishCurrent()
        index = i
        resetListening()
        // The engines send a burst of item/state notifications while switching; ignore them briefly.
        settleUntil = .now.addingTimeInterval(1.2)
        let item = queue[i]
        switch item {
        case .library(let song) where song.playsInLINER:
            // Not copy-protected: our own player, so we own the lock screen (full-screen animated artwork).
            if engine == .music { music.stop() }
            engine = .local
            do {
                try local.load(song.assetURL!, startTime: time)
                isPlaying = true
                nowPlaying.useOwnNowPlaying()
            } catch {
                fail(Self.explain(error, item))
                return
            }
        case .library(let first):
            if engine == .local { local.stop() }
            nowPlaying.useSystemNowPlaying()
            // One run for the system player: iCloud and Apple Music songs stream by their Apple Music ID,
            // downloaded songs play as library items; the run ends where the kind changes.
            let items = library.snapshot.items
            let stream = MusicEngine.streams(first, item: items[first.id]) || (forceStreamID == first.id && first.hasStoreID)
            var run: [Song] = []
            var j = i
            while j < queue.count, run.count < 150, case .library(let s) = queue[j], !s.playsInLINER {
                let fits = stream ? s.hasStoreID : (items[s.id] != nil && !MusicEngine.streams(s, item: items[s.id]))
                guard fits else { break }
                run.append(s)
                j += 1
            }
            guard !run.isEmpty else { fail("“\(item.title)” isn't in your library any more."); return }
            engine = .music
            awaitingStartUntil = .now.addingTimeInterval(stream ? 15 : 4)
            music.load(run, items: items, stream: stream, startTime: time) { [weak self] error in
                guard let self, self.current?.id == item.id else { return }
                self.fail(Self.explain(error, item))
            }
            isPlaying = true
        case .local(let track):
            if engine == .music { music.stop() }
            engine = .local
            do {
                try local.load(track.fileURL, startTime: time)
                isPlaying = true
                nowPlaying.useOwnNowPlaying()
            } catch {
                fail("Couldn't play “\(track.title)”: \(error.localizedDescription)")
                return
            }
        }
        errorMessage = nil
        nowPlaying.update()
        onStarted?(item)
    }

    private func fail(_ message: String) {
        awaitingStartUntil = .distantPast
        isPlaying = false
        errorMessage = message
    }

    private func stopAll() {
        awaitingStartUntil = .distantPast
        finishCurrent()
        music.stop()
        local.stop()
        engine = .none
        isPlaying = false
        nowPlaying.clear()
    }

    /// Settings → Recalibrate and the connect screen: clears the queue and resets both engines.
    func recalibrate() {
        stopAll()
        queue = []
        unshuffled = []
        index = 0
        errorMessage = nil
        let first = library.snapshot.songs.first { !$0.isCloudOnly && !$0.playsInLINER }.flatMap { library.snapshot.items[$0.id] }
        music.recalibrate(with: first)
    }

    // MARK: Transport

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func pause() {
        switch engine { case .music: music.pause(); case .local: local.pause(); case .none: break }
        isPlaying = false
        nowPlaying.update()
    }

    func resume() {
        switch engine {
        case .music: music.play()
        case .local: local.play()
        case .none: if current != nil { start(at: index) }; return
        }
        isPlaying = true
        nowPlaying.update()
    }

    func next() {
        if index + 1 < queue.count { start(at: index + 1) }
        else if repeatMode == .all { start(at: 0) }
        else { seek(to: duration); pause() }
    }

    func previous() {
        if currentTime > 3 || index == 0 { seek(to: 0) } else { start(at: index - 1) }
    }

    func jump(to i: Int) { start(at: i) }

    func seek(to t: Double) {
        let clamped = min(max(0, t), max(0, duration - 0.5))
        lastMusicTime = clamped
        switch engine { case .music: music.seek(clamped); case .local: local.seek(clamped); case .none: break }
        seekGeneration += 1
        nowPlaying.update(elapsed: clamped)
    }

    func toggleShuffle() {
        guard let now = current else { shuffle.toggle(); return }
        if shuffle {
            queue = unshuffled
            index = unshuffled.firstIndex(of: now) ?? 0
        } else {
            unshuffled = queue
            var rest = queue
            rest.remove(at: index)
            queue = [now] + rest.shuffled()
            index = 0
        }
        shuffle.toggle()
    }

    func cycleRepeat() { repeatMode = repeatMode.next }

    /// Applies an edit to the queue (given the current index). Used by the queue editing extension.
    func editQueue(_ change: (inout [QueueItem], Int) -> Void) {
        change(&queue, index)
        if !shuffle { unshuffled = queue }
    }

    // MARK: Engine events

    private func musicItemChanged(_ id: UInt64?) {
        guard engine == .music, !settling else { return }
        // The system player blinks to "nothing playing" while it swaps queues: only a song that actually got to
        // its end counts as finished.
        guard let id else { if reachedEnd { itemEnded() }; return }
        if id == current?.libraryID { return }
        // A song from an earlier queue: nothing to do with ours.
        guard music.runIDs.contains(id) else { return }
        if repeatMode == .one { start(at: index); return }
        // Skipped before it made a sound: the library copy couldn't play. Stream it instead, once.
        if lastMusicTime < 1, Date.now.timeIntervalSince(startedAt) < 10, let song = current?.song,
           song.hasStoreID, !music.streaming, forceStreamID != song.id {
            forceStreamID = song.id
            start(at: index)
            return
        }
        if index + 1 < queue.count, queue[index + 1].libraryID == id {
            finishCurrent()
            index += 1
            resetListening()
            nowPlaying.update()
            if let c = current { onStarted?(c) }
        } else if index > 0, queue[index - 1].libraryID == id {
            finishCurrent()
            index -= 1
            resetListening()
        } else if let j = queue.firstIndex(where: { $0.libraryID == id }) {
            // The engine moved further along its run than one step (queue edits): follow it, without restarting.
            finishCurrent()
            index = j
            resetListening()
            nowPlaying.update()
            if let c = current { onStarted?(c) }
        }
    }

    private func musicStateChanged() {
        guard engine == .music else { return }
        let state = music.player.playbackState
        if settling { if state == .playing { isPlaying = true }; return }
        if state == .stopped && isPlaying && reachedEnd { itemEnded(); return }
        isPlaying = state == .playing
    }

    /// Whether the system player's song really got to its end, judged by the last position it reported (a
    /// song you just tapped hasn't, so a stray "stopped" can't skip it).
    private var reachedEnd: Bool {
        let d = duration
        return d <= 0 || lastMusicTime >= d - 5
    }

    /// The current item played to its end (local file, or the last song of a library run).
    private func itemEnded() {
        guard !settling else { return }
        if repeatMode == .one { start(at: index); return }
        if index + 1 < queue.count { start(at: index + 1) }
        else if repeatMode == .all { start(at: 0) }
        else { finishCurrent(); isPlaying = false; nowPlaying.update() }
    }

    // MARK: Listening time

    private func tick() {
        let now = Date.now
        if isPlaying, let last = lastTick { listened += now.timeIntervalSince(last) }
        lastTick = now
        if engine == .local { isPlaying = local.isPlaying }
        guard engine == .music, isPlaying, !settling else { return }
        // A song change whose notice was missed (or ignored while starting): catch up with the player.
        if music.isPlaying, let id = music.nowPlayingID, id != current?.libraryID, music.runIDs.contains(id) {
            musicItemChanged(id)
            return
        }
        lastMusicTime = music.currentTime
    }

    private func resetListening() {
        lastMusicTime = 0
        startedAt = .now
        listened = 0
        lastTick = .now
    }

    private func finishCurrent() {
        guard let item = current, listened > 1 else { return }
        onFinished?(PlayRecord(item: item, startedAt: startedAt, listened: listened, viaOwnPlayer: engine == .local))
        listened = 0
    }
}
