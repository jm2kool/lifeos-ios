import SwiftUI

/// A Tinder-style stack of full-screen film cards. Drag or tap the buttons to swipe.
struct SwipeDeck<Empty: View>: View {
    let films: [FilmRef]
    var likeLabel = "LOVE"
    var nopeLabel = "NOPE"
    var likeSymbol = "heart.fill"
    var likeColor = Theme.heart
    var middle: (symbol: String, label: String)? = nil
    var onSwipe: (FilmRef, Bool) -> Void
    var onMiddle: ((FilmRef) -> Void)? = nil
    var onTap: ((FilmRef) -> Void)? = nil
    @ViewBuilder var empty: Empty

    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var flying: CGFloat = 0     // -1 left, 1 right while a card animates out

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if index >= films.count {
                    empty.transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    ForEach(Array(films.enumerated().filter { $0.offset >= index && $0.offset < index + 3 }.reversed()), id: \.element.id) { i, f in
                        let depth = CGFloat(i - index)
                        DeckCard(film: f, likeLabel: likeLabel, nopeLabel: nopeLabel, likeColor: likeColor,
                                 lean: depth == 0 ? drag.width : 0)
                            .scaleEffect(1 - depth * 0.05)
                            .offset(y: depth * 14)
                            .offset(depth == 0 ? drag : .zero)
                            .rotationEffect(.degrees(depth == 0 ? Double(drag.width / 22) : 0), anchor: .bottom)
                            .allowsHitTesting(depth == 0)
                            .zIndex(-depth)
                            .gesture(dragGesture(f))
                            .onTapGesture { onTap?(f) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if index < films.count {
                HStack(spacing: 22) {
                    roundButton("xmark", size: 62, color: .white) { swipe(films[index], right: false) }
                        .accessibilityLabel(nopeLabel.capitalized)
                    if let middle {
                        roundButton(middle.symbol, size: 50, color: .white.opacity(0.85)) {
                            let f = films[index]; onMiddle?(f); advance(direction: 0)
                        }
                        .accessibilityLabel(middle.label)
                    }
                    roundButton(likeSymbol, size: 62, color: likeColor) { swipe(films[index], right: true) }
                        .accessibilityLabel(likeLabel.capitalized)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: index)
    }

    private func dragGesture(_ f: FilmRef) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                let predicted = v.predictedEndTranslation.width
                if abs(v.translation.width) > 110 || abs(predicted) > 380 {
                    swipe(f, right: (abs(predicted) > abs(v.translation.width) ? predicted : v.translation.width) > 0)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    private func swipe(_ f: FilmRef, right: Bool) {
        UIImpactFeedbackGenerator(style: right ? .medium : .light).impactOccurred()
        onSwipe(f, right)
        advance(direction: right ? 1 : -1)
    }

    private func advance(direction: CGFloat) {
        withAnimation(.easeIn(duration: 0.22)) {
            drag = direction == 0 ? CGSize(width: 0, height: -900) : CGSize(width: direction * 700, height: drag.height + 40)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(230))
            drag = .zero
            index += 1
        }
    }

    private func roundButton(_ symbol: String, size: CGFloat, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

/// One card: the textless poster edge to edge, the film's logo, and LOVE / NOPE stamps as you drag.
struct DeckCard: View {
    let film: FilmRef
    var likeLabel = "LOVE"
    var nopeLabel = "NOPE"
    var likeColor = Theme.heart
    var lean: CGFloat = 0
    @State private var art: FilmArt?
    @State private var detail: FilmDetail?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay { RemoteImage(url: art?.poster ?? film.largePoster ?? film.poster) }
                .clipped()
            LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.75), location: 0.8),
                                   .init(color: .black.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 8) {
                TitleArt(title: film.title, logo: art?.logo, aspect: art?.logoAspect ?? 3, maxWidth: 240, maxHeight: 90, fontSize: 32)
                HStack(spacing: 6) {
                    Text(film.yearText)
                    if let g = detail?.genres.prefix(2), !g.isEmpty { Text("·"); Text(g.joined(separator: ", ")) }
                    if let m = detail?.runtimeMinutes, m > 0 { Text("·"); Text(filmClock(TimeInterval(m * 60))) }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)

            stamp(likeLabel, color: likeColor, angle: -14).opacity(Double(max(0, min(1, lean / 90))))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(26)
            stamp(nopeLabel, color: .white, angle: 14).opacity(Double(max(0, min(1, -lean / 90))))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(26)
        }
        .clipShape(.rect(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Theme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .contentShape(.rect(cornerRadius: 32))
        .task(id: film.id) {
            art = await Catalog.art(film.id)
            detail = try? await Catalog.detail(film.id)
        }
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Taste quiz

/// Swipe through films to build your film character.
struct TasteQuizView: View {
    @Environment(Taste.self) private var taste
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [(film: FilmRef, genres: [String])] = []
    @State private var failed = false
    @State private var result: Persona?
    private let goal = 20

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let result {
                PersonaReveal(persona: result) { dismiss() }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                VStack(spacing: 14) {
                    header
                    if cards.isEmpty {
                        Spacer()
                        if failed {
                            EmptyState(symbol: "wifi.exclamationmark", title: "Couldn't load films", message: "Check your connection and try again.")
                        } else { ProgressView().tint(.white) }
                        Spacer()
                    } else {
                        SwipeDeck(films: cards.map(\.film), middle: ("eye.slash", "Haven't seen"),
                                  onSwipe: { f, liked in
                                      taste.record(f, genres: genres(for: f), liked: liked)
                                      if taste.profile.seen >= goal { reveal() }
                                  },
                                  onMiddle: { _ in }) {
                            VStack(spacing: 14) {
                                Text("That's the deck!").font(.title2.bold())
                                Button("Show my character") { reveal() }.buttonStyle(.glassProminent).controlSize(.large)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.5), value: result)
        .task {
            taste.beginQuiz()
            do { cards = try await TMDB.deck() } catch { failed = true }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Skip") { taste.skipQuiz(); dismiss() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                Spacer()
                if taste.profile.seen >= 8 {
                    Button("Done") { reveal() }.font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
            Text("What's your film character?").font(.title2.weight(.heavy))
            Text("Swipe right on films you love, left on ones that aren't for you.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            ProgressView(value: Double(min(taste.profile.seen, goal)), total: Double(goal)).tint(Theme.accent)
                .padding(.horizontal, 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func genres(for f: FilmRef) -> [String] { cards.first { $0.film.id == f.id }?.genres ?? [] }

    private func reveal() {
        guard result == nil else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        result = taste.finish()
        Task { await taste.refreshPicks(library: library, force: true) }
    }
}

/// The big reveal: your film character.
struct PersonaReveal: View {
    let persona: Persona
    var onDone: () -> Void
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text(persona.emoji)
                    .font(.system(size: 96))
                    .scaleEffect(shown ? 1 : 0.3)
                    .rotationEffect(.degrees(shown ? 0 : -30))
                    .padding(.top, 40)
                VStack(spacing: 6) {
                    Text("YOU'RE").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(Theme.dim)
                    Text(persona.name).font(.system(size: 34, weight: .heavy, design: .serif)).multilineTextAlignment(.center)
                }
                Text(persona.blurb).font(.body).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 12)
                PersonaCard(persona: persona, compact: false)
                Button(action: onDone) { Text("Start exploring").font(.body.weight(.semibold)).frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).controlSize(.large)
            }
            .padding(24)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.1)) { shown = true } }
    }
}

/// Genre bars, era and traits — used on the reveal and on your profile.
struct PersonaCard: View {
    let persona: Persona
    var compact = true
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if compact {
                HStack(spacing: 12) {
                    Text(persona.emoji).font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YOUR FILM CHARACTER").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.dim)
                        Text(persona.name).font(.title3.weight(.bold))
                    }
                }
            }
            VStack(spacing: 8) {
                ForEach(Array(persona.topGenres.enumerated()), id: \.offset) { i, g in
                    HStack(spacing: 10) {
                        Text(g).font(.subheadline.weight(.semibold)).frame(width: 100, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(i == 0 ? Theme.accent : Theme.accent.opacity(0.55))
                                        .frame(width: geo.size.width * CGFloat(i < persona.genreShares.count ? persona.genreShares[i] : 0.3))
                                }
                        }
                        .frame(height: 10)
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([persona.era] + persona.traits, id: \.self) { t in
                        Text(t).font(.caption.weight(.semibold)).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.16), in: .capsule)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

// MARK: - Lists as a swipe deck

enum DeckAction {
    case watchlist   // right = add to watchlist
    case tonight     // right = watch it tonight (starts Intermission tracking and opens the film)
    case like        // right = like
}

/// Any list, opened full screen as a swipe deck. The toolbar button flips to the normal view.
struct FilmDeckScreen: View {
    let films: [FilmRef]
    let action: DeckAction
    @Binding var deckMode: Bool
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(Watching.self) private var watching
    @State private var rightCount = 0
    @State private var round = 0

    var body: some View {
        SwipeDeck(films: films, likeLabel: labels.like, nopeLabel: labels.nope, likeSymbol: labels.symbol, likeColor: labels.color,
                  onSwipe: { f, right in
                      guard right else { return }
                      rightCount += 1
                      switch action {
                      case .watchlist: if !library.inWatchlist(f.id) { library.toggleWatchlist(f) } else { library.toast = Toast(text: "Already in your watchlist", symbol: "clock.fill") }
                      case .like: if !library.isLiked(f.id) { library.toggleLike(f) }
                      case .tonight:
                          watching.start(f, runtime: Catalog.cached(f.id)?.runtimeMinutes)
                          router.open(f)
                      }
                  },
                  onTap: { router.open($0) }) {
            VStack(spacing: 16) {
                Text("🍿").font(.system(size: 64))
                Text("That's all \(films.count)").font(.title2.weight(.bold))
                Text(summary).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Go again") { round += 1; rightCount = 0 }.buttonStyle(.glass).controlSize(.large)
                    Button("Show as list") { withAnimation { deckMode = false } }.buttonStyle(.glassProminent).controlSize(.large)
                }
            }
            .padding(30)
        }
        .id(round)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var labels: (like: String, nope: String, symbol: String, color: Color) {
        switch action {
        case .watchlist: return ("WANT", "SKIP", "clock.fill", Theme.list)
        case .tonight: return ("TONIGHT", "LATER", "play.fill", Theme.accent)
        case .like: return ("LOVE", "MEH", "heart.fill", Theme.heart)
        }
    }

    private var summary: String {
        switch action {
        case .watchlist: return rightCount == 0 ? "Nothing caught your eye this time." : "\(rightCount) added to your watchlist."
        case .tonight: return "Nothing tonight? Your watchlist will be here."
        case .like: return rightCount == 0 ? "No new likes this round." : "\(rightCount) more films liked."
        }
    }
}

/// Toolbar button to flip between the swipe deck and the normal list.
struct DeckToggle: ToolbarContent {
    @Binding var deckMode: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(deckMode ? "List view" : "Swipe", systemImage: deckMode ? "square.grid.2x2" : "rectangle.stack") {
                withAnimation(.smooth) { deckMode.toggle() }
            }
        }
    }
}
