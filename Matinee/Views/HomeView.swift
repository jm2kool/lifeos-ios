import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var shelves: [HomeShelf: [FilmRef]] = [:]
    @State private var failed = false
    @State private var heroIndex: Int? = 0

    private var hero: [FilmRef] { Array((shelves[.trending] ?? []).filter { $0.backdrop != nil }.prefix(8)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                greeting
                heroCarousel
                if !library.doc.watchlist.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Up next", subtitle: "From your watchlist") {
                            NavigationLink("See all", value: CollectionRoute.watchlist)
                        }
                        PosterRow(films: Array(library.doc.watchlist.prefix(15)))
                    }
                }
                ForEach(HomeShelf.allCases) { s in
                    if let films = shelves[s], !films.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: s.title) { NavigationLink("See all", value: CollectionRoute.shelf(s)) }
                            PosterRow(films: s == .trending ? Array(films.dropFirst(min(3, films.count))) : films)
                        }
                    }
                }
                if failed && shelves.isEmpty {
                    EmptyState(symbol: "wifi.exclamationmark", title: "Couldn't load films", message: "Check your connection and pull to refresh.")
                        .padding(.top, 40)
                }
                genres
                if !library.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Your recent watches") {
                            Button("Diary") { router.tab = .diary }
                        }
                        PosterRow(films: Array(library.entries.prefix(12).map(\.film)), width: 96)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .oledBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load(force: true) }
        .task { if shelves.isEmpty { await load() } }
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
        .padding(.top, 8)
    }

    private var greetingText: String {
        let h = Calendar.current.component(.hour, from: .now)
        let part = h < 12 ? "Morning" : h < 17 ? "Afternoon" : "Evening"
        let first = library.doc.profile.name.split(separator: " ").first.map(String.init)
        return first.map { "\(part), \($0)" } ?? "Good \(part.lowercased())"
    }

    @ViewBuilder private var heroCarousel: some View {
        if hero.isEmpty {
            RoundedRectangle(cornerRadius: 28).fill(Theme.card)
                .frame(height: 440).padding(.horizontal, 20)
                .overlay { if !failed { ProgressView() } }
        } else {
            VStack(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Browse by genre")
            ScrollView(.horizontal) {
                LazyHGrid(rows: [GridItem(.fixed(44)), GridItem(.fixed(44))], spacing: 8) {
                    ForEach(Catalog.genres, id: \.self) { g in
                        NavigationLink(value: GenreRoute(name: g)) {
                            Text(g).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(height: 40)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func load(force: Bool = false) async {
        failed = false
        await withTaskGroup(of: (HomeShelf, [FilmRef]?).self) { g in
            for s in HomeShelf.allCases { g.addTask { let r = try? await Catalog.shelf(s); return (s, r) } }
            for await (s, films) in g {
                if let films { withAnimation(.smooth) { shelves[s] = films } }
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
                    RemoteImage(url: film.backdrop ?? film.poster)
                        .frame(height: 440)
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
