import SwiftUI

/// Anyone who worked on a film or show — actors, directors, writers, producers, composers, cinematographers.
/// Everything they made, grouped by what they did, with how much of it you've seen:
/// "You've seen 9 of 13". Films you've seen are bright; the rest are dimmed, ready to save.
struct PersonView: View {
    let route: PersonRoute
    @Environment(Library.self) private var library
    @State private var credits: PersonCredits?
    @State private var failed = false
    @State private var groupName: String?
    @State private var hideSeen = false
    @State private var media: MediaFilter = .all
    @State private var sort: Sort = .newest
    @State private var bioExpanded = false

    enum Sort: String, CaseIterable { case newest = "Newest", oldest = "Oldest", popular = "Most popular" }

    private var group: CreditGroup? {
        credits?.groups.first { $0.name == groupName } ?? credits?.mainGroup
    }

    /// The selected group, filtered and sorted.
    private var shown: [Credit] {
        var list = (group?.credits ?? []).filter { media.includes($0.film) }
        if hideSeen { list = list.filter { !library.isWatched($0.film.id) } }
        switch sort {
        case .newest: break
        case .oldest: list.reverse()
        case .popular: list.sort { $0.popularity > $1.popularity }
        }
        return list
    }

    var body: some View {
        ScrollView {
            if let c = credits {
                VStack(alignment: .leading, spacing: 20) {
                    header(c)
                    if c.groups.count > 1 { groupChips(c) }
                    if (group?.credits ?? []).contains(where: \.film.isShow) && (group?.credits ?? []).contains(where: { !$0.film.isShow }) {
                        MediaFilterBar(selection: $media).frame(maxWidth: .infinity)
                    }
                    progress
                    if shown.isEmpty {
                        Text(hideSeen ? "You've seen everything here." : "Nothing here.")
                            .font(.subheadline).foregroundStyle(Theme.dim).padding(.horizontal, 20)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), alignment: .leading, spacing: 14) {
                        ForEach(shown) { credit in cell(credit) }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)
            } else if failed {
                EmptyState(symbol: "person.crop.circle.badge.exclamationmark", title: "Couldn't load \(route.name)", message: "Check your connection and try again.")
                    .padding(.top, 60)
            } else {
                ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
            }
        }
        .ambientBackground(Array(shown.map(\.film).filter { library.isWatched($0.id) }.prefix(3)))
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Toggle(isOn: $hideSeen.animation(.smooth)) { Label("Hide what I've seen", systemImage: "eye.slash") }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
            }
        }
        .task {
            do { credits = try await Catalog.person(route.id) } catch { failed = true }
        }
    }

    private func cell(_ credit: Credit) -> some View {
        let f = credit.film
        let seen = library.isWatched(f.id)
        return NavigationLink(value: f) {
            VStack(alignment: .leading, spacing: 4) {
                PosterView(film: f, corner: 6, glows: seen)
                    .opacity(seen || !credit.released ? 1 : 0.4)
                    .saturation(seen ? 1 : 0.25)
                    .overlay(alignment: .topTrailing) {
                        if seen {
                            badge("eye.fill", Theme.watch)
                        } else if library.inWatchlist(f.id) {
                            badge("clock.fill", Theme.list)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if !credit.released {
                            Text("COMING").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Theme.accent, in: .capsule).padding(5)
                        }
                    }
                Text(f.title).font(.caption.weight(.semibold)).lineLimit(1)
                Text([f.yearText, credit.roles.prefix(2).joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Theme.dim).lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .filmContextMenu(f)
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            .padding(4).background(color, in: .circle).padding(4)
    }

    private func groupChips(_ c: PersonCredits) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(c.groups) { g in
                    let on = g.name == (group?.name ?? "")
                    Button { withAnimation(.smooth) { groupName = g.name } } label: {
                        Text("\(g.name) \(g.credits.count)").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .tint(on ? Theme.accent : nil)
                    .overlay(Capsule().strokeBorder(on ? Theme.accent : .clear, lineWidth: 1.5).allowsHitTesting(false))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func header(_ c: PersonCredits) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle().fill(Theme.card)
                    Text(c.person.name.prefix(1)).font(.largeTitle.bold()).foregroundStyle(Theme.dim)
                    if c.person.photo != nil { RemoteImage(url: c.person.photo).clipShape(Circle()) }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.person.name).font(.title2.weight(.bold))
                    Text(c.knownFor).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    if let b = c.birthday, let d = TMDB.airDate.date(from: b) {
                        Text("Born \(d.formatted(date: .long, time: .omitted))").font(.caption).foregroundStyle(Theme.dim)
                    }
                    if let place = c.birthplace { Text(place).font(.caption).foregroundStyle(Theme.dim).lineLimit(2) }
                }
            }
            if let bio = c.biography {
                Text(bio).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(bioExpanded ? nil : 4)
                    .onTapGesture { withAnimation(.smooth) { bioExpanded.toggle() } }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var progress: some View {
        let released = (group?.credits ?? []).filter { $0.released && media.includes($0.film) }
        let total = released.count
        let seen = released.filter { library.isWatched($0.film.id) }.count
        let saved = released.filter { !library.isWatched($0.film.id) && library.inWatchlist($0.film.id) }.count
        let noun = media == .shows ? "shows" : media == .movies ? "films" : "titles"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(seen == total && total > 0 ? "You've seen all \(total) \(noun)" : "You've seen \(seen) of \(total) \(noun)")
                    .font(.headline)
                Spacer()
                if total > 0 { Text("\(Int((Double(seen) / Double(total) * 100).rounded()))%").font(.headline.monospacedDigit()).foregroundStyle(Theme.accent) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Theme.list.opacity(0.6)).frame(width: total == 0 ? 0 : g.size.width * CGFloat(seen + saved) / CGFloat(total))
                    Capsule().fill(Theme.watch).frame(width: total == 0 ? 0 : g.size.width * CGFloat(seen) / CGFloat(total))
                }
            }
            .frame(height: 8)
            if saved > 0 { Text("\(saved) more on your watchlist").font(.caption).foregroundStyle(Theme.dim) }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16)
        .animation(.smooth, value: seen)
    }
}

/// A row of people — cast or crew — each opening their filmography.
struct PeopleRow: View {
    let people: [Person]
    var surface: Color = Theme.card

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(Array(people.enumerated()), id: \.offset) { _, p in
                    NavigationLink(value: PersonRoute(id: p.id, name: p.name)) {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(surface)
                                Text(p.name.prefix(1)).font(.title2.bold()).foregroundStyle(.white.opacity(0.65))
                                if p.photo != nil { RemoteImage(url: p.photo).clipShape(Circle()) }
                            }
                            .frame(width: 72, height: 72)
                            Text(p.name).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                            if !p.role.isEmpty { Text(p.role).font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(2).multilineTextAlignment(.center) }
                        }
                        .frame(width: 84)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
}
