import Foundation

/// Watches the music ten times a second and does what needs doing at the right moment: crossfades and fades
/// between songs (Automix and DJ mixes), a DJ mix's trims and loops for Apple Music songs, song levels, and the
/// sleep timer's slow fade.
@MainActor
final class MixDirector {
    static let shared = MixDirector()
    private weak var player: PlaybackCoordinator?
    private var task: Task<Void, Never>?
    /// The song being handled, and what's been done to it.
    private var itemID: String?
    private var startedAt = Date.now
    private var trimmed = false
    private var loopsDone = 0
    private var handedOver = false
    private var crossfadeFailed = false
    /// Fade the next song in over this many seconds (after an Apple Music fade-out).
    private var fadeInSeconds: Double = 0

    func attach(_ player: PlaybackCoordinator) {
        self.player = player
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let p = player else { return }
        let shaper = VolumeShaper.shared
        SleepTimer.shared.tick(p)
        guard let item = p.current, p.isPlaying else {
            shaper.apply(engine: p.engine, local: p.local)
            return
        }
        if item.id != itemID {
            // A new song: fade it in if the last one faded out.
            itemID = item.id
            startedAt = .now
            trimmed = false
            loopsDone = 0
            handedOver = false
            crossfadeFailed = false
        }
        let mix = p.mix(for: item)
        let t = p.currentTime, duration = p.duration
        let end = min(duration, mix?.end ?? duration)
        let own = p.engine == .local

        // Apple Music songs: trims and loops by seeking (LINER.'s own player does these seamlessly itself).
        if !own, let mix {
            if !trimmed, let start = mix.start, start > 1, Date.now.timeIntervalSince(startedAt) < 15 {
                if t > 0.2 { p.seek(to: start); trimmed = true }
            }
            if let loop = mix.validLoop(duration: duration), loopsDone < loop.repeats, t >= loop.end - 0.08, t < loop.end + 1 {
                loopsDone += 1
                p.seek(to: loop.start)
                return
            }
        }

        // The handover to the next song.
        let fade = mix?.transition ?? (Automix.mode == .crossfade ? Automix.seconds : 0)
        let hasNext = p.index + 1 < p.queue.count || p.repeatMode == .all
        var level: Float = 1
        if fade > 0, hasNext, p.repeatMode != .one, end - t <= fade, !handedOver, duration > fade * 2 {
            if own, !crossfadeFailed, p.crossfadeToNext(over: fade) {
                handedOver = true
                fadeInSeconds = 0
            } else {
                // Apple Music (or a song that can't cross over): fade out, move on, fade the next one in.
                crossfadeFailed = own
                level = Float(max(0, (end - t) / fade))
                if end - t <= 0.3 {
                    handedOver = true
                    fadeInSeconds = fade * 0.6
                    p.next()
                }
            }
        } else if !own, mix?.end != nil, t >= end - 0.15, !handedOver, fade == 0 {
            // A trimmed end without a fade: straight on.
            handedOver = true
            p.next()
        }
        // Fading the new song in.
        let since = Date.now.timeIntervalSince(startedAt)
        if fadeInSeconds > 0 {
            if since < fadeInSeconds { level = min(level, Float(since / fadeInSeconds)) } else { fadeInSeconds = 0 }
        }
        // A DJ mix's level for Apple Music songs (only quieter: the phone's volume can't go above where it is).
        if !own, let mix, mix.gainDB < 0 { level *= mix.gain }
        shaper.set("mix", level * level)
        shaper.apply(engine: p.engine, local: p.local)
    }
}
