import SwiftUI

/// Spike E screen: send the same story three ways and record what Instagram opened with.
struct InstagramSpikeView: View {
    private let spike = InstagramSpike.shared

    var body: some View {
        SpikePage(spike: .instagram,
                  intro: "Matinee's code only sends still pictures. This sends a moving 9:16 background with the key com.instagram.sharedSticker.backgroundVideo, using Matinee's Facebook app ID. Each button opens Instagram; close the story without posting, come back, and tap what you saw.") {
            Card {
                SectionLabel("Story background")
                if spike.working { ProgressView("Rendering 1080×1920 loop…").font(.footnote) }
                if let story = spike.story {
                    Image(uiImage: story.preview).resizable().aspectRatio(9 / 16, contentMode: .fit).frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button(spike.story == nil ? "Make story video" : "Remake from test song") { Task { await spike.prepare() } }
                    .buttonStyle(.glass).disabled(spike.working)
            }
            ForEach(InstagramSpike.Kind.allCases, id: \.self) { kind in
                Card {
                    Text(kind.rawValue).font(.system(size: 20, design: .serif))
                    Button("Open in Instagram", systemImage: "camera.circle.fill") { Task { await spike.share(kind) } }
                        .buttonStyle(.glassProminent).disabled(spike.working)
                    ObservationButtons(spike: .instagram, question: "\(kind.rawValue): what did Instagram show?", options: options(for: kind))
                }
            }
        }
    }

    private func options(for kind: InstagramSpike.Kind) -> [(String, Verdict)] {
        switch kind {
        case .still:
            [("The cover as the story background", .works), ("Instagram opened but empty / error", .fails), ("Instagram didn't open", .fails)]
        default:
            [("The cover, MOVING, as the story background", .works), ("A still frame or just the colours", .partial),
             ("Instagram opened but empty / error", .fails), ("Instagram didn't open", .fails)]
        }
    }
}

#Preview { NavigationStack { InstagramSpikeView() }.preferredColorScheme(.dark) }
