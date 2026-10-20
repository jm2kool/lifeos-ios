import SwiftUI

struct FilmView: View {
    let film: FilmRef
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var detail: FilmDetail?
    @State private var failed = false
    @State private var expanded = false

    private var ref: FilmRef {
        var r = detail?.ref ?? film
        if r.title.isEmpty { r.title = film.title }
        if r.poster == nil { r.poster = film.poster }
        return r
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                actionPanel.padding(.horizontal, 16)
                if let d = detail { info(d) } else if failed {
                    EmptyState(symbol: "film", title: "Couldn't load details", message: "You can still log, rate and save this film.")
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                yourActivity
            }
            .padding(.bottom, 60)
        }
        .oledBackground()
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(ref.title)\(ref.year.map { " (\($0))" } ?? "") — on my watch list in Matinee")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { router.sheet = .addToList(ref) } label: { Label("Add to list…", systemImage: "text.badge.plus") }
                    Menu {
                        ForEach(0..<4) { i in
                            Button("Slot \(i + 1)\(i < library.doc.favorites.count ? " — replaces \(library.doc.favorites[i].title)" : "")") {
                                library.setFavorite(ref, slot: i)
                            }
                        }
                    } label: { Label("Set as a favourite", systemImage: "star") }
                    if library.isWatched(ref.id) {
                        Button(role: .destructive) { library.toggleWatched(ref) } label: { Label("Remove from watched", systemImage: "eye.slash") }
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .task(id: film.id) {
            do {
                let d = try await Catalog.detail(film.id)
                withAnimation(.smooth) { detail = d }
                library.hydrate(film, with: d)
            } catch { failed = true }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: ref.backdrop ?? ref.poster)
                .frame(height: 380)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    if ref.backdrop == nil { Rectangle().fill(.ultraThinMaterial) }
                }
            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                   .init(color: .black.opacity(0.7), location: 0.75), .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ref.title.isEmpty ? " " : ref.title)
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .lineLimit(3).minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        if let y = ref.year { Text(String(y)) }
                        if let m = detail?.runtimeMinutes, m > 0 { Text("·"); Text("\(m / 60)h \(m % 60)m") }
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.dim)
                    if let dirs = detail?.directors, !dirs.isEmpty {
                        (Text("Directed by ").foregroundStyle(Theme.dim) + Text(dirs.prefix(2).joined(separator: ", ")).bold())
                            .font(.subheadline)
                    }
                }
                Spacer(minLength: 0)
                PosterView(film: ref, width: 104, corner: 10)
                    .shadow(color: .black.opacity(0.7), radius: 16, y: 8)
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 380)
    }

    // MARK: Actions — the one place to watch, like, save, rate and log

    private var actionPanel: some View {
        let watched = library.isWatched(ref.id), liked = library.isLiked(ref.id), saved = library.inWatchlist(ref.id)
        return VStack(spacing: 18) {
            HStack(spacing: 0) {
                toggle(watched ? "Watched" : "Watch", watched ? "eye.fill" : "eye", watched, Theme.watch) { library.toggleWatched(ref) }
                toggle(liked ? "Liked" : "Like", liked ? "heart.fill" : "heart", liked, Theme.heart) { library.toggleLike(ref) }
                toggle(saved ? "In watchlist" : "Watchlist", saved ? "clock.fill" : "clock", saved, Theme.list) { library.toggleWatchlist(ref) }
            }
            Divider().overlay(Theme.line)
            VStack(spacing: 8) {
                Text(library.rating(ref.id) == nil ? "Tap or slide to rate" : "Your rating")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                StarRating(rating: library.rating(ref.id), size: 36, spacing: 8) { library.rate(ref, $0) }
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button { router.sheet = .log(ref, nil) } label: {
                        Label(library.isWatched(ref.id) ? "Log again or review" : "Review or log", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button { router.sheet = .addToList(ref) } label: {
                        Image(systemName: "text.badge.plus").frame(width: 24)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Add to list")
                }
                .controlSize(.large)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func toggle(_ title: String, _ symbol: String, _ on: Bool, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: on ? .light : .medium).impactOccurred()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 26, weight: .medium))
                    .foregroundStyle(on ? color : .white.opacity(0.8))
                    .symbolEffect(.bounce, value: on)
                    .frame(height: 30)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(on ? color : Theme.dim)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Info

    @ViewBuilder private func info(_ d: FilmDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = d.tagline {
                Text(t.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(Theme.dim)
            }
            if let o = d.overview {
                Text(o).font(.body).foregroundStyle(.white.opacity(0.85)).lineLimit(expanded ? nil : 4)
                    .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
            }
            if !d.genres.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(d.genres, id: \.self) { g in
                            NavigationLink(value: GenreRoute(name: g)) { Text(g).font(.footnote.weight(.semibold)) }
                                .buttonStyle(.glass).controlSize(.small)
                        }
                    }
                }
                .scrollIndicators(.hidden).scrollClipDisabled()
            }
        }
        .padding(.horizontal, 20)

        if let r = d.communityRating, r > 0 {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("COMMUNITY").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.dim)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text((r / 2).formatted(.number.precision(.fractionLength(1)))).font(.system(size: 40, weight: .bold, design: .rounded))
                        Image(systemName: "star.fill").foregroundStyle(Theme.star)
                    }
                    if let v = d.voteCount { Text("\(v.formatted(.number.notation(.compactName))) ratings · \(Catalog.usingTMDB ? "TMDB" : "IMDb")").font(.caption).foregroundStyle(Theme.dim) }
                }
                Spacer()
                StarRating(rating: ((r / 2) * 2).rounded() / 2, size: 18, spacing: 3)
            }
            .padding(18)
            .background(Theme.card, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 16)
        }

        if !d.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Cast")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(d.cast) { p in
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(Theme.card)
                                    Text(p.name.prefix(1)).font(.title2.bold()).foregroundStyle(Theme.dim)
                                    if p.photo != nil { RemoteImage(url: p.photo).clipShape(Circle()) }
                                }
                                .frame(width: 72, height: 72)
                                Text(p.name).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                                if !p.role.isEmpty { Text(p.role).font(.caption2).foregroundStyle(Theme.dim).lineLimit(1) }
                            }
                            .frame(width: 84)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
        }

        if !d.countries.isEmpty || d.runtimeMinutes != nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Details")
                VStack(spacing: 0) {
                    if let m = d.runtimeMinutes, m > 0 { detailRow("Runtime", "\(m) minutes") }
                    if !d.countries.isEmpty { detailRow("Country", d.countries.prefix(3).joined(separator: ", ")) }
                    if !d.directors.isEmpty { detailRow(d.directors.count > 1 ? "Directors" : "Director", d.directors.joined(separator: ", ")) }
                }
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .padding(.horizontal, 16)
            }
        }

        if !d.similar.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("More like this")
                PosterRow(films: d.similar, width: 104)
            }
        }
    }

    private func detailRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).foregroundStyle(Theme.dim)
            Spacer()
            Text(v).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var yourActivity: some View {
        let mine = library.entries(for: ref.id)
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Your diary", subtitle: mine.count == 1 ? "Watched once" : "Watched \(mine.count) times")
                VStack(spacing: 8) {
                    ForEach(mine) { e in
                        Button { router.sheet = .log(e.film, e) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(e.watchedOn.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                                    if e.rewatch { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.watch) }
                                    Spacer()
                                    SmallStars(rating: e.rating)
                                    if e.liked { Image(systemName: "heart.fill").foregroundStyle(Theme.heart).font(.caption) }
                                }
                                if !e.review.isEmpty { Text(e.review).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(4).multilineTextAlignment(.leading) }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card, in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
