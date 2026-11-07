@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
import SwiftUI

/// Spike A: does the lock screen go full-screen when we hand it 3:4 animated artwork?
/// Tried twice: with a library song on `applicationQueuePlayer`, and with a local file on our own AVPlayer.
@MainActor @Observable
final class NowPlayingSpike {
    static let shared = NowPlayingSpike()

    enum Mode: String { case library = "Library song · applicationQueuePlayer", local = "Local file · AVPlayer" }

    private(set) var mode: Mode?
    private(set) var tall: LoopVideoMaker.Output?
    private(set) var square: LoopVideoMaker.Output?
    private(set) var cover: UIImage?
    private(set) var coverTitle = ""
    private(set) var working = false
    var includeSquare = true
    var reapplyOnChanges = true
    private(set) var applyCount = 0

    private var avPlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var commandsRegistered = false
    private var localTitle = "LINER. test tone"
    private let report = SpikeReport.shared
    private let lib = LibrarySpike.shared

    var supportedKeys: String {
        let keys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
        return keys.isEmpty ? "none" : keys.map { "\($0)" }.sorted().joined(separator: ", ")
    }
    var tallSupported: Bool { MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork) }

    // MARK: Covers

    /// Builds the 3:4 and 1:1 loops from the selected song's artwork (or a placeholder).
    func prepareCovers() async {
        let item = lib.selected
        let art = item?.artwork?.image(at: CGSize(width: 1400, height: 1400))
        let image = art ?? LoopVideoMaker.placeholderCover(title: "LINER.")
        cover = image
        coverTitle = item?.albumTitle ?? "Placeholder"
        working = true
        defer { working = false }
        report.log(.lockScreen, "Supported animated keys: \(supportedKeys)")
        report.log(.lockScreen, "Making Living Covers from \(art == nil ? "placeholder" : "artwork of \(coverTitle)") \(Int(image.size.width))×\(Int(image.size.height))")
        let clock = ContinuousClock()
        let start = clock.now
        do {
            async let t = LoopVideoMaker.make(from: image, width: 1080, height: 1440, name: "tall")
            async let s = LoopVideoMaker.make(from: image, width: 1080, height: 1080, name: "square")
            tall = try await t
            square = try await s
            report.log(.lockScreen, "Living Covers ready in \((clock.now - start).formatted(.units(allowed: [.seconds, .milliseconds])))")
        } catch {
            report.log(.lockScreen, "Living Cover FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: Run the test

    func startLibrary() async {
        guard let item = lib.selected else { report.log(.lockScreen, "Pick a song in spike D first"); return }
        if tall == nil { await prepareCovers() }
        stopLocal()
        removeCommands()
        mode = .library
        lib.onPlayerChange = { [weak self] in
            guard let self, self.reapplyOnChanges, self.mode == .library else { return }
            self.apply(reason: "queue player change")
        }
        lib.play(item)
        try? await Task.sleep(for: .seconds(1.5))
        apply(reason: "after play()")
        await verify()
    }

    func startLocal(file: URL? = nil) async {
        if tall == nil { await prepareCovers() }
        lib.stop()
        lib.onPlayerChange = nil
        mode = .local
        do {
            let url: URL
            if let file { url = file } else { url = try await ToneMaker.make() }
            localTitle = file?.deletingPathExtension().lastPathComponent ?? "LINER. test tone"
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = AVQueuePlayer()
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            avPlayer = player
            player.play()
            registerCommands()
            report.log(.lockScreen, "AVPlayer playing \(url.lastPathComponent)")
        } catch {
            report.log(.lockScreen, "AVPlayer setup FAILED: \(error.localizedDescription)")
            return
        }
        try? await Task.sleep(for: .seconds(0.5))
        apply(reason: "after AVPlayer play()")
        await verify()
    }

    func stopAll() {
        lib.stop()
        stopLocal()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        mode = nil
    }

    private func stopLocal() {
        avPlayer?.pause()
        looper = nil
        avPlayer = nil
    }

    // MARK: Now Playing

    /// Writes the full now playing info: text, static art, and the animated 3:4 (and 1:1) artwork.
    func apply(reason: String) {
        guard let mode, let tall else { return }
        var info: [String: Any] = [:]
        switch mode {
        case .library:
            let item = lib.player.nowPlayingItem ?? lib.selected
            info[MPMediaItemPropertyTitle] = item?.title ?? "Unknown"
            info[MPMediaItemPropertyArtist] = item?.artist ?? ""
            info[MPMediaItemPropertyAlbumTitle] = item?.albumTitle ?? ""
            info[MPMediaItemPropertyPlaybackDuration] = item?.playbackDuration ?? 0
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = lib.player.currentPlaybackTime
            info[MPNowPlayingInfoPropertyPlaybackRate] = lib.player.playbackState == .playing ? 1.0 : 0.0
        case .local:
            info[MPMediaItemPropertyTitle] = localTitle
            info[MPMediaItemPropertyArtist] = "Mixtape test"
            info[MPMediaItemPropertyAlbumTitle] = coverTitle
            info[MPMediaItemPropertyPlaybackDuration] = avPlayer?.currentItem?.duration.seconds.nonNaN ?? 90
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = avPlayer?.currentTime().seconds.nonNaN ?? 0
            info[MPNowPlayingInfoPropertyPlaybackRate] = Double(avPlayer?.rate ?? 0)
        }
        if let cover { info[MPMediaItemPropertyArtwork] = Self.staticArtwork(cover) }
        let albumID = lib.selected.map { String($0.albumPersistentID) } ?? "placeholder"
        info[MPNowPlayingInfoProperty3x4AnimatedArtwork] = Self.animated(id: "living-3x4-\(albumID)", tall)
        if includeSquare, let square {
            info[MPNowPlayingInfoProperty1x1AnimatedArtwork] = Self.animated(id: "living-1x1-\(albumID)", square)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        applyCount += 1
        report.log(.lockScreen, "[\(mode == .library ? "library" : "local")] nowPlayingInfo written (#\(applyCount), \(reason))")
    }

    /// Reads the info back a moment later to see if the system kept our keys.
    private func verify() async {
        try? await Task.sleep(for: .seconds(2.5))
        let keys = MPNowPlayingInfoCenter.default().nowPlayingInfo?.keys.map { $0 } ?? []
        let kept = keys.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork)
        report.log(.lockScreen, "Read back after 2.5s: \(keys.count) keys, 3:4 animated key \(kept ? "still there" : "GONE")")
    }

    /// Built outside the main actor: the system calls these handlers on its own queue.
    nonisolated private static func staticArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    nonisolated private static func animated(id: String, _ output: LoopVideoMaker.Output) -> MPMediaItemAnimatedArtwork {
        let preview = output.preview, video = output.video
        return MPMediaItemAnimatedArtwork(artworkID: id,
                                          previewImageRequestHandler: { @Sendable size in
                                              Task { @MainActor in SpikeReport.shared.log(.lockScreen, "System asked for \(id) preview at \(Int(size.width))×\(Int(size.height))") }
                                              return preview
                                          },
                                          videoAssetFileURLRequestHandler: { @Sendable size in
                                              Task { @MainActor in SpikeReport.shared.log(.lockScreen, "System asked for \(id) VIDEO at \(Int(size.width))×\(Int(size.height))") }
                                              return video
                                          })
    }

    // MARK: Remote commands (local mode only; the queue player brings its own)

    private func registerCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { @Sendable _ in
            Task { @MainActor in NowPlayingSpike.shared.avPlayer?.play(); NowPlayingSpike.shared.apply(reason: "remote play") }
            return .success
        }
        c.pauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in NowPlayingSpike.shared.avPlayer?.pause(); NowPlayingSpike.shared.apply(reason: "remote pause") }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in
                let s = NowPlayingSpike.shared
                if s.avPlayer?.rate == 0 { s.avPlayer?.play() } else { s.avPlayer?.pause() }
                s.apply(reason: "remote toggle")
            }
            return .success
        }
    }

    private func removeCommands() {
        guard commandsRegistered else { return }
        commandsRegistered = false
        let c = MPRemoteCommandCenter.shared()
        for command in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand] { command.removeTarget(nil) }
    }
}

private extension Double {
    var nonNaN: Double? { isFinite ? self : nil }
}
