import SwiftUI

/// A director's or actor's films, with how many you've seen: "You've seen 9 of 13 Nolan films".
/// Films you've seen are bright; the rest are dimmed, ready to save.
struct PersonView: View {
    let route: PersonRoute
    @Environment(Library.self) private var library
    @State private var credits: PersonCredits?
    @State private var failed = false
    @State private var pane: Pane = .directed
    @State private var hideSeen = false

    enum Pane: String, CaseIterable { case directed = "Directed", acted = "Acted" }

    private var films: [FilmRef] {
        guard let c = credits else { return [] }
        return pane == .directed ? c.directed : c.acted
    }

    var body: some View {
        ScrollView {
            if let c = credits {
                VStack(alignment: .leading, spacing: 22) {
                    header(c)
                    if !c.directed.isEmpty && !c.acted.isEmpty {
                        Picker("Films", selection: $pane) {
                            ForEach(Pane.allCases, id: \.self) { Text("\($0.rawValue) (\(count($0)))").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                    }
                    progress
                    let shown = hideSeen ? films.filter { !library.isWatched($0.id) } : films
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                        ForEach(shown) { f in
                            let seen = library.isWatched(f.id)
                            NavigationLink(value: f) {
                                VStack(spacing: 4) {
                                    PosterView(film: f, corner: 6, glows: seen)
                                        .opacity(seen ? 1 : 0.38)
                                        .saturation(seen ? 1 : 0.2)
                                        .overlay(alignment: .topTrailing) {
                                            if seen {
                                                Image(systemName: "eye.fill").font(.system(size: 9, weight: .bold))
                                                    .padding(4).background(Theme.watch, in: .circle).padding(4)
                                            } else if library.inWatchlist(f.id) {
                                                Image(systemName: "clock.fill").font(.system(size: 9, weight: .bold))
                                                    .padding(4).background(Theme.list, in: .circle).padding(4)
                                            }
                                        }
                                    Text(f.yearText).font(.caption2).foregroundStyle(Theme.dim)
                                }
                            }
                            .buttonStyle(.plain)
                            .filmContextMenu(f)
                        }
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
        .ambientBackground(Array(films.filter { library.isWatched($0.id) }.prefix(3)))
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(hideSeen ? "Show all" : "Hide seen", systemImage: hideSeen ? "eye" : "eye.slash") { withAnimation(.smooth) { hideSeen.toggle() } }
            }
        }
        .task {
            do {
                let c = try await Catalog.person(route.id)
                credits = c
                pane = c.directed.isEmpty || (c.person.role == "Acting" && !c.acted.isEmpty) ? .acted : .directed
            } catch { failed = true }
        }
    }

    private func count(_ p: Pane) -> Int { (p == .directed ? credits?.directed : credits?.acted)?.count ?? 0 }

    private func header(_ c: PersonCredits) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(Theme.card)
                Text(c.person.name.prefix(1)).font(.largeTitle.bold()).foregroundStyle(Theme.dim)
                if c.person.photo != nil { RemoteImage(url: c.person.photo).clipShape(Circle()) }
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(c.person.name).font(.title2.weight(.bold))
                if !c.person.role.isEmpty { Text(c.person.role == "Directing" ? "Director" : c.person.role == "Acting" ? "Actor" : c.person.role).font(.subheadline).foregroundStyle(Theme.dim) }
                if let bio = c.biography {
                    Text(bio).font(.footnote).foregroundStyle(.white.opacity(0.75)).lineLimit(4)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var progress: some View {
        let total = films.count
        let seen = films.filter { library.isWatched($0.id) }.count
        let saved = films.filter { !library.isWatched($0.id) && library.inWatchlist($0.id) }.count
        let last = route.name.split(separator: " ").last.map(String.init) ?? route.name
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(seen == total && total > 0 ? "You've seen every \(last) film" : "You've seen \(seen) of \(total) \(last) films")
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
