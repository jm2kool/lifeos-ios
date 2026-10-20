import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var shelves: [HomeShelf: [FilmRef]] = [:]
    @State private var failed = false
    @State private var heroIndex: Int? = 0
    @State private var errorText: String?
    @AppStorage("tmdbToken") private var token = ""

    private var connected: Bool { !token.isEmpty || Catalog.hasToken }

    private var hero: [FilmRef] { Array((shelves[.trending] ?? []).filter { $0.backdrop != nil }.prefix(8)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                greeting
                if connected { heroCarousel } else { TMDBConnectCard() }
                if !library.doc.watchlist.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Up next", subtitle: "From your watchlist") {
                            NavigationLink("See all", value: CollectionRoute.watchlist)
                        }
                        PosterRow(films: Array(library.doc.watchlist.prefix(15)))
                    }
                }
                ForEach(HomeShelf.allCases) { s in
                    if let films = shelves[s], !films.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: s.title) { NavigationLink("See all", value: CollectionRoute.shelf(s)) }
                            PosterRow(films: s == .trending ? Array(films.dropFirst(min(3, films.count))) : films)
                        }
                    }
                }
                if connected && failed && shelves.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Couldn't load films").font(.headline)
                            Text(errorText ?? "Check your connection and pull down to retry.").font(.subheadline).foregroundStyle(Theme.dim)
                            Button("Try again") { Task { await load(force: true) } }
                                .buttonStyle(.glass).controlSize(.small).padding(.top, 6)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .background(Theme.card, in: .rect(cornerRadius: 22))
                    .padding(.horizontal, 16)
                }
                genres
                if !library.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Your recent watches") {
                            Button("Diary") { router.tab = .diary }
                        }
                        PosterRow(films: Array(library.entries.prefix(12).map(\.film)), width: 96)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .oledBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load(force: true) }
        .task(id: token) { if connected { await load(force: true) } }
    }

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.dim)
                Text(greetingText).font(.largeTitle.weight(.heavy))
            }
            Spacer()
            Button { router.sheet = .settings } label: { Avatar(profile: library.doc.profile, size: 40) }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
    }

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: .now)
        let part = h < 12 ? "Morning" : h < 17 ? "Afternoon" : "Evening"
        let first = library.doc.profile.name.split(separator: " ").first.map(String.init)
        return first.map { "\(part), \($0)" } ?? "Good \(part.lowercased())"
    }

    @ViewBuilder private var heroCarousel: some View {
        if hero.isEmpty {
            if !failed {
                RoundedRectangle(cornerRadius: 28).fill(Theme.card)
                    .frame(height: 440).padding(.horizontal, 20)
                    .overlay { ProgressView() }
            }
        } else {
            VStack(spacing: 14) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(hero.enumerated()), id: \.element.id) { i, f in
                            HeroCard(film: f).containerRelativeFrame(.horizontal) { w, _ in w - 40 }.id(i)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $heroIndex)
                .scrollIndicators(.hidden)
                HStack(spacing: 6) {
                    ForEach(hero.indices, id: \.self) { i in
                        Capsule().fill(i == (heroIndex ?? 0) ? Color.white : Color.white.opacity(0.25))
                            .frame(width: i == (heroIndex ?? 0) ? 18 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: heroIndex)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var genres: some View {
        let half = (Catalog.genres.count + 1) / 2
        let rows = [Array(Catalog.genres.prefix(half)), Array(Catalog.genres.dropFirst(half))]
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Browse by genre")
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 8) {
                            ForEach(rows[r], id: \.self) { g in
                                NavigationLink(value: GenreRoute(name: g)) {
                                    Text(g).font(.subheadline.weight(.semibold)).fixedSize()
                                }
                                .buttonStyle(.glass)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func load(force: Bool = false) async {
        failed = false
        errorText = nil
        await withTaskGroup(of: (HomeShelf, [FilmRef]?, String?).self) { g in
            for s in HomeShelf.allCases {
                g.addTask {
                    do { let r = try await Catalog.shelf(s); return (s, r, nil) } catch { return (s, nil, error.localizedDescription) }
                }
            }
            for await (s, films, err) in g {
                if let films { withAnimation(.smooth) { shelves[s] = films } }
                if let err { errorText = err }
            }
        }
        if shelves.values.allSatisfy(\.isEmpty) { failed = true }
    }
}

struct HeroCard: View {
    let film: FilmRef
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NavigationLink(value: film) {
                ZStack {
                    // Color.clear sets the size; the image fills it without widening the card.
                    Color.clear
                        .frame(height: 440)
                        .overlay { RemoteImage(url: film.backdrop ?? film.poster) }
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.2), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                }
                .frame(height: 440)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(film.title)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 14) {
                    PosterView(film: film, width: 84, corner: 8)
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRENDING").font(.caption2.weight(.heavy)).tracking(1.4).foregroundStyle(Theme.accent)
                        Text(film.title).font(.title2.weight(.bold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(film.yearText).font(.subheadline).foregroundStyle(Theme.dim)
                    }
                }
                .allowsHitTesting(false)
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { router.sheet = .log(film, nil) } label: {
                            Label("Log", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        Button { library.toggleWatchlist(film) } label: {
                            Label(library.inWatchlist(film.id) ? "Saved" : "Watchlist",
                                  systemImage: library.inWatchlist(film.id) ? "checkmark" : "clock")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    .controlSize(.large)
                }
            }
            .padding(18)
        }
        .frame(height: 440)
        .clipShape(.rect(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.line, lineWidth: 0.5).allowsHitTesting(false))
    }
}

struct Avatar: View {
    let profile: Profile
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.accent, Theme.heart], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white)
            if let a = profile.avatar { RemoteImage(url: a).clipShape(Circle()) }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
    }
    private var initials: String {
        let parts = profile.name.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "🎬" : String(parts)
    }
}

/// Shown until a TMDB token is added — the one bit of setup Matinee needs.
struct TMDBConnectCard: View {
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MatineeMark().frame(width: 44, height: 44).scaleEffect(0.7)
                Text("Connect TMDB").font(.title2.weight(.bold))
            }
            Text("Matinee gets films, posters and cast from TMDB — the same database Letterboxd uses. It's free: make an account, open Settings → API, and copy the **API Read Access Token**.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            Link(destination: URL(string: "https://www.themoviedb.org/settings/api")!) {
                Label("Get a free token", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass).controlSize(.large)
            TextField("Paste your token", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .font(.footnote.monospaced())
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14)
                .background(Theme.card, in: .rect(cornerRadius: 16))
            Button {
                Catalog.setToken(draft)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: { Text("Connect").font(.body.weight(.semibold)).frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent).controlSize(.large)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 16)
    }
}
