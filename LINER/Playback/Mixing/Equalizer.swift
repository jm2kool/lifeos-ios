import Foundation

/// The equaliser for songs LINER. plays itself (mixtapes and unprotected files): ten bands, presets, on or off.
/// Apple Music songs are played by iOS, which never hands their sound to apps, so it can't reach them.
@MainActor @Observable
final class Equalizer {
    static let shared = Equalizer()
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    struct Preset: Identifiable, Hashable {
        let name: String
        let gains: [Float]
        var id: String { name }
    }

    static let presets: [Preset] = [
        Preset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        Preset(name: "Bass Boost", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        Preset(name: "Bass Reducer", gains: [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0]),
        Preset(name: "Vocal", gains: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        Preset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        Preset(name: "Loudness", gains: [5, 4, 1, 0, -1, 0, 0, 1, 4, 5]),
        Preset(name: "Late Night", gains: [3, 3, 2, 1, 0, 0, 1, 1, 0, -1]),
        Preset(name: "Acoustic", gains: [3, 3, 2, 1, 1, 1, 2, 3, 2, 1]),
        Preset(name: "Electronic", gains: [4, 4, 1, 0, -2, 1, 0, 1, 4, 5]),
        Preset(name: "Hip-Hop", gains: [5, 4, 1, 3, -1, -1, 1, -1, 2, 3]),
        Preset(name: "Rock", gains: [5, 4, 3, 1, -1, -1, 0, 2, 3, 4]),
        Preset(name: "Spoken Word", gains: [-3, -2, 0, 1, 3, 4, 4, 3, 1, -2]),
    ]

    var isOn: Bool { didSet { save(); onChange?() } }
    var gains: [Float] { didSet { save(); onChange?() } }
    var presetName: String { didSet { save() } }
    @ObservationIgnored var onChange: (() -> Void)?

    private init() {
        let d = UserDefaults.standard
        isOn = d.bool(forKey: "eq.on")
        let saved = (d.array(forKey: "eq.gains") as? [Double])?.map(Float.init) ?? []
        gains = saved.count == 10 ? saved : Array(repeating: 0, count: 10)
        presetName = d.string(forKey: "eq.preset") ?? "Flat"
    }

    func use(_ preset: Preset) {
        presetName = preset.name
        gains = preset.gains
    }

    /// What the bands should be right now (flat when off).
    var activeGains: [Float] { isOn ? gains : Array(repeating: 0, count: 10) }

    private func save() {
        let d = UserDefaults.standard
        d.set(isOn, forKey: "eq.on")
        d.set(gains.map(Double.init), forKey: "eq.gains")
        d.set(presetName, forKey: "eq.preset")
    }
}
