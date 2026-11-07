@preconcurrency import MediaPlayer
import UIKit

/// Lock screen and Control Centre. Library songs on the queue player get their Now Playing from the system;
/// for imported files we write it ourselves and answer the remote commands. Animated artwork joins in Phase 8.
@MainActor
final class NowPlayingManager {
    weak var coordinator: PlaybackCoordinator?
    private var ownsNowPlaying = false
    private var commandsRegistered = false
    private var artworkTask: Task<Void, Never>?
    private var artwork: (key: String, image: UIImage)?

    /// The lock screen's animated artwork (motion covers and Living Covers).
    let animated = AnimatedArtwork()
    init() { animated.nowPlaying = self }

    func useSystemNowPlaying() {
        guard ownsNowPlaying else { return }
        ownsNowPlaying = false
        removeCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func useOwnNowPlaying() {
        ownsNowPlaying = true
        registerCommands()
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        removeCommands()
        ownsNowPlaying = false
    }

    /// Writes the current item's info. For library songs only the extra keys are added on top of the system's.
    func update(elapsed: Double? = nil) {
        guard let c = coordinator, let item = c.current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist,
            MPMediaItemPropertyAlbumTitle: item.albumTitle,
            MPMediaItemPropertyPlaybackDuration: item.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed ?? c.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: c.isPlaying ? 1.0 : 0.0,
        ]
        let extra = animated.keys(for: item)
        guard ownsNowPlaying || !extra.isEmpty else { return }
        if let artwork, artwork.key == item.artworkKey {
            info[MPMediaItemPropertyArtwork] = Self.staticArtwork(artwork.image)
        } else {
            loadArtwork(for: item)
        }
        info.merge(extra) { _, new in new }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for item: QueueItem) {
        artworkTask?.cancel()
        artworkTask = Task {
            guard let image = await CoverArt.image(for: item, pixels: 1000), !Task.isCancelled else { return }
            artwork = (item.artworkKey, image)
            update()
        }
    }

    /// Built outside the main actor: the system calls the handler on its own queue.
    nonisolated static func staticArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    // MARK: Remote commands (own Now Playing only)

    private func registerCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { @Sendable _ in Self.onMain { $0.resume() } }
        center.pauseCommand.addTarget { @Sendable _ in Self.onMain { $0.pause() } }
        center.togglePlayPauseCommand.addTarget { @Sendable _ in Self.onMain { $0.togglePlayPause() } }
        center.nextTrackCommand.addTarget { @Sendable _ in Self.onMain { $0.next() } }
        center.previousTrackCommand.addTarget { @Sendable _ in Self.onMain { $0.previous() } }
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            let t = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            return Self.onMain { $0.seek(to: t) }
        }
    }

    private func removeCommands() {
        guard commandsRegistered else { return }
        commandsRegistered = false
        let c = MPRemoteCommandCenter.shared()
        for command in [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand, c.nextTrackCommand,
                        c.previousTrackCommand, c.changePlaybackPositionCommand] as [MPRemoteCommand] {
            command.removeTarget(nil)
        }
    }

    nonisolated private static func onMain(_ action: @escaping @MainActor @Sendable (PlaybackCoordinator) -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor in if let c = PlaybackCoordinator.shared { action(c) } }
        return .success
    }
}
