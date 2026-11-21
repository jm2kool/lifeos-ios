import SwiftUI

/// The equaliser: on or off, a preset, and ten bands to drag. It works on what LINER. plays itself.
struct EqualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var player

    var body: some View {
        @Bindable var eq = Equalizer.shared
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Toggle("Equaliser", isOn: $eq.isOn).font(.headline)
                    if player.engine == .music {
                        Label("This song is from Apple Music. iOS plays Apple Music songs itself and doesn't let apps change their sound, so the equaliser works on your mixtapes and your own files. For Apple Music, use Settings → Apps → Music → EQ.",
                              systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    presets(eq)
                    bands(eq).opacity(eq.isOn ? 1 : 0.4).disabled(!eq.isOn)
                    Button("Open Settings", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.footnote)
                }
                .padding(16)
            }
            .background(Palette.background)
            .navigationTitle("Equaliser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func presets(_ eq: Equalizer) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Equalizer.presets) { p in
                    let on = eq.presetName == p.name && eq.gains == p.gains
                    Button {
                        withAnimation(.liner) { eq.use(p) }
                        if !eq.isOn { eq.isOn = true }
                    } label: {
                        Text(p.name).font(.subheadline.weight(.medium)).padding(.horizontal, 12).frame(height: 34)
                            .background(Capsule().fill(on ? Color.white : Color.clear))
                            .foregroundStyle(on ? Color.black : Color.white)
                            .overlay(Capsule().stroke(Palette.stroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func bands(_ eq: Equalizer) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<10, id: \.self) { i in
                VStack(spacing: 8) {
                    Text(String(format: "%+.0f", eq.gains[i])).font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Palette.label)
                    BandSlider(value: Binding(get: { eq.gains[i] }, set: { v in
                        eq.gains[i] = v
                        eq.presetName = "Custom"
                    }))
                    .frame(height: 220)
                    Text(label(Equalizer.frequencies[i])).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.label)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    private func label(_ f: Float) -> String { f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))" }
}

/// One band: drag up or down, −12 … +12 dB, snapping to whole decibels.
struct BandSlider: View {
    @Binding var value: Float

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let y = h * CGFloat((12 - value) / 24)
            ZStack(alignment: .top) {
                Capsule().fill(Palette.stroke).frame(width: 4).frame(maxHeight: .infinity)
                Rectangle().fill(Palette.faint).frame(width: 14, height: 1).offset(y: h / 2)
                Capsule().fill(.white).frame(width: 4, height: abs(y - h / 2)).offset(y: min(y, h / 2))
                Circle().fill(.white).frame(width: 20, height: 20).shadow(radius: 3).offset(y: y - 10)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let v = 12 - Float(g.location.y / max(1, h)) * 24
                let snapped = max(-12, min(12, v.rounded()))
                if snapped != value { value = snapped; UISelectionFeedbackGenerator().selectionChanged() }
            })
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(value)) decibels")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(12, value + 1)
            case .decrement: value = max(-12, value - 1)
            @unknown default: break
            }
        }
    }
}

#Preview { EqualizerView().environment(PreviewData.player).preferredColorScheme(.dark) }
