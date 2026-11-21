@preconcurrency import AVFoundation
import MediaPlayer
import SwiftUI

/// The phone's own volume, which is the only way to fade Apple Music songs (LINER. never gets their sound).
/// A tiny hidden volume view in the window lets LINER. move the volume without the system's volume overlay.
@MainActor
final class SystemVolume {
    static let shared = SystemVolume()
    fileprivate weak var view: MPVolumeView?

    /// 0…1, as the volume buttons set it.
    var current: Float { AVAudioSession.sharedInstance().outputVolume }

    /// Whether LINER. can move the volume (the hidden view is in place).
    var isAvailable: Bool { slider != nil }

    private var slider: UISlider? { view?.subviews.compactMap { $0 as? UISlider }.first }

    func set(_ value: Float) {
        guard let slider else { return }
        let v = max(0, min(1, value))
        guard abs(slider.value - v) > 0.002 else { return }
        slider.value = v
    }
}

/// Put once in the root view, out of sight.
struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 120, height: 30))
        view.alpha = 0.02
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        SystemVolume.shared.view = view
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Everything that wants the music quieter for a moment (the sleep timer, automix fades, a DJ mix's song
/// levels) gives a factor here; the product is applied to LINER.'s own player directly, and to Apple Music songs
/// through the phone's volume, which goes back to where you had it as soon as nothing needs it any more.
@MainActor
final class VolumeShaper {
    static let shared = VolumeShaper()
    private var factors: [String: Float] = [:]
    /// Your volume before LINER. started moving it (Apple Music songs only).
    private var base: Float?
    private var lastSet: Float?

    var product: Float { factors.values.reduce(1, *) }

    func set(_ name: String, _ factor: Float) {
        let f = max(0, min(1, factor))
        if f >= 0.999 { factors[name] = nil } else { factors[name] = f }
    }

    func clear(_ name: String) { factors[name] = nil }

    /// Applies the factors to whichever player is playing.
    func apply(engine: PlaybackCoordinator.Engine, local: LocalEngine) {
        let f = product
        local.outputVolume = engine == .local ? f : 1
        let volume = SystemVolume.shared
        if engine == .music, f < 0.999 {
            if base == nil { base = volume.current }
            // You moved the volume during a fade: that's your new level.
            if let lastSet, abs(volume.current - lastSet) > 0.05, let b = base, f > 0.05 { base = min(1, max(0, b + (volume.current - lastSet) / f)) }
            let target = (base ?? 1) * f
            volume.set(target)
            lastSet = target
        } else if let b = base {
            volume.set(b)
            base = nil
            lastSet = nil
        }
    }
}
