import SwiftUI
import PhotosUI

/// "What's this from?" Paste a YouTube Short, X/Twitter, TikTok, Instagram or Reddit link, pick a screenshot,
/// or describe a scene. Matinee reads the post and the text in its thumbnail, Apple Intelligence on the iPhone
/// works out what it's from, and TMDB confirms it.
struct FinderView: View {
    var initial: String? = nil
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var photo: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var screenshotText: [String] = []
    @State private var clip: ClipInfo?
    @State private var matches: [FinderMatch] = []
    @State private var step: Finder.Step?
    @State private var searched = false
    @FocusState private var focused: Bool

    private var busy: Bool { step != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(Intelligence.isAvailable ? "Apple Intelligence · on your iPhone" : "Reads the post and matches titles",
                              systemImage: Intelligence.isAvailable ? "apple.intelligence" : "text.magnifyingglass")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                        Text("What's this from?").font(.title2.weight(.bold))
                        Text("Paste a link to a YouTube Short, X post, TikTok or Reel — or describe the scene.")
                            .font(.subheadline).foregroundStyle(Theme.dim)
                    }

                    VStack(spacing: 10) {
                        TextField("Link, or “the one where they rob a casino with a pinch of…”", text: $input, axis: .vertical)
                            .lineLimit(1...5)
                            .focused($focused)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.search)
                            .onSubmit(run)
                        HStack(spacing: 8) {
                            PasteButton(payloadType: String.self) { strings in
                                guard let s = strings.first else { return }
                                Task { @MainActor in input = s; run() }
                            }
                            .buttonBorderShape(.capsule)
                            .labelStyle(.titleAndIcon)
                            .tint(Theme.card)
                            PhotosPicker(selection: $photo, matching: .images) {
                                Label("Screenshot", systemImage: "photo")
                            }
                            .buttonStyle(.glass)
                            Spacer()
                            Button(action: run) {
                                Image(systemName: busy ? "ellipsis" : "arrow.up").font(.headline).frame(width: 34, height: 34)
                                    .symbolEffect(.pulse, isActive: busy)
                            }
                            .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                            .disabled(busy || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && screenshot == nil))
                        }
                        .controlSize(.small)
                    }
                    .padding(14)
                    .background(Theme.card, in: .rect(cornerRadius: 20))

                    if let screenshot {
                        HStack(spacing: 10) {
                            Image(uiImage: screenshot).resizable().aspectRatio(contentMode: .fill).frame(width: 54, height: 54).clipShape(.rect(cornerRadius: 10))
                            Text(screenshotText.isEmpty ? "Screenshot added" : "Read \(screenshotText.count) lines of text from the screenshot")
                                .font(.caption).foregroundStyle(Theme.dim)
                            Spacer()
                            Button("Remove", systemImage: "xmark.circle.fill") { self.screenshot = nil; screenshotText = [] }
                                .labelStyle(.iconOnly).foregroundStyle(Theme.dim)
                        }
                    }

                    if let step { progress(step) }

                    if !matches.isEmpty {
                        Text(matches.first.map { $0.confidence > 0.75 } == true ? "FOUND IT" : "BEST GUESSES")
                            .font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.accent)
                        ForEach(Array(matches.enumerated()), id: \.element.id) { i, m in matchCard(m, top: i == 0) }
                    } else if searched && !busy {
                        EmptyState(symbol: "questionmark.video", title: "Couldn't place it",
                                   message: "Add a few words about the scene — an actor, a line, what happens — and try again.")
                    }

                    if let clip, !busy { readout(clip) }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .oledBackground()
            .navigationTitle("Find a film")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .onAppear {
                if let initial, !initial.isEmpty, input.isEmpty {
                    input = initial
                    run()
                } else {
                    focused = true
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        screenshot = img
                        screenshotText = await TicketReader.read(img).map(\.text)
                        run()
                    }
                    photo = nil
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func run() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !text.isEmpty || screenshot != nil else { return }
        focused = false
        matches = []
        clip = nil
        searched = false
        Task {
            var info: ClipInfo?
            var note = text
            if let url = Finder.link(in: text) {
                info = await Finder.read(url) { step = $0 }
                note = text.replacingOccurrences(of: url.absoluteString, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            clip = info
            let found = await Finder.find(clip: info, description: note, screenshotText: screenshotText) { step = $0 }
            withAnimation(.smooth) { matches = found; step = nil; searched = true }
            UINotificationFeedbackGenerator().notificationOccurred(found.isEmpty ? .warning : .success)
        }
    }

    private func progress(_ s: Finder.Step) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(Self.label(s))
            .foregroundStyle(Theme.dim)
            .contentTransition(.opacity)
        }
        .animation(.smooth, value: s)
    }

    private static func label(_ s: Finder.Step) -> String {
        switch s {
        case .reading(let p): return "Reading the \(p) post…"
        case .lookingAtFrame: return "Reading text in the video frame…"
        case .thinking: return "Working out what it's from…"
        case .checking: return "Checking TMDB…"
        }
    }

    private func matchCard(_ m: FinderMatch, top: Bool) -> some View {
        let saved = library.inWatchlist(m.film.id)
        return HStack(alignment: .top, spacing: 14) {
            Button { open(m.film) } label: { PosterView(film: m.film, width: top ? 96 : 64, corner: 8) }
                .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if m.film.isShow {
                        Text("TV").font(.caption2.weight(.heavy)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.list.opacity(0.25), in: .rect(cornerRadius: 4)).foregroundStyle(Theme.list)
                    }
                    Text(m.film.yearText).font(.caption).foregroundStyle(Theme.dim)
                    Spacer()
                    Text("\(Int(m.confidence * 100))%").font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(m.confidence > 0.7 ? Theme.watch : Theme.dim)
                }
                Text(m.film.title).font(top ? .title3.weight(.bold) : .headline).multilineTextAlignment(.leading)
                Text(m.reason).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 8) {
                    Button("Open", systemImage: "arrow.up.right") { open(m.film) }.buttonStyle(.glassProminent)
                    Button(saved ? "Saved" : "Watchlist", systemImage: saved ? "checkmark" : "clock") { library.toggleWatchlist(m.film) }
                        .buttonStyle(.glass)
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .filmContextMenu(m.film)
    }

    private func readout(_ c: ClipInfo) -> some View {
        DisclosureGroup("What Matinee read from \(c.platform)") {
            VStack(alignment: .leading, spacing: 10) {
                if let t = c.thumbnail {
                    RemoteImage(url: t, contentMode: .fit).frame(maxHeight: 160).clipShape(.rect(cornerRadius: 10))
                }
                Text(c.evidence.isEmpty ? "Nothing — the site didn't share any details. Try describing the scene." : c.evidence)
                    .font(.caption).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.top, 6)
        }
        .font(.footnote).tint(.white)
    }

    private func open(_ f: FilmRef) {
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            router.open(f)
        }
    }
}

/// On Search: the way into the finder.
struct FinderCard: View {
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.sheet = .finder(nil) } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkle.magnifyingglass").font(.title2).foregroundStyle(Theme.accent).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("What's this from?").font(.headline)
                    Text("Paste a Short, a post or a TikTok — or describe the scene").font(.subheadline).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
            }
            .padding(16)
            .contentShape(.rect(cornerRadius: 22))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}
