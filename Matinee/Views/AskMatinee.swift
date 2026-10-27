import SwiftUI

/// "What are you in the mood for?" Apple Intelligence reads your watchlist (or your picks) on the phone and
/// suggests up to three, each with a reason. Without Apple Intelligence, a simpler matcher does its best.
struct AskMatineeSheet: View {
    @Environment(Library.self) private var library
    @Environment(Taste.self) private var taste
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var mood = ""
    @State private var source: Source = .watchlist
    @State private var picks: [AIPick] = []
    @State private var thinking = false
    @FocusState private var focused: Bool

    enum Source: String, CaseIterable { case watchlist = "My watchlist", forYou = "Picked for me" }

    private let ideas = ["Something short and funny", "A tense thriller for tonight", "Feel-good, with friends",
                         "Mind-bending sci-fi", "Cosy and comforting", "A good cry", "Date night", "Under 90 minutes"]

    private var pool: [FilmRef] { source == .watchlist ? library.doc.watchlist : taste.picks }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(Intelligence.isAvailable ? "Apple Intelligence · on your iPhone" : "Matching by genre and length",
                              systemImage: Intelligence.isAvailable ? "apple.intelligence" : "wand.and.stars")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                        Text("What are you in the mood for?").font(.title2.weight(.bold))
                    }
                    HStack(spacing: 10) {
                        TextField("e.g. something light, under two hours", text: $mood, axis: .vertical)
                            .lineLimit(1...3)
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit(ask)
                        Button(action: ask) {
                            Image(systemName: thinking ? "ellipsis" : "arrow.up")
                                .font(.headline).frame(width: 36, height: 36)
                                .symbolEffect(.pulse, isActive: thinking)
                        }
                        .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                        .disabled(mood.trimmingCharacters(in: .whitespaces).isEmpty || thinking || pool.isEmpty)
                    }
                    .padding(14)
                    .background(Theme.card, in: .rect(cornerRadius: 20))

                    Picker("From", selection: $source) {
                        ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if pool.isEmpty {
                        Text(source == .watchlist ? "Your watchlist is empty — save a few films first." : "Your picks are still loading. Try your watchlist.")
                            .font(.subheadline).foregroundStyle(Theme.dim)
                    }

                    if picks.isEmpty && !thinking {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(ideas, id: \.self) { idea in
                                    Button(idea) { mood = idea; ask() }.buttonStyle(.glass).controlSize(.small)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                    }

                    if thinking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking through \(min(pool.count, 45)) titles…").foregroundStyle(Theme.dim)
                        }
                        .padding(.top, 10)
                    }

                    ForEach(Array(picks.enumerated()), id: \.element.id) { i, p in
                        Button { open(p.film) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                PosterView(film: p.film, width: i == 0 ? 92 : 70, corner: 8)
                                VStack(alignment: .leading, spacing: 6) {
                                    if i == 0 { Text("BEST MATCH").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.accent) }
                                    Text(p.film.title).font(i == 0 ? .title3.weight(.bold) : .headline).multilineTextAlignment(.leading)
                                    Text(p.film.yearText).font(.caption).foregroundStyle(Theme.dim)
                                    Text(p.reason).font(.subheadline).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(Theme.card, in: .rect(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if !picks.isEmpty {
                        Button("Ask again", systemImage: "arrow.clockwise") { ask() }
                            .buttonStyle(.glass).frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .oledBackground()
            .navigationTitle("Ask Matinee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .onAppear { focused = true }
        }
        .presentationDragIndicator(.visible)
    }

    private func ask() {
        let m = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty, !thinking, !pool.isEmpty else { return }
        focused = false
        thinking = true
        let list = pool.shuffled()
        Task {
            let out = await Intelligence.pick(mood: m, from: list)
            withAnimation(.smooth) { picks = out; thinking = false }
            UINotificationFeedbackGenerator().notificationOccurred(out.isEmpty ? .warning : .success)
        }
    }

    private func open(_ f: FilmRef) {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            router.open(f)
        }
    }
}
