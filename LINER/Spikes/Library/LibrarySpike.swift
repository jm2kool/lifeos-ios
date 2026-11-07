@preconcurrency import MediaPlayer
import SwiftUI

/// Spike D: can a free-signed app read the library and play it through `applicationQueuePlayer`?
/// Also owns the song the lock screen spike (A) uses.
@MainActor @Observable
final class LibrarySpike {
    static let shared = LibrarySpike()

    private(set) var status = MPMediaLibrary.authorizationStatus()
    /// The most-played songs, for picking a test song and comparing play counts with the Music app.
    private(set) var topSongs: [MPMediaItem] = []
    private(set) var topArtists: [String] = []
    var selected: MPMediaItem?
    private(set) var stateText = "stopped"
    private(set) var nowPlayingTitle: String?

    let player = MPMusicPlayerController.applicationQueuePlayer
    private var observing = false
    /// Called when the queue player's item or state changes (the lock screen spike re-applies its info here).
    var onPlayerChange: (() -> Void)?

    private let report = SpikeReport.shared

    func requestAccess() async {
        let result = await Self.askForAccess()
        status = result
        report.log(.libraryPlayback, "Authorization: \(Self.describe(result))")
        if result == .authorized { scan() } else { report.set(.libraryPlayback, .fails, because: "No library permission") }
    }

    nonisolated private static func askForAccess() async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { @Sendable status in continuation.resume(returning: status) }
        }
    }

    /// Reads the whole library once and logs what it finds, timing it (§7 wants 10k songs under 1s).
    func scan() {
        let clock = ContinuousClock()
        let start = clock.now
        let songs = MPMediaQuery.songs().items ?? []
        let readTime = clock.now - start
        let sorted = songs.sorted { $0.playCount > $1.playCount }
        let sortTime = clock.now - start
        topSongs = Array(sorted.prefix(40))
        if selected == nil { selected = topSongs.first }

        var artistPlays: [String: Int] = [:]
        for s in songs { artistPlays[s.albumArtist ?? s.artist ?? "Unknown", default: 0] += s.playCount }
        topArtists = artistPlays.sorted { $0.value > $1.value }.prefix(10).map(\.key)

        let albums = MPMediaQuery.albums().collections?.count ?? 0
        let withStoreID = songs.filter { !$0.playbackStoreID.isEmpty && $0.playbackStoreID != "0" }.count
        let cloud = songs.filter(\.isCloudItem).count
        let protected = songs.filter(\.hasProtectedAsset).count
        let withArt = songs.prefix(200).filter { $0.artwork != nil }.count
        let totalPlays = songs.reduce(0) { $0 + $1.playCount }

        report.log(.libraryPlayback, "Songs \(songs.count), albums \(albums), total plays \(totalPlays.formatted())")
        report.log(.libraryPlayback, "Read \(readTime.formatted(.units(allowed: [.milliseconds]))), read+sort \(sortTime.formatted(.units(allowed: [.milliseconds])))")
        report.log(.libraryPlayback, "storeID set: \(withStoreID), cloud-only: \(cloud), protected (Apple Music): \(protected), artwork in first 200: \(withArt)")
        for s in topSongs.prefix(5) {
            report.log(.libraryPlayback, "Top: \(s.title ?? "?") – \(s.artist ?? "?") · \(s.playCount) plays · last \(s.lastPlayedDate?.formatted(date: .abbreviated, time: .omitted) ?? "never")")
        }
    }

    // MARK: Playback

    func play(_ item: MPMediaItem) {
        selected = item
        startObserving()
        player.setQueue(with: MPMediaItemCollection(items: [item]))
        report.log(.libraryPlayback, "setQueue: \(item.title ?? "?") (protected \(item.hasProtectedAsset), cloud \(item.isCloudItem), storeID \(item.playbackStoreID.isEmpty ? "none" : item.playbackStoreID))")
        let started = Date.now
        player.prepareToPlay { @Sendable error in
            let message = error.map { "\($0.localizedDescription) [\(($0 as NSError).domain) \(($0 as NSError).code)]" }
            Task { @MainActor in LibrarySpike.shared.prepared(message, since: started) }
        }
    }

    private func prepared(_ error: String?, since started: Date) {
        let ms = Int(Date.now.timeIntervalSince(started) * 1000)
        if let error {
            report.log(.libraryPlayback, "prepareToPlay FAILED after \(ms) ms: \(error)")
            report.set(.libraryPlayback, .fails, because: "prepareToPlay error")
            return
        }
        report.log(.libraryPlayback, "prepareToPlay OK in \(ms) ms, calling play()")
        player.play()
        Task {
            try? await Task.sleep(for: .seconds(4))
            checkProgress()
        }
    }

    /// Four seconds after play(), check the clock actually moved.
    private func checkProgress() {
        let t = player.currentPlaybackTime
        let state = Self.describe(player.playbackState)
        report.log(.libraryPlayback, "After 4s: state \(state), time \(String(format: "%.1f", t))s, nowPlayingItem \(player.nowPlayingItem?.title ?? "nil")")
        if player.playbackState == .playing && t > 1 {
            report.set(.libraryPlayback, .works, because: "Audio clock advanced to \(String(format: "%.1f", t))s")
        } else {
            report.set(.libraryPlayback, .fails, because: "Not playing after 4s")
        }
    }

    func togglePause() { player.playbackState == .playing ? player.pause() : player.play() }
    func skipForward() { player.currentPlaybackTime += 15 }
    func stop() { player.stop() }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange, .MPMusicPlayerControllerPlaybackStateDidChange] {
            center.addObserver(forName: name, object: player, queue: .main) { @Sendable note in
                let which = note.name == .MPMusicPlayerControllerNowPlayingItemDidChange ? "item changed" : "state changed"
                MainActor.assumeIsolated { LibrarySpike.shared.playerChanged(which) }
            }
        }
    }

    private func playerChanged(_ which: String) {
        stateText = Self.describe(player.playbackState)
        nowPlayingTitle = player.nowPlayingItem?.title
        report.log(.libraryPlayback, "Notification: \(which) → \(stateText), \(nowPlayingTitle ?? "nil")")
        onPlayerChange?()
    }

    // MARK: Words

    static func describe(_ s: MPMediaLibraryAuthorizationStatus) -> String {
        switch s {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not asked yet"
        @unknown default: "unknown"
        }
    }

    static func describe(_ s: MPMusicPlaybackState) -> String {
        switch s {
        case .playing: "playing"
        case .paused: "paused"
        case .stopped: "stopped"
        case .interrupted: "interrupted"
        case .seekingForward, .seekingBackward: "seeking"
        @unknown default: "unknown"
        }
    }
}
