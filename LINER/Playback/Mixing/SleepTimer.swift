import SwiftUI

/// Stops the music after a while, the end of this song, or the end of the queue, fading it out slowly over the
/// last minute or so first. The volume goes back to where it was once the music has stopped.
@MainActor @Observable
final class SleepTimer {
    static let shared = SleepTimer()

    enum Mode: Equatable {
        case minutes(Int)
        case endOfSong
        case endOfQueue
    }

    private(set) var mode: Mode?
    /// Seconds left, refreshed ten times a second while it runs.
    private(set) var remaining: Double = 0
    private var endsAt: Date?
    private var songID: String?

    /// How long the fade at the end lasts (Settings → Listening).
    static var fadeSeconds: Double {
        let v = UserDefaults.standard.double(forKey: "sleep.fadeSeconds")
        return v > 0 ? v : 90
    }

    var isOn: Bool { mode != nil }

    func start(_ mode: Mode, player: PlaybackCoordinator) {
        self.mode = mode
        songID = player.current?.id
        if case .minutes(let m) = mode { endsAt = .now.addingTimeInterval(Double(m) * 60) } else { endsAt = nil }
        tick(player)
    }

    /// More time on a running timer.
    func extend(minutes: Int, player: PlaybackCoordinator) {
        let base = max(0, remaining)
        mode = .minutes(Int((base / 60).rounded(.up)) + minutes)
        endsAt = .now.addingTimeInterval(base + Double(minutes) * 60)
        tick(player)
    }

    func cancel() {
        mode = nil
        endsAt = nil
        remaining = 0
        VolumeShaper.shared.clear("sleep")
    }

    /// Called by the mix director: works out the time left, fades, and pauses at the end.
    func tick(_ player: PlaybackCoordinator) {
        guard let mode else { return }
        let t = player.currentTime
        switch mode {
        case .minutes:
            remaining = endsAt.map { $0.timeIntervalSinceNow } ?? 0
        case .endOfSong:
            // The song it was set on has ended.
            if player.current?.id != songID { remaining = 0 } else { remaining = max(0, player.duration - t) }
        case .endOfQueue:
            remaining = max(0, player.duration - t) + player.upNext.reduce(0) { $0 + $1.duration }
        }
        // Songs are stopped just before they end, so the next one never starts.
        var stopAt = 0.4
        if case .minutes = mode { stopAt = 0 }
        guard player.isPlaying || remaining <= stopAt else { return }
        let fade = min(Self.fadeSeconds, mode == .endOfSong ? max(10, player.duration * 0.3) : Self.fadeSeconds)
        if remaining <= stopAt {
            player.pause()
            cancel()
            // Let the pause land before the volume comes back.
            VolumeShaper.shared.set("sleep", 0)
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                VolumeShaper.shared.clear("sleep")
            }
        } else if remaining < fade {
            // A gentle curve: most of the drop happens towards the end.
            let x = remaining / fade
            VolumeShaper.shared.set("sleep", Float(x * x))
        } else {
            VolumeShaper.shared.clear("sleep")
        }
    }

    /// "12:34" left, for the badge.
    var label: String {
        let s = Int(remaining.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
