import SwiftUI

/// You and someone else: how well your taste lines up, what you both want to see, and films you'd both
/// like. Swipe through their watchlist together; a right swipe on one they saved too is a match.
struct BlendView: View {
    let profile: PublicProfile
    @Environment(Library.self) private var library
    @Environment(Taste.self) private var taste
    @Environment(Router.self) private var router
    @State private var match: TasteMatch?
    @State private var bothLike: [FilmRef] = []
    @State private var blurb: String?
    @State private var deck: [FilmRef]?

    private var theirName: String { profile.handle.map { "@\($0)" } ?? (profile.name.isEmpty ? "them" : profile.name) }
    private var theirWatchlist: [FilmRef] { profile.watchlist ?? [] }
    private var bothWant: [FilmRef] {
        let mine = Set(library.doc.watchlist.map(\.id))
        return theirWatchlist.filter { mine.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if let m = match { matchCard(m) } else { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30) }

                if profile.watchlist == nil {
                    Text("\(theirName) hasn't shared their watchlist, so there's no \"both want to see\" yet. They can switch it on in Settings → Friends.")
                        .font(.footnote).foregroundStyle(Theme.dim).padding(.horizontal, 20)
                } else if !bothWant.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("You both want to see", subtitle: "\(bothWant.count) on both your watchlists")
                        PosterRow(films: bothWant, width: 112)
                    }
                }

                if !bothLike.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("You'd both like", subtitle: "Grown from both your favourites")
                        PosterRow(films: bothLike, width: 104)
                    }
                }

                let pool = deckPool
                if !pool.isEmpty {
                    Button { deck = pool } label: {
                        Label("Plan a movie night — swipe together", systemImage: "rectangle.stack.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .padding(.horizontal, 16)
                    Text("Right on something \(theirName) saved too and it's a match.")
                        .font(.caption).foregroundStyle(Theme.dim).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 30)
        }
        .ambientBackground(Array((bothWant + profile.allFavorites).prefix(3)))
        .navigationTitle("Blend")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: Binding(get: { deck != nil }, set: { if !$0 { deck = nil } })) {
            BlendDeck(films: deck ?? [], theirs: Set(theirWatchlist.map(\.id)), theirName: theirName) { deck = nil }
                .environment(library).environment(router)
        }
        .task(id: profile.userID) { await load() }
    }

    /// Both-want first, then what you'd both like, then the rest of their watchlist you haven't seen.
    private var deckPool: [FilmRef] {
        var seen = Set<String>()
        return (bothWant + bothLike + theirWatchlist.shuffled())
            .filter { !library.isWatched($0.id) && seen.insert($0.id).inserted }
    }

    private var header: some View {
        HStack(spacing: -14) {
            Avatar(profile: library.doc.profile, size: 72)
            Avatar(profile: profile.asProfile, size: 72)
                .overlay(Circle().strokeBorder(.black, lineWidth: 3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func matchCard(_ m: TasteMatch) -> some View {
        VStack(spacing: 10) {
            Text("\(m.percent)%").font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(Score.color(Double(m.percent)))
            Text("taste match with \(theirName)").font(.headline)
            Text(m.verdict).font(.subheadline).foregroundStyle(Theme.dim)
            if !m.sharedGenres.isEmpty {
                HStack(spacing: 6) {
                    ForEach(m.sharedGenres, id: \.self) { g in
                        Text(g).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            if !m.sharedFavorites.isEmpty {
                Text("You both put \(m.sharedFavorites.map(\.title).prefix(3).joined(separator: ", ")) in your favourites.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            }
            if let blurb {
                Divider().overlay(Theme.line)
                Label("Apple Intelligence", systemImage: "apple.intelligence").font(.caption2.weight(.semibold)).foregroundStyle(Theme.dim)
                Text(blurb).font(.subheadline).multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .padding(.horizontal, 16)
    }

    private func load() async {
        // Genres of both sets of favourites (and your character, if you have one).
        let mine = library.allFavorites + library.doc.liked.suffix(20)
        let theirs = profile.allFavorites
        await FactStore.shared.fill(mine + theirs, limit: 60)
        let m = TasteMatch(mine: mine, theirs: theirs, myPersona: taste.profile.persona, theirPersona: profile.persona,
                           bothWant: bothWant.count)
        withAnimation(.smooth) { match = m }
        bothLike = await TasteMatch.bothLike(mine: library.allFavorites, theirs: theirs, library: library)
        if Intelligence.isAvailable {
            let me = "favourites \(library.allFavorites.prefix(5).map(\.title).joined(separator: ", ")); likes \(m.myGenres.prefix(3).joined(separator: ", "))"
            let them = "favourites \(theirs.prefix(5).map(\.title).joined(separator: ", ")); likes \(m.theirGenres.prefix(3).joined(separator: ", "))"
            let out = await Intelligence.matchBlurb(me: me, them: them, theirName: theirName,
                                                    shared: m.sharedFavorites.map(\.title) + m.sharedGenres, percent: m.percent)
            withAnimation(.smooth) { blurb = out }
        }
    }
}

/// How alike two people's taste is, from the genres of their favourites (and film characters), plus
/// favourites and watchlist films they share.
struct TasteMatch {
    var percent: Int
    var sharedGenres: [String]
    var sharedFavorites: [FilmRef]
    var myGenres: [String]
    var theirGenres: [String]

    var verdict: String {
        switch percent {
        case 85...: return "Practically the same person."
        case 70..<85: return "You'd agree on most film nights."
        case 50..<70: return "Plenty of common ground."
        case 30..<50: return "Different tastes — good for recommendations."
        default: return "Opposites. Brave movie nights ahead."
        }
    }

    @MainActor init(mine: [FilmRef], theirs: [FilmRef], myPersona: Persona?, theirPersona: PublicProfile.PublicPersona?, bothWant: Int) {
        func vector(_ films: [FilmRef], _ genres: [String], _ shares: [Double]) -> [String: Double] {
            var v: [String: Double] = [:]
            for f in films { for g in FactStore.shared[f.id]?.genres ?? [] { v[g, default: 0] += 1 } }
            let total = max(1, v.values.reduce(0, +))
            for k in v.keys { v[k]! /= total }
            for (g, s) in zip(genres, shares) { v[g, default: 0] += s }
            return v
        }
        let a = vector(mine, myPersona?.topGenres ?? [], myPersona?.genreShares ?? [])
        let b = vector(theirs, theirPersona?.topGenres ?? [], theirPersona?.genreShares ?? [])
        let keys = Set(a.keys).union(b.keys)
        let dot = keys.reduce(0.0) { $0 + (a[$1] ?? 0) * (b[$1] ?? 0) }
        let na = sqrt(a.values.reduce(0.0) { $0 + $1 * $1 }), nb = sqrt(b.values.reduce(0.0) { $0 + $1 * $1 })
        let cosine = na > 0 && nb > 0 ? dot / (na * nb) : 0.5
        let theirIDs = Set(theirs.map(\.id))
        var seen = Set<String>()
        sharedFavorites = mine.filter { theirIDs.contains($0.id) && seen.insert($0.id).inserted }
        let mineSorted = a.sorted { $0.value > $1.value }.map(\.key)
        let theirsSorted = b.sorted { $0.value > $1.value }.map(\.key)
        myGenres = mineSorted
        theirGenres = theirsSorted
        sharedGenres = Array(mineSorted.prefix(5).filter { theirsSorted.prefix(5).contains($0) }.prefix(3))
        let score = 25 + 65 * cosine + Double(sharedFavorites.count) * 6 + Double(min(bothWant, 5)) * 2
        percent = Int(min(99, max(1, score)).rounded())
    }

    /// Recommendations grown from both people's favourites; titles that come up for both go first.
    @MainActor static func bothLike(mine: [FilmRef], theirs: [FilmRef], library: Library) async -> [FilmRef] {
        func recs(_ seeds: [FilmRef]) async -> [FilmRef] {
            var out: [FilmRef] = []
            for s in seeds.prefix(4) { out += await TMDB.recommendations(s.id) }
            return out
        }
        let a = await recs(mine), b = await recs(theirs)
        let bIDs = Set(b.map(\.id))
        var seen = Set(library.watchedFilms.map(\.id) + mine.map(\.id) + theirs.map(\.id))
        let both = a.filter { bIDs.contains($0.id) }
        var mixed: [FilmRef] = []
        for i in 0..<max(a.count, b.count) {
            if i < b.count { mixed.append(b[i]) }
            if i < a.count { mixed.append(a[i]) }
        }
        return Array((both + mixed).filter { seen.insert($0.id).inserted }.prefix(20))
    }
}

/// Their watchlist (and picks for you both) as a swipe deck. Right adds it to your watchlist.
struct BlendDeck: View {
    let films: [FilmRef]
    let theirs: Set<String>
    let theirName: String
    var onClose: () -> Void
    @Environment(Library.self) private var library
    @State private var matches: [FilmRef] = []
    @State private var top: FilmRef?

    var body: some View {
        NavigationStack {
            SwipeDeck(films: films, likeLabel: "WANT", nopeLabel: "SKIP", likeSymbol: "clock.fill", likeColor: Theme.list,
                      onSwipe: { f, right in
                          guard right else { return }
                          if !library.inWatchlist(f.id) { library.toggleWatchlist(f) }
                          if theirs.contains(f.id) {
                              matches.append(f)
                              UINotificationFeedbackGenerator().notificationOccurred(.success)
                              library.toast = Toast(text: "It's a match with \(theirName)!", symbol: "sparkles")
                          }
                      },
                      onTop: { top = $0 }) {
                VStack(spacing: 16) {
                    Text(matches.isEmpty ? "🍿" : "🎉").font(.system(size: 64))
                    Text(matches.isEmpty ? "No matches this time" : "\(matches.count) match\(matches.count == 1 ? "" : "es")").font(.title2.weight(.bold))
                    if !matches.isEmpty {
                        Text(matches.map(\.title).joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                    }
                    Button("Done", action: onClose).buttonStyle(.glassProminent).controlSize(.large)
                }
                .padding(30)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AmbientGlow(urls: top?.poster.map { [$0] } ?? [], intensity: 0.55))
            .navigationTitle("Movie night with \(theirName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark", action: onClose) } }
        }
    }
}
