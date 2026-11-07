import SwiftUI

/// Phase 0 home: the five spikes in the order to run them, and the report to send back.
struct SpikeHomeView: View {
    @State private var copied = false
    private let report = SpikeReport.shared

    /// D first (it picks the song the lock screen test uses), then A, B, C, E.
    private let order: [SpikeID] = [.libraryPlayback, .lockScreen, .intelligence, .deezer, .instagram]

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Phase 0 · Spike lab")
                        Text(AppBrand.name).font(.system(size: 56, weight: .regular, design: .serif))
                        Text("Run each test top to bottom, tap what you saw, then copy the report and paste it back.")
                            .font(.callout).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 12)

                    ForEach(Array(order.enumerated()), id: \.element) { index, spike in
                        NavigationLink(value: spike) { row(index + 1, spike) }
                            .buttonStyle(.plain)
                    }

                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = report.text
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.linerPrimary)
                            ShareLink(item: report.text) {
                                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                        .controlSize(.large)
                    }
                    .padding(.top, 8)
                }
                .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Spike lab")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SpikeID.self) { destination($0) }
    }

    private func row(_ step: Int, _ spike: SpikeID) -> some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: spike.symbol).font(.title2).frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("STEP \(step) · SPIKE \(spike.rawValue)").font(.system(size: 10, weight: .semibold)).tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(spike.title).font(.system(size: 20, design: .serif))
                }
                Spacer()
                VerdictBadge(verdict: report.verdict(spike))
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    @ViewBuilder private func destination(_ spike: SpikeID) -> some View {
        switch spike {
        case .libraryPlayback: LibrarySpikeView()
        case .lockScreen: LockScreenSpikeView()
        case .intelligence: IntelligenceSpikeView()
        case .deezer: DeezerSpikeView()
        case .instagram: InstagramSpikeView()
        }
    }
}

#Preview { NavigationStack { SpikeHomeView() }.preferredColorScheme(.dark) }
