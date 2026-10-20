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
    var onTop: ((FilmRef?) -> Void)? = nil
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
        .onChange(of: index, initial: true) { _, i in onTop?(films.indices.contains(i) ? films[i] : nil) }
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

/// Drives the endless quiz: explores every genre first, then narrows in on your favourites
/// until your character is clear.
@Observable @MainActor
final class QuizEngine {
    var cards: [(film: FilmRef, genres: [String])] = []
    private(set) var exposure: [String: Double] = [:]
    private(set) var decisive = 0
    private(set) var likes = 0
    private(set) var failed = false
    private var topHistory: [[String]] = []
    private var seen = Set<String>()
    private var pages: [String: Int] = [:]
    private var loading = false
    private var rotation = 0

    static let main: Set<String> = ["Action", "Comedy", "Drama", "Horror", "Romance", "Sci-Fi", "Thriller",
                                    "Animation", "Crime", "Fantasy", "Adventure", "Mystery"]
    static func required(_ g: String) -> Double { main.contains(g) ? 2 : 1 }

    private func need(_ g: String) -> Double { max(0, Self.required(g) - exposure[g, default: 0]) }
    private var uncovered: [String] { Catalog.genres.filter { need($0) > 0 } }

    func start() async {
        cards = []; exposure = [:]; decisive = 0; likes = 0; topHistory = []; seen = []; pages = [:]; failed = false
        if let first = try? await TMDB.deck() {
            for c in first.prefix(14) where seen.insert(c.film.id).inserted { cards.append(c) }
        }
        if cards.isEmpty { await topUp() }
        if cards.isEmpty { failed = true }
    }

    /// Record a swipe. `liked == nil` means "haven't seen".
    func record(_ film: FilmRef, liked: Bool?, scores: [String: Double]) {
        guard let idx = cards.firstIndex(where: { $0.film.id == film.id }) else { return }
        for g in cards[idx].genres { exposure[g, default: 0] += liked == nil ? 0.5 : 1 }
        if let liked {
            decisive += 1
            if liked { likes += 1 }
            topHistory.append(Self.top(scores, 2))
        }
        reprioritize(after: idx)
        if cards.count - idx - 1 < 8 { Task { await topUp() } }
    }

    // MARK: Confidence

    static func top(_ scores: [String: Double], _ n: Int) -> [String] {
        scores.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(n).map(\.key)
    }

    private func separation(_ scores: [String: Double]) -> Double {
        let v = scores.values.sorted(by: >)
        let first = v.first ?? 0, third = v.count > 2 ? v[2] : 0
        return min(1, max(0, (first - third) / 3))
    }

    private var stable: Bool {
        guard topHistory.count >= 6 else { return false }
        let last = topHistory.suffix(6).map { Set($0) }
        return last.allSatisfy { $0 == last.last && $0.count == 2 }
    }

    func confidence(_ scores: [String: Double]) -> Double {
        let total = Catalog.genres.reduce(0) { $0 + Self.required($1) }
        let covered = Catalog.genres.reduce(0) { $0 + min(Self.required($1), exposure[$1, default: 0]) }
        let coverage = covered / total
        let stability = stable ? 1 : Double(min(topHistory.count, 6)) / 6 * 0.6
        let raw = 0.45 * coverage + 0.35 * separation(scores) + 0.2 * stability
        return isSure(scores) ? 1 : min(0.97, raw)
    }

    func isSure(_ scores: [String: Double]) -> Bool {
        uncovered.isEmpty && separation(scores) >= 0.66 && stable && likes >= 5 && decisive >= 15
    }

    var phase: String {
        if !uncovered.isEmpty { return "Exploring genres · \(Catalog.genres.count - uncovered.count) of \(Catalog.genres.count)" }
        return "Narrowing in on your taste"
    }

    // MARK: Supply

