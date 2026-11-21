@preconcurrency import AVFoundation

/// Plays the songs LINER. can play itself (mixtape tracks and unprotected library files), so it owns Now Playing.
/// Audio files go through two decks on an audio engine: real crossfades for Automix, a DJ mix's trims, loops
/// and levels, and the equaliser. Anything the engine can't read (a video file) plays through AVPlayer instead.
@MainActor
final class LocalEngine {
    let player = AVPlayer()
    var onEnd: (() -> Void)?
    private var endObserver: NSObjectProtocol?

    private let engine = AVAudioEngine()
    private let decks = [Deck(index: 0), Deck(index: 1)]
    private let submix = AVAudioMixerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 10)
    private var active = 0
    /// Playing through AVPlayer rather than a deck.
    private var usesPlayer = false
    private var built = false
    private var fadeTask: Task<Void, Never>?
    /// The level everything plays at (the sleep timer and fades), 0…1.
    var outputVolume: Float = 1 {
        didSet { engine.mainMixerNode.outputVolume = outputVolume; player.volume = outputVolume }
    }

    private var deck: Deck { decks[active] }

    var isPlaying: Bool { usesPlayer ? player.rate != 0 : deck.isPlaying }
    var currentTime: Double {
        if usesPlayer { let t = player.currentTime().seconds; return t.isFinite ? t : 0 }
        return deck.currentTime
    }
    /// Whether a crossfade can happen (both songs on decks).
    var canCrossfade: Bool { !usesPlayer && built }

    static weak var shared: LocalEngine?
    init() {
        Self.shared = self
        Equalizer.shared.onChange = { [weak self] in self?.applyEQ() }
    }

    // MARK: Loading

    func load(_ url: URL, startTime: Double = 0, mix: SongMix? = nil) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        cancelFade()
        decks[1 - active].stop()
        if (try? deck.open(url)) != nil, (try? prepareEngine(for: deck)) != nil {
            stopPlayer()
            usesPlayer = false
            deck.setGain(mix?.gainDB ?? 0)
            deck.node.volume = 1
            deck.schedule(from: startTime, mix: mix, finished: Self.deckFinished)
            deck.play()
        } else {
            deck.stop()
            usesPlayer = true
            loadPlayer(url, startTime: startTime)
        }
    }

    private func loadPlayer(_ url: URL, startTime: Double) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { LocalEngine.shared?.onEnd?() }
        }
        if startTime > 0 { seek(startTime) }
        player.play()
    }

    private func stopPlayer() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    /// Builds the graph once (two decks → their levels → a mixer → the equaliser → out) and connects a deck
    /// for its file's format.
    private func prepareEngine(for d: Deck) throws {
        guard let format = d.file?.processingFormat else { return }
        if !built {
            for x in decks { engine.attach(x.node); engine.attach(x.level) }
            engine.attach(submix)
            engine.attach(eq)
            setUpBands()
            engine.connect(submix, to: eq, format: nil)
            engine.connect(eq, to: engine.mainMixerNode, format: nil)
            built = true
            NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { @Sendable _ in
                MainActor.assumeIsolated { LocalEngine.shared?.restartAfterChange() }
            }
        }
        engine.connect(d.node, to: d.level, format: format)
        engine.connect(d.level, to: submix, fromBus: 0, toBus: d.index, format: format)
        if !engine.isRunning { try engine.start() }
    }

    private func setUpBands() {
        for (i, band) in eq.bands.enumerated() {
            band.filterType = i == 0 ? .lowShelf : (i == 9 ? .highShelf : .parametric)
            band.frequency = Equalizer.frequencies[i]
            band.bandwidth = 1
            band.bypass = false
        }
        applyEQ()
    }

    private func applyEQ() {
        let gains = Equalizer.shared.activeGains
        for (i, band) in eq.bands.enumerated() where i < gains.count { band.gain = gains[i] }
    }

    private func restartAfterChange() {
        guard built, !engine.isRunning else { return }
        let wasPlaying = decks.map(\.isPlaying)
        try? engine.start()
        for (d, on) in zip(decks, wasPlaying) where on { d.play() }
    }

    /// A deck reached the end of what it was given (called on an audio thread).
    private static let deckFinished: @Sendable (Int, Int) -> Void = { index, generation in
        Task { @MainActor in LocalEngine.shared?.finished(deck: index, generation: generation) }
    }

    private func finished(deck index: Int, generation: Int) {
        guard index == active, decks[index].generation == generation, !usesPlayer else { return }
        onEnd?()
    }

    // MARK: Transport

    func play() {
        if usesPlayer { player.play(); return }
        if !engine.isRunning { try? engine.start() }
        deck.play()
    }

    func pause() {
        if usesPlayer { player.pause(); return }
        cancelFade()
        decks[1 - active].stop()
        deck.pause()
    }

    func stop() {
        cancelFade()
        stopPlayer()
        for d in decks { d.stop() }
        if built { engine.pause() }
    }

    func seek(_ t: Double, mix: SongMix? = nil) {
        if usesPlayer {
            player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        let wasPlaying = deck.isPlaying
        deck.schedule(from: t, mix: mix, finished: Self.deckFinished)
        if wasPlaying { deck.play() }
    }

    // MARK: Crossfade

    /// Starts the next song on the other deck under this one and crosses over in `seconds`. False when it can't
    /// (the next file isn't readable, or this song plays through AVPlayer): the caller moves on the usual way.
    func crossfade(to url: URL, mix: SongMix?, over seconds: Double) -> Bool {
        guard canCrossfade else { return false }
        let out = deck, incoming = decks[1 - active]
        guard (try? incoming.open(url)) != nil, (try? prepareEngine(for: incoming)) != nil else { return false }
        cancelFade()
        incoming.setGain(mix?.gainDB ?? 0)
        incoming.node.volume = 0
        incoming.schedule(from: 0, mix: mix, finished: Self.deckFinished)
        incoming.play()
        // The song going out is no longer the active deck, so its own end isn't reported.
        active = incoming.index
        let outGeneration = out.generation
        fadeTask = Task { @MainActor [weak self] in
            let steps = max(1, Int(seconds * 30))
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(33))
                if Task.isCancelled { break }
                let p = Float(step) / Float(steps)
                // Equal-power curves keep the loudness even through the middle.
                incoming.node.volume = sin(p * .pi / 2)
                if out.generation == outGeneration { out.node.volume = cos(p * .pi / 2) }
            }
            incoming.node.volume = 1
            out.stop()
            out.node.volume = 1
            self?.fadeTask = nil
        }
        return true
    }

    private func cancelFade() {
        fadeTask?.cancel()
        fadeTask = nil
        deck.node.volume = 1
    }
}
