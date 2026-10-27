import SwiftUI
import Charts

struct FilmView: View {
    let film: FilmRef
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(Watching.self) private var watching
    @State private var detail: FilmDetail?
    @State private var failed = false
    @State private var expanded = false
    @State private var palette: PosterPalette?
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var art: FilmArt?
    @State private var artLoaded = false
    @State private var trailerKey: String?
    @State private var showTrailer = false
    @State private var shareImage: UIImage?
    @State private var hosting = false
    @Environment(Auth.self) private var auth
    @AppStorage(FilmRatingStyle.key) private var ratingStyle: FilmRatingStyle = .score

    /// The page takes its colour from the poster: deep enough for white text, never washed out.
    private var bg: Color { palette?.background ?? .black }
    private var surface: Color { palette?.surface ?? Theme.card }

    /// A textless poster when TMDB has one (the title is drawn separately as the logo).
    private var heroURL: URL? {
        if let p = art?.poster { return p }
        return artLoaded || failed ? (ref.largePoster ?? ref.poster) : nil
    }

    private var ref: FilmRef {
        var r = detail?.ref ?? film
        if r.title.isEmpty { r.title = film.title }
        if r.poster == nil { r.poster = film.poster }
        return r
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 26) {
                    actionPanel.padding(.horizontal, 16)
                    if let d = detail, ref.isShow {
                        SeasonsSection(show: ref, detail: d, surface: surface, accent: palette?.highlight ?? Theme.accent)
                    }
                    if let d = detail { info(d); WatchProvidersSection(film: ref, surface: surface) } else if failed {
                        EmptyState(symbol: ref.isShow ? "tv" : "film", title: "Couldn't load details",
                                   message: "You can still log, rate and save this \(ref.isShow ? "show" : "film").")
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    yourActivity
                }
                .padding(.top, 6)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bg)
            }
        }
        .scrollPosition($scroll)
        .scrollEdgeEffectHidden(true, for: .top)
        .background(bg.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: "\(ref.title)\(ref.year.map { " (\($0))" } ?? "") — on my watch list in Matinee") {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    if let img = shareImage {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview(ref.title, image: Image(uiImage: img))) {
                            Label("Share as a story card", systemImage: "photo.on.rectangle")
                        }
                    }
                    Button { router.sheet = .addToList(ref) } label: { Label("Add to list…", systemImage: "text.badge.plus") }
                    if library.isFavorite(ref.id) {
                        Button { library.removeFavorite(ref) } label: { Label("Remove from favourites", systemImage: "star.slash") }
                    } else {
                        Button { library.addFavorite(ref) } label: {
                            Label(library.favoritesFull ? "Favourites are full — edit in Settings" : "Add to favourites", systemImage: "star")
                        }
                        .disabled(library.favoritesFull)
                    }
                    if library.isWatched(ref.id) {
                        Button(role: .destructive) { library.toggleWatched(ref) } label: { Label("Remove from watched", systemImage: "eye.slash") }
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .fullScreenCover(isPresented: $showTrailer) {
            if let k = trailerKey { TrailerView(key: k, title: ref.title) }
        }
        .task(id: film.id) { trailerKey = await Catalog.trailer(film.id) }
        // Keep a story card ready to share, with your current rating on it.
        .task(id: "\(heroURL?.absoluteString ?? "")|\(art?.logo?.absoluteString ?? "")|\(library.rating(ref.id) ?? 0)|\(library.isLiked(ref.id))") {
            guard heroURL != nil else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            shareImage = await ShareCard.render(film: ref, poster: heroURL, logo: art?.logo, rating: library.rating(ref.id),
                                                liked: library.isLiked(ref.id), tint: palette?.accent ?? Theme.accent)
        }
        .task(id: film.id) {
            do {
                let d = try await Catalog.detail(film.id)
                withAnimation(.smooth) { detail = d }
                library.hydrate(film, with: d)
                let a = await Catalog.art(d.ref.id)
                withAnimation(.easeOut(duration: 0.4)) { art = a; artLoaded = true }
            } catch { failed = true; artLoaded = true }
        }
        .task(id: heroURL) {
            if ProcessInfo.processInfo.environment["MATINEE_SCROLL"] != nil {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(.smooth(duration: 0.8)) { scroll.scrollTo(y: 640) }
            }
            guard let url = heroURL else { return }
            if let hit = Palette.cached(url) { palette = hit; return }
            if let p = await Palette.of(url) {
                withAnimation(.easeInOut(duration: 0.7)) { palette = p }
            }
        }
    }

    // MARK: Header

    /// Apple Music–style: a textless poster fills the screen, the film's logo is the title, and as you
    /// scroll the logo shrinks into the navigation bar and stays there.
    private var header: some View {
        let safeTop = Screen.safeTop
        return ZStack(alignment: .bottom) {
            Color.clear
                .overlay { RemoteImage(url: heroURL) }
                .clipped()
                .visualEffect { content, geo in
                    // Stretch the poster when you pull down past the top.
                    let y = geo.frame(in: .scrollView).minY
                    return content.scaleEffect(y > 0 ? 1 + y / max(geo.size.height, 1) : 1, anchor: .bottom)
                }
                // Tap the poster for the trailer, full screen.
                .contentShape(.rect)
                .onTapGesture { playTrailer() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Play trailer")
            LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.16),
                                   .init(color: .clear, location: 0.5), .init(color: bg.opacity(0.8), location: 0.78),
                                   .init(color: bg, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(spacing: 10) {
                TitleArt(title: ref.title, logo: art?.logo, aspect: art?.logoAspect ?? 3, maxWidth: 280, maxHeight: 110, fontSize: 40,
                         ready: artLoaded || failed)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
                    .visualEffect { content, geo in
                        // Shrink toward the nav bar as you scroll, then stay pinned there.
                        let f = geo.frame(in: .scrollView)
                        let pinTop = safeTop + 8
                        // Fit between the back button and the ••• menu: at most 30pt tall and 180pt wide.
                        let fit = min(1, 30 / max(f.height, 1), 180 / max(f.width, 1))
                        let travel: CGFloat = 220
                        let distance = f.minY - pinTop
                        let p = min(1, max(0, 1 - distance / travel))
                        let scale = 1 - p * (1 - fit)
                        return content.scaleEffect(scale, anchor: .top).offset(y: max(0, -distance))
                    }
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        if let g = detail?.genres.first { Text(g.uppercased()).foregroundStyle(palette?.highlight ?? Theme.accent); Text("·") }
                        if let y = ref.year { Text(yearSpan(y)) }
                        if let n = detail?.regularSeasons.count, ref.isShow, n > 0 { Text("·"); Text(n == 1 ? "1 season" : "\(n) seasons") }
                        else if let m = detail?.runtimeMinutes, m > 0 { Text("·"); Text("\(m / 60)h \(m % 60)m") }
                        if let r = detail?.communityRating, r > 0 {
                            Text("·")
                            Image(systemName: "star.fill").foregroundStyle(Theme.star)
                            Text((r / 2).formatted(.number.precision(.fractionLength(1))))
                        }
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    if let dirs = detail?.directors, !dirs.isEmpty {
                        Text("Directed by **\(dirs.prefix(2).joined(separator: ", "))**")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    } else if let c = detail?.creators, !c.isEmpty {
                        Text("Created by **\(c.prefix(2).joined(separator: ", "))**")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }
                    if trailerKey != nil {
                        Button { playTrailer() } label: {
                            Label("Trailer", systemImage: "play.fill").font(.footnote.weight(.bold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .contentShape(Capsule())
                                .glassEffect(.regular, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    Image(systemName: "chevron.compact.up")
                        .font(.title2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
                .visualEffect { content, geo in
                    let y = geo.frame(in: .scrollView).minY
                    return content.opacity(min(1, max(0, (y - 90) / 160)))
                }
            }
            .padding(.bottom, 18)
        }
        .containerRelativeFrame(.vertical)
        .frame(maxWidth: .infinity)
        .zIndex(1)   // keeps the pinned logo above the page as it scrolls
    }

    /// "2008" for a film; "2008–2013" or "2019–" for a show.
    private func yearSpan(_ y: Int) -> String {
        guard ref.isShow, let d = detail else { return String(y) }
        if d.hasEnded, let last = d.lastYear, last != y { return "\(y)–\(last)" }
        return d.hasEnded ? String(y) : "\(y)–"
    }

    private func playTrailer() {
        if trailerKey != nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showTrailer = true
        } else {
            library.toast = Toast(text: "No trailer for this one yet", symbol: "play.slash")
        }
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
            watchControl
            watchExtras
            Divider().overlay(Theme.line)
            if library.isComfort(ref.id) {
                VStack(spacing: 6) {
                    Image(systemName: "sofa.fill").font(.system(size: 30)).foregroundStyle(Theme.star)
                    Text("A comfort \(ref.isShow ? "show" : "film")").font(.headline)
                    Text("Watch it as often as you like — Matinee won't ask you to rate it.")
                        .font(.caption).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                }
                .padding(.vertical, 6)
            } else if ref.isShow {
                VStack(spacing: 8) {
                    Text(library.rating(ref.id) == nil ? "Rate the show" : "Your rating for the show")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
                    FilmRatingInput(score: library.rating(ref.id)) { library.rate(ref, $0) }
                    if let avg = library.progress(ref.id)?.average() {
                        Text("Your episodes average \(Score.describe(avg.score, style: ratingStyle)) across \(avg.count) rated")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
            } else {
                FilmRatingInput(score: library.rating(ref.id)) { library.rate(ref, $0) }
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

    /// Intermission mode: start watching, pause with a note, pick up later.
    @ViewBuilder private var watchControl: some View {
        if ref.isShow && watching.session(for: ref.id) == nil {
            // Shows start from an episode, in the list below.
            EmptyView()
        } else if let s = watching.session(for: ref.id) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if s.running {
                        TimelineView(.periodic(from: .now, by: 30)) { tl in
                            Label("\(s.episodeCode ?? "Watching") · \(filmClock(s.elapsed(at: tl.date)))\(s.runtime.map { " of \(filmClock($0))" } ?? "")", systemImage: "play.circle.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        GlassChip(prominent: true, action: { router.sheet = .intermission(s.id) }) {
                            Label("Intermission", systemImage: "pause.fill")
                        }
                    } else {
                        Label("Paused at \(filmClock(s.banked))", systemImage: "pause.circle.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        GlassChip(prominent: true, action: { watching.resume(s.id) }) {
                            Label("Resume", systemImage: "play.fill")
                        }
                    }
                }
                if let stop = s.lastStop, !s.running { IntermissionRow(stop: stop) }
            }
        } else {
            // GlassChip gives the capsule a hit shape before the interactive glass; without it the glass
            // swallowed the tap and nothing started.
            GlassChip(action: {
                watching.start(ref, runtime: detail?.runtimeMinutes)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                Label("Start watching", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
        }
    }

    /// Pin a show to Currently watching on Home, and mark a comfort title so it's never asked for a rating.
    private var watchExtras: some View {
        let comfort = library.isComfort(ref.id)
        return VStack(spacing: 8) {
            if let release = detail?.releaseDate, release > .now, !ref.isShow {
                let on = library.hasReminder(ref.id)
                GlassChip(prominent: on, action: {
                    library.toggleReminder(ref, on: release)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }) {
                    Label(on ? "Reminder on · \(release.formatted(.dateTime.day().month(.abbreviated)))"
                             : "Remind me when it's out · \(release.formatted(.dateTime.day().month(.abbreviated).year()))",
                          systemImage: on ? "bell.fill" : "bell")
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
            }
            if let s = watching.session(for: ref.id) {
                GlassChip(prominent: s.party != nil, action: {
                    if let code = s.party { router.sheet = .party(code) } else { hostParty(s) }
                }) {
                    Label(s.party.map { "Watch party · \($0)" } ?? (hosting ? "Starting party…" : "Watch together"), systemImage: "person.3.fill")
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .disabled(hosting)
            }
            comfortRow(comfort)
        }
    }

    private func hostParty(_ s: WatchSession) {
        guard auth.signedIn else { router.sheet = .signIn; return }
        hosting = true
        Task {
            let code = await Party.shared.host(s)
            hosting = false
            if let code { router.sheet = .party(code) }
            else { library.toast = Toast(text: Party.shared.error ?? "Couldn't start a party", symbol: "person.3") }
        }
    }

    private func comfortRow(_ comfort: Bool) -> some View {
        HStack(spacing: 8) {
            if ref.isShow {
                let pinned = library.isCurrentlyWatching(ref.id)
                GlassChip(prominent: pinned, action: {
                    library.toggleCurrentlyWatching(ref)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }) {
                    Label("Currently watching", systemImage: pinned ? "checkmark" : "pin")
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
            }
            GlassChip(prominent: comfort, action: {
                library.toggleComfort(ref)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                Label(ref.isShow ? "Comfort show" : "Comfort film", systemImage: comfort ? "sofa.fill" : "sofa")
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
        }
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
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(on ? color : .white.opacity(0.65))
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
                Text(t.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.white.opacity(0.65))
            }
            if let o = d.overview {
                Text(o).font(.body).foregroundStyle(.white.opacity(0.85)).lineLimit(expanded ? nil : 4)
                    .onTapGesture { withAnimation(.smooth) { expanded.toggle() } }
            }
            if !d.genres.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(d.genres, id: \.self) { g in
                            // Film genres open their page; TV-only ones ("Reality", "Kids"…) are just labels.
                            if Catalog.genres.contains(g) && !ref.isShow {
                                NavigationLink(value: GenreRoute(name: g)) { Text(g).font(.footnote.weight(.semibold)) }
                                    .buttonStyle(.glass).controlSize(.small)
                            } else {
                                Text(g).font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .glassEffect(.regular, in: .capsule)
                            }
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
                    Text("COMMUNITY").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(.white.opacity(0.65))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text((r / 2).formatted(.number.precision(.fractionLength(1)))).font(.system(size: 40, weight: .bold, design: .rounded))
                        Image(systemName: "star.fill").foregroundStyle(Theme.star)
                    }
                    if let v = d.voteCount { Text("\(v.formatted(.number.notation(.compactName))) ratings on TMDB").font(.caption).foregroundStyle(.white.opacity(0.65)) }
                }
                Spacer()
                StarRating(rating: ((r / 2) * 2).rounded() / 2, size: 18, spacing: 3)
            }
            .padding(18)
            .background(surface, in: .rect(cornerRadius: 22))
            .padding(.horizontal, 16)
        }

        if !d.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(ref.isShow ? "Cast" : "Cast & crew", subtitle: "Tap anyone for how many of their films you've seen")
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array((d.directorPeople + d.cast).enumerated()), id: \.offset) { _, p in
                            NavigationLink(value: PersonRoute(id: p.id, name: p.name)) {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(surface)
                                    Text(p.name.prefix(1)).font(.title2.bold()).foregroundStyle(.white.opacity(0.65))
                                    if p.photo != nil { RemoteImage(url: p.photo).clipShape(Circle()) }
                                }
                                .frame(width: 72, height: 72)
                                Text(p.name).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                                if !p.role.isEmpty { Text(p.role).font(.caption2).foregroundStyle(.white.opacity(0.65)).lineLimit(1) }
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

        if !d.countries.isEmpty || d.runtimeMinutes != nil || ref.isShow {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Details")
                VStack(spacing: 0) {
                    if ref.isShow {
                        if let st = d.status { detailRow("Status", st == "Returning Series" ? "Still running" : st) }
                        if !d.networks.isEmpty { detailRow(d.networks.count > 1 ? "Networks" : "Network", d.networks.prefix(3).joined(separator: ", ")) }
                        if let n = d.nextEpisode, let date = n.airDate {
                            detailRow("Next episode", "\(n.code) · \(date.formatted(.dateTime.day().month(.abbreviated)))")
                        }
                        if !d.creators.isEmpty { detailRow("Created by", d.creators.joined(separator: ", ")) }
                    }
                    if let m = d.runtimeMinutes, m > 0 { detailRow(ref.isShow ? "Episode length" : "Runtime", "\(m) minutes") }
                    if !d.countries.isEmpty { detailRow("Country", d.countries.prefix(3).joined(separator: ", ")) }
                    if !d.directors.isEmpty { detailRow(d.directors.count > 1 ? "Directors" : "Director", d.directors.joined(separator: ", ")) }
                }
                .background(surface, in: .rect(cornerRadius: 18))
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
            Text(k).foregroundStyle(.white.opacity(0.65))
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
                SectionHeader("Your diary", subtitle: ref.isShow ? (mine.count == 1 ? "1 entry" : "\(mine.count) entries")
                              : mine.count == 1 ? "Watched once" : "Watched \(mine.count) times")
                if !ref.isShow { RewatchChart(entries: mine, accent: palette?.highlight ?? Theme.accent, surface: surface) }
                VStack(spacing: 8) {
                    ForEach(mine) { e in
                        Button { router.sheet = .log(e.film, e) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(e.watchedOn.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                                    if let l = e.episodeLabel { Text(l).font(.caption.weight(.bold)).foregroundStyle(palette?.highlight ?? Theme.accent) }
                                    if e.rewatch { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.watch) }
                                    Spacer()
                                    SmallRating(rating: e.rating)
                                    if e.liked { Image(systemName: "heart.fill").foregroundStyle(Theme.heart).font(.caption) }
                                }
                                if !e.review.isEmpty { Text(e.review).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(4).multilineTextAlignment(.leading) }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(surface, in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// How your score for a film has moved each time you've watched it.
struct RewatchChart: View {
    let entries: [LogEntry]
    let accent: Color
    let surface: Color

    private var points: [LogEntry] { entries.filter { ($0.rating ?? 0) > 0 }.sorted { $0.watchedOn < $1.watchedOn } }

    var body: some View {
        let p = points
        if p.count >= 2, let first = p.first?.rating, let last = p.last?.rating {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary(first, last)).font(.subheadline.weight(.semibold))
                Chart(p) { e in
                    LineMark(x: .value("Watched", e.watchedOn), y: .value("Score", e.rating ?? 0))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(accent)
                    PointMark(x: .value("Watched", e.watchedOn), y: .value("Score", e.rating ?? 0))
                        .foregroundStyle(Score.color(e.rating ?? 0))
                        .annotation(position: .top) {
                            Text(Score.text(e.rating)).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.8))
                        }
                }
                .chartYScale(domain: max(0, (p.compactMap(\.rating).min() ?? 0) - 15)...100)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: p.map(\.watchedOn)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    }
                }
                .frame(height: 120)
            }
            .padding(16)
            .background(surface, in: .rect(cornerRadius: 18))
        }
    }

    private func summary(_ a: Double, _ b: Double) -> String {
        let d = Int((b - a).rounded())
        if abs(d) < 3 { return "You've felt the same about it every time" }
        return d > 0 ? "It's grown on you: up \(d) points since the first watch" : "It's lost a little shine: down \(-d) points since the first watch"
    }
}
