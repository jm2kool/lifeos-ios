import SwiftUI

/// Settings → Listening → Automix, sleep timer and equaliser.
struct SoundSettingsView: View {
    @AppStorage("automix.mode") private var automix = Automix.Mode.off.rawValue
    @AppStorage("automix.seconds") private var seconds = 6.0
    @AppStorage("sleep.fadeSeconds") private var sleepFade = 90.0
    @State private var showEQ = false

    var body: some View {
        Form {
            Section {
                Toggle("Automix", isOn: Binding(get: { automix == Automix.Mode.crossfade.rawValue },
                                                set: { automix = ($0 ? Automix.Mode.crossfade : .off).rawValue }))
                if automix == Automix.Mode.crossfade.rawValue {
                    VStack(alignment: .leading) {
                        Text("Handover · \(Int(seconds)) seconds")
                        Slider(value: $seconds, in: 2...12, step: 1)
                    }
                }
            } header: { Text("Automix") } footer: {
                Text("Your mixtapes and your own files cross over: the next song starts under the last one. Apple Music songs fade out and the next fades in (iOS doesn't let apps play two Apple Music songs at once). A DJ mix on a playlist sets its own handovers.")
            }
            Section {
                VStack(alignment: .leading) {
                    Text("Fade out over \(sleepFade >= 60 ? "\(Int(sleepFade / 60)) min\(sleepFade >= 120 ? "s" : "")" : "\(Int(sleepFade)) s")")
                    Slider(value: $sleepFade, in: 30...300, step: 30)
                }
            } header: { Text("Sleep timer") } footer: {
                Text("Start it from ••• in the player. The music fades slowly before it stops, then your volume goes back to where it was.")
            }
            Section {
                Button("Equaliser…") { showEQ = true }
            } footer: {
                Text("The equaliser works on what \(AppBrand.name) plays itself. Apple Music songs use the Music app's EQ in iPhone Settings.")
            }
        }
        .navigationTitle("Sound")
        .sheet(isPresented: $showEQ) { EqualizerView() }
    }
}

#Preview { NavigationStack { SoundSettingsView() }.environment(PreviewData.player).preferredColorScheme(.dark) }
