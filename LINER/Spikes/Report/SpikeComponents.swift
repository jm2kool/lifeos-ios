import SwiftUI

/// The verdict as a small coloured capsule.
struct VerdictBadge: View {
    let verdict: Verdict
    var body: some View {
        Text(verdict.rawValue)
            .font(.system(size: 10, weight: .bold)).tracking(1.5)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(verdict == .untested ? .white.opacity(0.5) : .black)
            .background(verdict.color, in: Capsule())
    }
}

/// "What did you see?" buttons for things only a person looking at the phone can judge.
struct ObservationButtons: View {
    let spike: SpikeID
    let question: String
    /// Each option: label, verdict it implies.
    let options: [(String, Verdict)]
    /// When set, the pick goes here instead of becoming the spike's verdict (for spikes with several tests).
    var onPick: ((Verdict) -> Void)?
    @State private var picked: String? = nil

    init(spike: SpikeID, question: String, options: [(String, Verdict)], onPick: ((Verdict) -> Void)? = nil) {
        self.spike = spike
        self.question = question
        self.options = options
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(question)
            ForEach(options, id: \.0) { option in
                Button {
                    picked = option.0
                    if let onPick {
                        SpikeReport.shared.log(spike, "\(question) → \(option.0)")
                        onPick(option.1)
                    } else {
                        SpikeReport.shared.set(spike, option.1, because: "\(question) → \(option.0)")
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack {
                        Image(systemName: picked == option.0 ? "checkmark.circle.fill" : "circle")
                        Text(option.0).multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The spike's running log, newest last.
struct SpikeLogView: View {
    let spike: SpikeID
    var body: some View {
        let lines = SpikeReport.shared.lines(spike)
        Card {
            SectionLabel("Log")
            if lines.isEmpty {
                Text("Nothing yet.").font(.footnote).foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.75))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// Shared page chrome for a spike: serif title, explanation, content, then log.
struct SpikePage<Content: View>: View {
    let spike: SpikeID
    let intro: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SectionLabel("Spike \(spike.rawValue)")
                    VerdictBadge(verdict: SpikeReport.shared.verdict(spike))
                }
                Text(spike.title).font(.system(size: 32, weight: .regular, design: .serif))
                Text(intro).font(.callout).foregroundStyle(.white.opacity(0.7))
                content
                SpikeLogView(spike: spike)
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SpikePage(spike: .deezer, intro: "Preview of the spike page chrome.") {
            Card { ObservationButtons(spike: .deezer, question: "What did you see?", options: [("It worked", .works), ("It didn't", .fails)]) }
        }
    }
    .preferredColorScheme(.dark)
}
