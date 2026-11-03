import SwiftUI

/// Something you're waiting for: the next episode of a show, or the day a film comes out.
struct UpcomingItem: Identifiable, Hashable {
    enum Kind: Hashable { case episode(Episode), release }
    var film: FilmRef
    var date: Date
    var kind: Kind
    var detail: String
    var id: String

    var isEpisode: Bool { if case .episode = kind { return true }; return false }
}

/// One day in the calendar.
struct UpcomingDay: Identifiable {
    var day: Date
    var items: [UpcomingItem]
    var id: Date { day }
}

struct UpcomingRoute: Hashable {}

@MainActor
enum Upcoming {
    /// The next episode of each show you're watching (or saved), and release days of watchlist films and reminders,
    /// from today up to `days` ahead, soonest first.
    static func load(_ library: Library, days: Int = 180) async -> [UpcomingItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let until = cal.date(byAdding: .day, value: days, to: today) ?? .distantFuture
        let thisYear = Date.now.year
        var seen = Set<String>()
        let shows = Array((library.currentlyWatching + library.showsInProgress + library.doc.watchlist.filter(\.isShow))
            .filter { seen.insert($0.id).inserted }.prefix(30))
        let films = Array(library.doc.watchlist.filter { !$0.isShow && ($0.year ?? thisYear) >= thisYear - 1 }.prefix(40))
        var out: [UpcomingItem] = []
        await withTaskGroup(of: UpcomingItem?.self) { g in
            for s in shows {
                g.addTask {
                    guard let d = try? await Catalog.detail(s.id), let n = d.nextEpisode, let day = n.airDate else { return nil }
                    return UpcomingItem(film: s, date: day, kind: .episode(n), detail: "\(n.code) · \(n.name)", id: "ep-\(s.id)-\(n.id)")
                }
            }
            for f in films {
                g.addTask {
                    guard let d = try? await Catalog.detail(f.id), let day = d.releaseDate else { return nil }
                    return UpcomingItem(film: f, date: day, kind: .release, detail: "Release day", id: "rel-\(f.id)")
                }
            }
            for await item in g {
                if let item, item.date >= today, item.date <= until { out.append(item) }
            }
        }
        for r in library.reminders where r.date >= today && r.date <= until && !out.contains(where: { $0.film.id == r.film.id }) {
            out.append(UpcomingItem(film: r.film, date: r.date, kind: .release, detail: "Release day · reminder on", id: "rel-\(r.film.id)"))
        }
        return out.sorted { ($0.date, $0.film.title) < ($1.date, $1.film.title) }
    }

    static func group(_ items: [UpcomingItem]) -> [UpcomingDay] {
        let cal = Calendar.current
        var out: [UpcomingDay] = []
        for i in items {
            let d = cal.startOfDay(for: i.date)
            if out.last?.day == d { out[out.count - 1].items.append(i) } else { out.append(UpcomingDay(day: d, items: [i])) }
        }
        return out
    }

    /// "Today", "Tomorrow", "Saturday", or "Tue 18 November" further out.
    static func heading(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: d).day ?? 0
        return n < 7 ? d.formatted(.dateTime.weekday(.wide)) : d.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
    }

    /// Short, for a chip: "Today", "Tmrw", "Sat", "18 Nov".
    static func chip(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: d).day ?? 0
        return n < 7 ? d.formatted(.dateTime.weekday(.abbreviated)) : d.formatted(.dateTime.day().month(.abbreviated))
    }

    static func open(_ item: UpcomingItem, router: Router) {
        if case .episode(let e) = item.kind { router.sheet = .episode(item.film, e) } else { router.open(item.film) }
    }
}

/// Coming up: a calendar of new episodes and release days for everything you're following.
struct UpcomingView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var items: [UpcomingItem] = []
    @State private var loaded = false
    @State private var filter: MediaFilter = .all

    var body: some View {
        let shown = items.filter { filter.includes($0.film) }
        List {
            if !loaded {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear).listRowSeparator(.hidden).padding(.top, 60)
            } else if shown.isEmpty {
                EmptyState(symbol: "calendar", title: "Nothing coming up",
                           message: "Pin shows you're watching, or save films that aren't out yet, and their dates appear here.")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(Upcoming.group(shown)) { day in
                Section {
                    ForEach(day.items) { item in
                        Button { Upcoming.open(item, router: router) } label: {
                            HStack(spacing: 12) {
                                PosterView(film: item.film, width: 46, corner: 5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.film.title).font(.body.weight(.semibold)).lineLimit(1)
                                    Text(item.detail).font(.subheadline).foregroundStyle(Theme.dim).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: item.isEpisode ? "tv" : "film").foregroundStyle(Theme.accent)
                                    .accessibilityLabel(item.isEpisode ? "New episode" : "Release")
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .filmContextMenu(item.film)
                    }
                } header: {
                    Text(Upcoming.heading(day.day)).font(.headline).foregroundStyle(.white)
                }
            }
        }
        .listStyle(.plain)
        .ambientBackground(Array(shown.prefix(3).map(\.film)))
        .navigationTitle("Coming up")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $filter) { ForEach(MediaFilter.allCases, id: \.self) { Text($0.label).tag($0) } }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
            }
        }
        .refreshable { items = await Upcoming.load(library) }
        .task {
            items = await Upcoming.load(library)
            loaded = true
        }
    }
}

/// Home: the next few things you're waiting for, with a way into the full calendar.
struct ComingUpSection: View {
    var media: MediaFilter = .all
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var items: [UpcomingItem] = []

    private var signature: String {
        "\(library.currentlyWatching.map(\.id))|\(library.showsInProgress.count)|\(library.doc.watchlist.count)|\(library.reminders.count)"
    }

    var body: some View {
        let shown = Array(items.filter { media.includes($0.film) }.prefix(12))
        Group {
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Coming up", subtitle: "New episodes and release days you're waiting for") {
                        NavigationLink("Calendar", value: UpcomingRoute())
                    }
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(shown) { item in
                                Button { Upcoming.open(item, router: router) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        PosterView(film: item.film, width: 104)
                                            .overlay(alignment: .topLeading) {
                                                Text(Upcoming.chip(item.date)).font(.caption2.weight(.heavy))
                                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                                    .background(Theme.accent, in: .capsule)
                                                    .padding(6)
                                            }
                                        Text(item.isEpisode ? item.detail : item.film.title)
                                            .font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    }
                                    .frame(width: 104, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .filmContextMenu(item.film)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
        }
        .task(id: signature) {
            guard Catalog.hasToken else { return }
            items = await Upcoming.load(library, days: 60)
        }
    }
}

/// On a film's page: the series it belongs to, and how much of it you've seen.
struct FranchiseSection: View {
    let collectionID: Int
    var surface: Color = Theme.card
    @Environment(Library.self) private var library
    @State private var collection: FilmCollection?

    var body: some View {
        Group {
            if let c = collection, c.films.count > 1 {
                let seen = c.films.filter { library.isWatched($0.id) }.count
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(c.name, subtitle: seen == c.films.count ? "You've seen all \(c.films.count)"
                                  : seen == 0 ? "\(c.films.count) films" : "You've seen \(seen) of \(c.films.count)")
                    if seen > 0 {
                        ProgressView(value: Double(seen), total: Double(c.films.count)).tint(Theme.watch).padding(.horizontal, 20)
                    }
                    PosterRow(films: c.films, width: 96, marksSeen: true)
                }
            }
        }
        .task(id: collectionID) { collection = await Catalog.collection(collectionID) }
    }
}
