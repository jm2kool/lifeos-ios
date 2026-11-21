@preconcurrency import AVFoundation

/// One side of LINER.'s own deck: a file played in scheduled pieces, so a DJ mix's trims and loops are
/// seamless, with its own level for crossfades and song gain.
@MainActor
final class Deck {
    let index: Int
    let node = AVAudioPlayerNode()
    /// Song gain (a DJ mix's level), in dB, with no bands.
    let level = AVAudioUnitEQ(numberOfBands: 0)
    private(set) var file: AVAudioFile?
    private(set) var url: URL?
    /// The pieces of the file queued, in order, as (first frame, frame count).
    private var pieces: [(start: AVAudioFramePosition, count: AVAudioFrameCount)] = []
    /// Bumped whenever what's queued is thrown away, so a stale "finished" is ignored.
    private(set) var generation = 0
    /// Where playback stood when paused or stopped, for when the node has no time to report.
    private var heldTime: Double = 0

    init(index: Int) { self.index = index }

    var sampleRate: Double { file?.processingFormat.sampleRate ?? 44_100 }
    var duration: Double { file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0 }
    var isPlaying: Bool { node.isPlaying }

    /// Opens a file. Throws when it isn't audio this deck can read (the caller falls back to AVPlayer).
    func open(_ url: URL) throws {
        file = try AVAudioFile(forReading: url)
        self.url = url
        heldTime = 0
    }

    /// Queues the song from `time` following its DJ mix (trimmed start and end, a looped section), and calls
    /// `finished` with this generation when the last piece has been heard.
    func schedule(from time: Double, mix: SongMix?, finished: @escaping @Sendable (Int, Int) -> Void) {
        guard let file else { return }
        generation += 1
        node.stop()
        pieces = []
        let rate = sampleRate, length = file.length
        func frame(_ t: Double) -> AVAudioFramePosition { max(0, min(length, AVAudioFramePosition((t * rate).rounded()))) }
        let first = frame(max(time, mix?.start ?? 0))
        let last = frame(mix?.end ?? duration)
        guard last > first else { heldTime = time; return }
        if let loop = mix?.validLoop(duration: duration), frame(loop.end) > first {
            let ls = frame(loop.start), le = frame(loop.end)
            pieces.append((first, AVAudioFrameCount(le - first)))
            for _ in 0..<loop.repeats { pieces.append((ls, AVAudioFrameCount(le - ls))) }
            if last > le { pieces.append((le, AVAudioFrameCount(last - le))) }
        } else {
            pieces.append((first, AVAudioFrameCount(last - first)))
        }
        let gen = generation, deck = index
        for (i, piece) in pieces.enumerated() {
            let isLast = i == pieces.count - 1
            node.scheduleSegment(file, startingFrame: piece.start, frameCount: piece.count, at: nil,
                                 completionCallbackType: .dataPlayedBack) { @Sendable _ in
                if isLast { finished(deck, gen) }
            }
        }
        heldTime = Double(first) / rate
    }

    /// The position in the song (loops count back, as they sound).
    var currentTime: Double {
        guard let nodeTime = node.lastRenderTime, let t = node.playerTime(forNodeTime: nodeTime), t.sampleTime >= 0,
              !pieces.isEmpty else { return heldTime }
        var played = AVAudioFramePosition(Double(t.sampleTime) * sampleRate / t.sampleRate)
        for piece in pieces {
            if played < AVAudioFramePosition(piece.count) { return Double(piece.start + played) / sampleRate }
            played -= AVAudioFramePosition(piece.count)
        }
        let end = pieces.last.map { $0.start + AVAudioFramePosition($0.count) } ?? 0
        return Double(end) / sampleRate
    }

    func play() { node.play() }

    func pause() {
        heldTime = currentTime
        node.pause()
    }

    /// Stops and forgets what was queued (its "finished" won't arrive).
    func stop() {
        generation += 1
        node.stop()
        pieces = []
    }

    func setGain(_ db: Double) { level.globalGain = Float(max(-24, min(24, db))) }
}
