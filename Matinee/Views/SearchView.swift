import SwiftUI

struct SearchView: View {
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @State private var query = ""
    @State private var results: [FilmRef] = []
    @State private var people: [PublicProfile] = []
    @State private var crew: [Person] = []
    @Environment(Router.self) private var router
    @State private var loading = false
    @State private var error: String?
    @AppStorage("tmdbToken") private var token = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if token.isEmpty && !Catalog.hasToken {
                    TMDBConnectCard()
                } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    FinderCard()
                    if !library.doc.recentSearches.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Recent") { Button("Clear") { library.clearSearches() } }
                            VStack(spacing: 0) {
                                ForEach(library.doc.recentSearches, id: \.self) { q in
                                    Button { query = q } label: {
                                        HStack {
                                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.dim)
                                            Text(q)
                                            Spacer()
                                            Image(systemName: "arrow.up.left").foregroundStyle(Theme.dim).font(.caption)
                                        }
                                        .padding(.vertical, 12).padding(.horizontal, 20)
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Genres")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(Catalog.genres, id: \.self) { g in
                                NavigationLink(value: GenreRoute(name: g)) { GenreTile(name: g) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else if loading && results.isEmpty && people.isEmpty && crew.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let error, results.isEmpty && people.isEmpty && crew.isEmpty {
                    EmptyState(symbol: "wifi.exclamationmark", title: "Search failed", message: error).padding(.top, 40)
                } else if results.isEmpty && people.isEmpty && crew.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "Nothing found", message: "Try a different spelling or the original title.").padding(.top, 40)
                    Button { router.sheet = .finder(query) } label: {
                        Label("Ask the AI finder instead", systemImage: "sparkle.magnifyingglass").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass).padding(.horizontal, 40)
                } else {
                    if !people.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader("People")
                            ForEach(people) { PersonRow(person: $0) }
                        }
                    }
                    // People who make films: when the search is a name, they come first.
                    if !crew.isEmpty && (results.isEmpty || crew[0].name.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespaces))) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Cast & crew")
                            PeopleRow(people: crew)
                        }
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(results) { f in SearchRow(film: f) }
                    }
                    if !crew.isEmpty && !(results.isEmpty || crew[0].name.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespaces))) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Cast & crew")
                            PeopleRow(people: crew)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .ambientBackground(Array(results.prefix(3)))
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Films, shows, people, @friends or a link")
        .onSubmit(of: .search) { library.rememberSearch(query) }
        .task(id: query) {
            let q = query
            guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; people = []; crew = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            loading = true; defer { loading = false }
            let found = await auth.searchProfiles(q)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { people = found }
            // "@name" looks for people only.
            if q.hasPrefix("@") { results = []; crew = []; error = nil; return }
            // A pasted link goes to the AI finder.
            if let url = URL(string: q.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true {
                query = ""
                router.sheet = .finder(url.absoluteString)
                return
            }
            do {
                let r = try await Catalog.searchAll(q)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth) { results = r.films; crew = r.people; error = nil }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PersonRow: View {
    let person: PublicProfile
    var body: some View {
        NavigationLink(value: ProfileRoute(handle: person.handle ?? "")) {
            HStack(spacing: 14) {
                Avatar(profile: person.asProfile, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name.isEmpty ? "Film fan" : person.name).font(.body.weight(.semibold))
                    if let h = person.handle { Text("@\(h)").font(.subheadline).foregroundStyle(Theme.dim) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(person.handle == nil)
    }
}

struct SearchRow: View {
    let film: FilmRef
    @Environment(Library.self) private var library

    var body: some View {
        let saved = library.inWatchlist(film.id)
        HStack(spacing: 12) {
            NavigationLink(value: film) {
                HStack(spacing: 14) {
                    PosterView(film: film, width: 54, corner: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(film.title).font(.body.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            if film.isShow {
                                Text("TV").font(.caption2.weight(.heavy)).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Theme.list.opacity(0.25), in: .rect(cornerRadius: 4)).foregroundStyle(Theme.list)
                            }
                            Text(film.yearText).foregroundStyle(Theme.dim)
                            if library.isWatched(film.id) { Image(systemName: "eye.fill").foregroundStyle(Theme.watch) }
                            SmallRating(rating: library.rating(film.id))
                        }
                        .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .filmContextMenu(film)

            // A sibling of the row link (not inside it), so it draws and taps on its own.
            // "clock.badge.plus" isn't a real symbol, which is why this button used to draw empty.
            GlassChip(circle: true, action: {
                library.toggleWatchlist(film)
                UIImpactFeedbackGenerator(style: saved ? .light : .medium).impactOccurred()
            }) {
                Image(systemName: saved ? "clock.fill" : "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(saved ? Theme.list : Color.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(saved ? "Remove from watchlist" : "Add to watchlist")
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }
}

struct GenreTile: View {
    let name: String
    private var stableHue: Double {
        Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 997 }) / 997
    }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hue: stableHue, saturation: 0.75, brightness: 0.55), Color(hue: stableHue, saturation: 0.9, brightness: 0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(name).font(.headline).padding(14)
        }
        .frame(height: 84)
        .clipShape(.rect(cornerRadius: 18))
    }
}

/// Search-and-log in one place, opened from the Diary's + button.
struct QuickLogSheet: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FilmRef] = []

    var body: some View {
        NavigationStack {
            List {
                let pool = query.isEmpty ? Array((library.doc.watchlist + library.watchedFilms).prefix(20)) : results
                if query.isEmpty && !pool.isEmpty {
                    Text("From your watchlist and recent films").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                        .listRowBackground(Color.clear)
                }
                ForEach(pool) { f in
                    Button { router.sheet = .log(f, nil) } label: {
                        HStack(spacing: 12) {
                            PosterView(film: f, width: 40, corner: 4)
                            VStack(alignment: .leading) {
                                Text(f.title).font(.body.weight(.semibold))
                                Text(f.yearText).font(.subheadline).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .oledBackground()
            .navigationTitle("What did you watch?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search films and shows")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Scan a ticket", systemImage: "ticket") { router.sheet = .scanTicket } }
            }
            .task(id: query) {
                guard !query.isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if let r = try? await Catalog.search(query), !Task.isCancelled { results = r }
            }
        }
    }
}

struct GenreView: View {
    let genre: String
    @State private var films: [FilmRef] = []
    @State private var failed = false
    var body: some View {
        ScrollView {
            if films.isEmpty {
                if failed { EmptyState(symbol: "film", title: "Nothing here yet", message: "Couldn't load \(genre) films.") }
                else { ProgressView().padding(.top, 80) }
            } else {
                PosterGrid(films: films, columns: 3).padding(16)
            }
        }
        .ambientBackground(Array(films.prefix(3)))
        .navigationTitle(genre)
        .task {
            if let f = try? await Catalog.genre(genre) { films = f } else { failed = true }
            if films.isEmpty { failed = true }
        }
    }
}

struct CollectionView: View {
    let route: CollectionRoute
    @Environment(Library.self) private var library
    @Environment(Taste.self) private var taste
    @AppStorage("deckMode") private var deckMode = true
    @AppStorage("homeMedia") private var homeMedia: MediaFilter = .all
    @State private var remote: [FilmRef] = []

    private var action: DeckAction {
        switch route {
        case .watchlist: return .tonight
        case .watched, .liked, .rated, .tag, .shows: return .like
        default: return .watchlist
        }
    }

    private var title: String {
        switch route {
        case .shelf(let s): return s.title
        case .watched: return "Films"
        case .liked: return "Likes"
        case .watchlist: return "Watchlist"
        case .tag(let t): return "#\(t)"
        case .rated(let b): return FilmRatingStyle.current == .stars ? Stars.text(Double(b + 1) / 2) : "Scored \(b * 10 + 1)–\(b * 10 + 10)"
        case .forYou: return homeMedia == .all ? "Picked for you" : homeMedia == .shows ? "Shows you'd like" : "Films you'd like"
        case .shows: return "Shows"
        }
    }

    private var films: [FilmRef] {
        switch route {
        case .shelf: return remote
        case .watched: return library.watchedFilms
        case .liked: return library.doc.liked.reversed()
        case .watchlist: return library.doc.watchlist
        case .tag(let t): return library.entries.filter { $0.tags.contains(t) }.map(\.film)
        case .rated(let b): return library.watchedFilms.filter { !$0.isShow && library.rating($0.id).map { Library.band($0) == b } == true }
        case .forYou: return taste.picks.filter(homeMedia.includes)
        case .shows: return library.showsInProgress + library.watchedFilms.filter(\.isShow)
        }
    }

    var body: some View {
        Group {
            if deckMode && !films.isEmpty {
                FilmDeckScreen(films: films, action: action, deckMode: $deckMode)
            } else {
                ScrollView {
                    if films.isEmpty, case .shelf = route { ProgressView().padding(.top, 80) }
                    else if films.isEmpty { EmptyState(symbol: "film.stack", title: "Nothing here yet", message: "Films you add will show up here.").padding(.top, 60) }
                    else { PosterGrid(films: films, columns: 4).padding(16) }
                }
            }
        }
        .ambientBackground(Array(films.prefix(3)))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(deckMode && !films.isEmpty ? .hidden : .visible, for: .tabBar)
        .toolbar { DeckToggle(deckMode: $deckMode) }
        .task { if case .shelf(let s) = route { remote = (try? await Catalog.shelf(s)) ?? [] } }
    }
}
