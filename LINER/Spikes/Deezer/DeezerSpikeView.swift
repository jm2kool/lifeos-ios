import SwiftUI

/// Spike C screen: look up your top artists on Deezer and show one portrait in black and white.
struct DeezerSpikeView: View {
    private let spike = DeezerSpike.shared
    @State private var custom = ""

    private var names: [String] {
        let top = LibrarySpike.shared.topArtists
        return top.isEmpty ? ["Taylor Swift", "A. R. Rahman", "The Weeknd", "Arijit Singh", "Lorde"] : top
    }

    var body: some View {
        SpikePage(spike: .deezer,
                  intro: "Looks up your 10 most-played artists on Deezer's free API and checks how many come back with a real photo. Uses sample names if you haven't run Library playback yet.") {
            if let portrait = spike.portrait {
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: portrait).resizable().scaledToFill().frame(height: 360).clipped()
                    LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                    Text(spike.matches.first { !$0.isPlaceholder }?.found ?? "")
                        .font(.system(size: 44, design: .serif)).padding(16)
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            Card {
                SectionLabel("Artists to try")
                Text(names.joined(separator: " · ")).font(.footnote).foregroundStyle(.white.opacity(0.7))
                Button(spike.running ? "Looking up…" : "Look them up", systemImage: "magnifyingglass") {
                    Task { await spike.run(names) }
                }
                .buttonStyle(.linerPrimary).disabled(spike.running)
                HStack {
                    TextField("Or type one artist", text: $custom).textFieldStyle(.roundedBorder)
                    Button("Go") { Task { await spike.run([custom]) } }.buttonStyle(.glass).disabled(custom.isEmpty)
                }
            }
            if !spike.matches.isEmpty {
                Card {
                    SectionLabel("Results")
                    ForEach(spike.matches) { m in
                        Button { if let u = m.url { Task { await spike.showPortrait(u) } } } label: {
                            HStack {
                                Image(systemName: m.isPlaceholder ? "person.crop.circle.badge.xmark" : "person.crop.circle.fill")
                                    .foregroundStyle(m.isPlaceholder ? .orange : .green)
                                Text(m.asked).font(.subheadline)
                                Spacer()
                                Text(m.found ?? "—").font(.caption).foregroundStyle(m.nameMatches ? .white.opacity(0.6) : .orange)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

#Preview { NavigationStack { DeezerSpikeView() }.preferredColorScheme(.dark) }
