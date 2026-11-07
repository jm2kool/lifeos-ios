import SwiftUI

/// Spike B screen: check availability, then time a recipe and a reorder.
struct IntelligenceSpikeView: View {
    private let spike = IntelligenceSpike.shared
    @State private var vibe = "rainy late-night drive, a bit sad but hopeful"

    var body: some View {
        SpikePage(spike: .intelligence,
                  intro: "Checks that the on-device Apple Intelligence model is available, then times the two calls the mood playlists will make: a recipe from your words, and ordering a 40-song shortlist.") {
            Card {
                SectionLabel("Availability")
                Text(spike.availability).font(.subheadline)
                Button("Check again") { spike.check() }.buttonStyle(.glass)
            }
            Card {
                SectionLabel("Your vibe")
                TextField("Describe a vibe", text: $vibe, axis: .vertical).textFieldStyle(.roundedBorder)
                Button(spike.running ? "Thinking…" : "Run the model", systemImage: "sparkles") {
                    Task { await spike.run(vibe: vibe) }
                }
                .buttonStyle(.linerPrimary).disabled(spike.running || !spike.available)
                if let r = spike.recipeText { Text(r).font(.footnote).textSelection(.enabled) }
                if let o = spike.orderText { Text(o).font(.footnote).foregroundStyle(.white.opacity(0.7)) }
            }
        }
        .onAppear { spike.check() }
    }
}

#Preview { NavigationStack { IntelligenceSpikeView() }.preferredColorScheme(.dark) }