    /// Cards beyond the visible stack get re-ordered so the most useful ones come next.
    private func reprioritize(after idx: Int) {
        let keep = idx + 4   // leave the cards already stacked on screen alone
        guard cards.count > keep + 1 else { return }
        let tail = Array(cards[keep...])
        let exploring = !uncovered.isEmpty
        let leaders = Set(topHistory.last ?? [])
        let sorted = tail.map { c -> (c: (film: FilmRef, genres: [String]), score: Double) in
            let s = exploring ? c.genres.reduce(0) { $0 + need($1) } : c.genres.reduce(0) { $0 + (leaders.contains($1) ? 1 : 0.1) }
            return (c, s + Double.random(in: 0..<0.3))
        }.sorted { $0.score > $1.score }.map { $0.c }
        cards.replaceSubrange(keep..., with: sorted)
    }

    func topUp() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        for _ in 0..<3 {
            let target = nextTarget()
            let key = target.joined(separator: "+")
            let page = pages[key, default: 0] + 1
            pages[key] = page
            let fresh = await TMDB.deckPage(genres: target, page: page).filter { seen.insert($0.film.id).inserted }
            if !fresh.isEmpty { cards.append(contentsOf: fresh.shuffled().prefix(10)); return }
        }
    }

    private func nextTarget() -> [String] {
        // Still exploring: go to the genre we know least about.
        if let g = uncovered.shuffled().max(by: { need($0) < need($1) }) { return [g] }
        let leaders = topHistory.last ?? []
        rotation += 1
        switch rotation % 5 {
        case 0 where leaders.count == 2: return leaders                       // films mixing your top two
        case 1, 3: return leaders.first.map { [$0] } ?? [Catalog.genres.randomElement()!]
        case 2: return leaders.dropFirst().first.map { [$0] } ?? [Catalog.genres.randomElement()!]
        default: return [Catalog.genres.randomElement()!]                  // keep re-testing the rest
        }
    }
}

/// Swipe through films — as many as it takes — to build your film character.
struct TasteQuizView: View {
    @Environment(Taste.self) private var taste
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var engine = QuizEngine()
    @State private var result: Persona?
    @State private var top: FilmRef?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AmbientGlow(urls: result == nil ? (top?.poster.map { [$0] } ?? []) : [], intensity: 0.55)
            if let result {
                PersonaReveal(persona: result) { dismiss() }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                VStack(spacing: 14) {
                    header
                    if engine.cards.isEmpty {
                        Spacer()
                        if engine.failed {
                            EmptyState(symbol: "wifi.exclamationmark", title: "Couldn't load films", message: "Check your connection and try again.")
                        } else { ProgressView().tint(.white) }
                        Spacer()
                    } else {
                        SwipeDeck(films: engine.cards.map(\.film), middle: ("eye.slash", "Haven't seen"),
                                  onSwipe: { f, liked in
                                      taste.record(f, genres: genres(for: f), liked: liked)
                                      engine.record(f, liked: liked, scores: taste.profile.scores)
                                      if engine.isSure(taste.profile.scores) { reveal() }
                                  },
                                  onMiddle: { f in engine.record(f, liked: nil, scores: taste.profile.scores) },
                                  onTop: { top = $0 }) {
                            VStack(spacing: 12) {
                                ProgressView().tint(.white)
                                Text("Finding more films…").font(.subheadline).foregroundStyle(Theme.dim)
                            }
                            .task { await engine.topUp() }
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
            await engine.start()
        }
    }

    private var header: some View {
        let confidence = engine.confidence(taste.profile.scores)
        return VStack(spacing: 10) {
            HStack {
                Button("Skip") { taste.skipQuiz(); dismiss() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                Spacer()
                if engine.decisive >= 40 {
                    Button("Finish now") { reveal() }.font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
            Text("What's your film character?").font(.title2.weight(.heavy))
            Text("Swipe right on films you love, left on ones that aren't for you. We'll keep going until we really know you.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            VStack(spacing: 6) {
                ProgressView(value: confidence).tint(Theme.accent)
                    .animation(.smooth, value: confidence)
                HStack {
                    Text(engine.phase)
                    Spacer()
                    Text("\(Int(confidence * 100))% sure")
                }
                .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func genres(for f: FilmRef) -> [String] { engine.cards.first { $0.film.id == f.id }?.genres ?? [] }

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
    @State private var top: FilmRef?

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
                  onTap: { router.open($0) },
                  onTop: { top = $0 }) {
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
        .background(AmbientGlow(urls: top?.poster.map { [$0] } ?? [], intensity: 0.55))
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
