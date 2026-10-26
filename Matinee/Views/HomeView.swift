import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(Taste.self) private var taste
    @State private var shelves: [HomeShelf: [FilmRef]] = [:]
    @State private var failed = false
    @State private var heroPage = 0
    @State private var errorText: String?
    @AppStorage("tmdbToken") private var token = ""

    private var connected: Bool { !token.isEmpty || Catalog.hasToken }

    /// The page glow follows the hero film on screen, mixed with what's next for you.
    private var glowFilms: [FilmRef] {
        var out: [FilmRef] = []
        if hero.indices.contains(heroPage) { out.append(hero[heroPage]) }
        out += taste.picks.prefix(1)
        out += library.doc.watchlist.prefix(1)
        out += (shelves[.topRated] ?? []).prefix(1)
        return out
    }

    private var hero: [FilmRef] { Array((shelves[.trending] ?? []).filter { $0.backdrop != nil }.prefix(8)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                if connected { heroSection } else {
                    greeting.padding(.top, Screen.safeTop + 8)
                    TMDBConnectCard()
                }
                IntermissionShelf()
                if !library.showsInProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Continue watching", subtitle: "Shows you're partway through") {
                            NavigationLink("See all", value: CollectionRoute.shows)
                        }
                        ShowProgressRow(shows: library.showsInProgress)
                    }
                }
                if connected { forYou }
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
            .padding(.bottom, 32)
        }
        .ambientBackground(glowFilms, intensity: 0.5)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load(force: true) }
        .task(id: token) { if connected { await load(force: true) } }
    }

    /// "Films you'd like", built from your swipe quiz and your highest ratings.
    @ViewBuilder private var forYou: some View {
        if let p = taste.profile.persona {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Films you'd like", subtitle: "For \(p.name) \(p.emoji)") {
                    if !taste.picks.isEmpty { NavigationLink("Swipe", value: CollectionRoute.forYou) }
                }
                if taste.picks.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 160)
                } else {
                    PosterRow(films: taste.picks, width: 124)
                }
            }
            .task(id: library.doc.ratings.count) { await taste.refreshPicks(library: library) }
        } else {
            Button { taste.showQuiz = true } label: {
                HStack(spacing: 14) {
                    Text("🎭").font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Find your film character").font(.headline)
                        Text("Swipe through 20 films and get recommendations made for you.")
                            .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
                }
                .padding(18)
                .contentShape(.rect(cornerRadius: 24))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    private var greeting: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.7))
                Text(greetingText).font(.title.weight(.heavy))
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

    /// Full-bleed, edge-to-edge hero: textless backdrop, the film's logo, and two small glass buttons.
    private var heroSection: some View {
        ZStack(alignment: .top) {
            if hero.isEmpty {
                Color.clear
                    .overlay { if !failed { ProgressView() } }
            } else {
                TabView(selection: $heroPage) {
                    ForEach(Array(hero.enumerated()), id: \.element.id) { i, f in
                        HeroPage(film: f).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            greeting
                .shadow(color: .black.opacity(0.5), radius: 12)
                .padding(.top, Screen.safeTop + 6)
        }
        .overlay(alignment: .bottom) {
            if hero.count > 1 {
                HStack(spacing: 6) {
                    ForEach(hero.indices, id: \.self) { i in
                        Capsule().fill(i == heroPage ? Color.white : Color.white.opacity(0.3))
                            .frame(width: i == heroPage ? 16 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: heroPage)
                .padding(.bottom, 8)
            }
        }
        .containerRelativeFrame(.vertical) { h, _ in h * 0.72 }
        .task(id: hero.count) {
            // Gently auto-advance, like a cinema lobby screen.
            while !Task.isCancelled && hero.count > 1 {
                try? await Task.sleep(for: .seconds(7))
                if Task.isCancelled { break }
                withAnimation(.smooth(duration: 0.7)) { heroPage = (heroPage + 1) % hero.count }
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

struct HeroPage: View {
    let film: FilmRef
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var art: FilmArt?

    var body: some View {
        let saved = library.inWatchlist(film.id)
        ZStack(alignment: .bottom) {
            NavigationLink(value: film) {
                Color.clear
                    .overlay { RemoteImage(url: art?.backdrop ?? film.backdrop ?? film.poster) }
                    .clipped()
                    // Darken only behind the status bar and greeting…
                    .overlay {
                        LinearGradient(stops: [.init(color: .black.opacity(0.5), location: 0), .init(color: .clear, location: 0.26)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    // …and dissolve the bottom into the glowing page instead of a hard black edge.
                    .mask {
                        LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.42),
                                               .init(color: .white.opacity(0.55), location: 0.68), .init(color: .white.opacity(0.15), location: 0.88),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(film.title)

            VStack(spacing: 12) {
                TitleArt(title: film.title, logo: art?.logo, aspect: art?.logoAspect ?? 3, maxWidth: 260, maxHeight: 96, fontSize: 34)
                    .shadow(color: .black.opacity(0.6), radius: 18, y: 4)
                    .allowsHitTesting(false)
                Text(["Trending now", film.yearText].filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                    .font(.caption.weight(.bold)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .allowsHitTesting(false)
                HStack(spacing: 10) {
                    GlassChip(prominent: true, action: { router.sheet = .log(film, nil) }) {
                        Label("Log", systemImage: "plus")
                    }
                    GlassChip(action: { library.toggleWatchlist(film) }) {
                        Label(saved ? "Saved" : "Watchlist", systemImage: saved ? "checkmark" : "clock")
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .task(id: film.id) { art = await Catalog.art(film.id) }
    }
}

struct Avatar: View {
    let profile: Profile
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.accent, Theme.heart], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white)
            if let d = profile.avatarData, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: size, height: size).clipShape(Circle())
            } else if let a = profile.avatar {
                RemoteImage(url: a).clipShape(Circle())
            }
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
