@preconcurrency import AVFoundation
import SwiftUI

/// Something in the crate: an album, a mixtape or a mood playlist.
struct VinylRecord: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let year: Int?
    let albumID: UInt64?
    let coverData: Data?
    let tracks: [QueueItem]
    /// What the record opens when you tap it in the crate.
    var source: Source? = nil

    enum Source: Hashable {
        case album(Album)
        case mixtape(Mixtape)
        case mood(MoodPlaylist)
    }

    static func == (a: VinylRecord, b: VinylRecord) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// The crate's filters (SPEC §6.16).
enum CrateFilter: String, CaseIterable, Identifiable {
    case recent = "Recent", all = "All albums", mostPlayed = "Most played", pinned = "Pinned", mixtapes = "Mixtapes", moods = "Mood Playlists"
    var id: String { rawValue }
}

/// Needle drop and crackle, made on the phone the first time (original sounds, nothing to license).
@MainActor
final class VinylSounds {
    static let shared = VinylSounds()
    private var pop: AVAudioPlayer?
    private var crackle: AVAudioPlayer?

    static var enabled: Bool { UserDefaults.standard.object(forKey: "needleSounds") as? Bool ?? true }

    /// Makes the sounds ahead of time so the first needle drop is instant.
    func prepare() { if Self.enabled { load() } }

    func needleDrop() {
        guard Self.enabled else { return }
        load()
        // Apple Music songs play in the system player: mix with it so the pop never pauses or delays the music.
        if PlaybackCoordinator.shared?.engine != .local {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        pop?.currentTime = 0
        pop?.play()
        crackle?.currentTime = 0
        crackle?.volume = 0.22
        crackle?.play()
    }

    func stopCrackle() { crackle?.setVolume(0, fadeDuration: 0.6) }

    private func load() {
        guard pop == nil else { return }
        let dir = URL.cachesDirectory
        let popURL = dir.appending(path: "liner-needle.caf"), crackleURL = dir.appending(path: "liner-crackle.caf")
        if !FileManager.default.fileExists(atPath: popURL.path) { Self.write(popURL, seconds: 0.35, make: Self.popSample) }
        if !FileManager.default.fileExists(atPath: crackleURL.path) { Self.write(crackleURL, seconds: 3.5, make: Self.crackleSample) }
        pop = try? AVAudioPlayer(contentsOf: popURL)
        crackle = try? AVAudioPlayer(contentsOf: crackleURL)
        pop?.volume = 0.5
        pop?.prepareToPlay()
        crackle?.prepareToPlay()
    }

    private static func write(_ url: URL, seconds: Double, make: (Int, Double) -> Float) {
        let rate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * rate)),
              let data = buffer.floatChannelData?[0],
              let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return }
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) { data[i] = make(i, rate) }
        try? file.write(from: buffer)
    }

    /// A soft thump with a little hiss: the needle landing.
    private static func popSample(_ i: Int, _ rate: Double) -> Float {
        let t = Double(i) / rate
        let thump = sin(2 * .pi * 70 * t) * exp(-t * 28)
        let hiss = Double.random(in: -1...1) * exp(-t * 18) * 0.25
        return Float((thump + hiss) * 0.8)
    }

    /// Quiet surface noise with random dust clicks, looped smoothly at the ends.
    private static func crackleSample(_ i: Int, _ rate: Double) -> Float {
        let t = Double(i) / rate
        var v = Double.random(in: -1...1) * 0.02
        if Double.random(in: 0...1) < 0.0009 { v += Double.random(in: -1...1) * 0.6 }
        let edge = min(1, t / 0.2, (3.5 - t) / 0.2)
        return Float(v * edge)
    }
}
