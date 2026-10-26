import SwiftUI

// MARK: - Seasons and episodes on a show's page

/// Season tabs, the episode list with a tick for each one you've seen, and your ratings.
/// Finishing a season (or the whole show) brings up the wrap-up.
struct SeasonsSection: View {
    let show: FilmRef
    let detail: FilmDetail
    var surface: Color = Theme.card
    var accent: Color = Theme.accent
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(Watching.self) private var watching
    @State private var selected: Int?
    @State private var episodes: [Int: [Episode]] = [:]
    @State private var failed: Set<Int> = []
    @State private var pendingWrap: WrapRequest?

    private struct WrapRequest: Equatable { var season: Int; var series: Bool }

    /// The regular seasons in order, then the specials.
    private var seasons: [SeasonInfo] {
        detail.regularSeasons + detail.seasons.filter { $0.number == 0 && $0.episodeCount > 0 }
    }

    /// Where you're up to: the first season you haven't finished.
    private var current: Int {
        if let selected { return selected }
        return detail.regularSeasons.first { library.seenCount(show.id, season: $0.number) < $0.episodeCount }?.number
            ?? detail.regularSeasons.last?.number ?? seasons.first?.number ?? 1
    }

    private var totalSeen: Int { detail.regularSeasons.reduce(0) { $0 + min($1.episodeCount, library.seenCount(show.id, season: $1.number)) } }
    private var totalEpisodes: Int { detail.regularSeasons.reduce(0) { $0 + $1.episodeCount } }

    var body: some View {
        if !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Episodes", subtitle: totalSeen == 0 ? "\(totalEpisodes) episodes · tick them off as you go"
                              : "You've seen \(totalSeen) of \(totalEpisodes)")
                if totalSeen > 0 {
                    ProgressView(value: Double(totalSeen), total: Double(max(1, totalEpisodes)))
                        .tint(Theme.watch)
                        .padding(.horizontal, 20)
                }
                seasonPicker
                if let info = seasons.first(where: { $0.number == current }) { seasonCard(info) }
                episodeList
            }
            .task(id: current) {
                // Pin the season you're on, so finishing it doesn't jump the page to the next one mid-celebration.
                if selected == nil { selected = current }
                await load(current)
            }
            .onChange(of: library.seenCount(show.id, season: current)) { old, new in
                seasonMayHaveFinished(current, from: old, to: new)
            }
            .onChange(of: router.sheet == nil) { _, closed in if closed { presentPendingWrap() } }
        }
    }

    // MARK: Season picker

    private var seasonPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(seasons) { s in
                        let seen = library.seenCount(show.id, season: s.number)
                        let on = s.number == current
                        Button {
                            withAnimation(.smooth) { selected = s.number }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            HStack(spacing: 8) {
                                ProgressRing(progress: s.episodeCount > 0 ? Double(seen) / Double(s.episodeCount) : 0, tint: Theme.watch)
                                    .frame(width: 16, height: 16)
                                Text(s.number == 0 ? "Specials" : "Season \(s.number)")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(on ? accent.opacity(0.28) : surface, in: .capsule)
                            .overlay(Capsule().strokeBorder(on ? accent : .clear, lineWidth: 1.2))
                        }
                        .buttonStyle(.plain)
                        .id(s.number)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
    }

    // MARK: Season card: progress, your ratings, mark all

    private func seasonCard(_ info: SeasonInfo) -> some View {
        let seen = library.seenCount(show.id, season: info.number)
        let aired = episodes[info.number]?.filter(\.aired) ?? []
        let allSeen = !aired.isEmpty && aired.allSatisfy { library.isSeen(show.id, $0) }
        let avg = library.progress(show.id)?.average(season: info.number)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.name).font(.headline)
                    Text(["\(seen) of \(info.episodeCount) watched", info.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                if !aired.isEmpty {
                    Button {
                        library.setSeen(show, aired, !allSeen)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label(allSeen ? "Unmark all" : "Mark all watched", systemImage: allSeen ? "arrow.uturn.backward" : "checkmark.circle")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.glass).controlSize(.small)
                }
            }
            if info.number > 0 && !library.isComfort(show.id) && (avg != nil || allSeen || library.seasonRating(show.id, info.number) != nil) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EPISODES AVG").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(.white.opacity(0.55))
                        if let avg {
                            RatingValue(score: avg.score)
                            Text("\(avg.count) rated").font(.caption2).foregroundStyle(.white.opacity(0.55))
                        } else {
                            Text("–").font(.title3.weight(.bold))
                        }
                    }
                    Divider().frame(height: 46).overlay(Theme.line)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR SEASON RATING").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(.white.opacity(0.55))
                        CompactRatingInput(score: library.seasonRating(show.id, info.number)) {
                            library.rateSeason(show, info.number, $0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(surface, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    // MARK: Episodes

    @ViewBuilder private var episodeList: some View {
        if let eps = episodes[current] {
            let next = eps.first { $0.aired && !library.isSeen(show.id, $0) }
            LazyVStack(spacing: 8) {
                ForEach(eps) { ep in
                    EpisodeRow(show: show, episode: ep, upNext: ep.id == next?.id, surface: surface, accent: accent,
                               fallbackRuntime: detail.runtimeMinutes)
                }
            }
            .padding(.horizontal, 16)
        } else if failed.contains(current) {
            Button("Couldn't load episodes — try again") { failed.remove(current); Task { await load(current) } }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }

    private func load(_ season: Int) async {
        guard episodes[season] == nil else { return }
        if let hit = Catalog.cachedSeason(show.id, season) { episodes[season] = hit; return }
        do {
            let eps = try await Catalog.season(show.id, season)
            withAnimation(.smooth) { episodes[season] = eps }
        } catch { failed.insert(season) }
    }

    // MARK: Wrap-up when a season or the show is finished

    private func seasonMayHaveFinished(_ season: Int, from old: Int, to new: Int) {
        guard season > 0, new > old, let eps = episodes[season] else { return }
        let aired = eps.filter(\.aired)
        guard !aired.isEmpty, old < aired.count, aired.allSatisfy({ library.isSeen(show.id, $0) }) else { return }
        Task {
            let series = await allSeasonsFinished()
            // Comfort shows don't get asked for a rating; a finished one still joins your watched titles.
            if library.isComfort(show.id) {
                if series && detail.hasEnded { library.finishShow(show) }
                return
            }
            pendingWrap = WrapRequest(season: season, series: series)
            presentPendingWrap()
        }
    }

    /// Every episode that has aired, in every regular season, is ticked off.
    private func allSeasonsFinished() async -> Bool {
        for s in detail.regularSeasons {
            var found = episodes[s.number]
            if found == nil { found = try? await Catalog.season(show.id, s.number) }
            guard let eps = found else { return false }
            if eps.contains(where: { $0.aired && !library.isSeen(show.id, $0) }) { return false }
        }
        return true
    }

    /// Waits for any open sheet (say, the episode you just rated) to close first.
    private func presentPendingWrap() {
        guard pendingWrap != nil, router.sheet == nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            guard router.sheet == nil, let w = pendingWrap else { return }
            pendingWrap = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            router.sheet = .wrap(show, w.season, w.series)
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    var tint: Color = Theme.watch
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 2.5)
            Circle().trim(from: 0, to: min(1, progress)).stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress >= 1 { Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(tint) }
        }
    }
}

struct EpisodeRow: View {
    let show: FilmRef
    let episode: Episode
    var upNext = false
    var surface: Color = Theme.card
    var accent: Color = Theme.accent
    var fallbackRuntime: Int?
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(Watching.self) private var watching

    var body: some View {
        let seen = library.isSeen(show.id, episode)
        VStack(alignment: .leading, spacing: 10) {
            if upNext {
                Text("UP NEXT").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(accent)
            }
            HStack(spacing: 12) {
                Button {
                    library.toggleSeen(show, episode)
                    UIImpactFeedbackGenerator(style: seen ? .light : .medium).impactOccurred()
                } label: {
                    Image(systemName: seen ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26))
                        .foregroundStyle(seen ? Theme.watch : .white.opacity(episode.aired ? 0.45 : 0.15))
                        .symbolEffect(.bounce, value: seen)
                        .frame(width: 34, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!episode.aired && !seen)
                .accessibilityLabel(seen ? "Watched \(episode.code)" : "Mark \(episode.code) watched")

                Button { router.sheet = .episode(show, episode) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Rectangle().fill(Color.white.opacity(0.06))
                            if episode.still != nil { RemoteImage(url: episode.still) }
                            else { Image(systemName: "tv").foregroundStyle(.white.opacity(0.3)) }
                        }
                        .frame(width: 96, height: 54)
                        .clipShape(.rect(cornerRadius: 8))
                        .opacity(seen ? 0.6 : 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(episode.number). \(episode.name)").font(.subheadline.weight(.semibold)).lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                if !episode.aired {
                                    Text(episode.airDate.map { "Airs \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? "Not aired yet")
                                        .foregroundStyle(accent)
                                } else if let m = episode.runtime ?? fallbackRuntime, m > 0 {
                                    Text(filmClock(TimeInterval(m * 60)))
                                }
                                SmallRating(rating: library.episodeRating(show.id, episode))
                            }
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            if upNext {
                HStack(spacing: 8) {
                    GlassChip(prominent: true, action: {
                        watching.start(show, episode: episode, runtime: fallbackRuntime)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) { Label("Start watching", systemImage: "play.fill") }
                    GlassChip(action: { library.setSeen(show, [episode], true) }) { Label("Watched", systemImage: "checkmark") }
                }
            }
        }
        .padding(.vertical, upNext ? 14 : 6).padding(.horizontal, upNext ? 12 : 4)
        .background(upNext ? surface : .clear, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(upNext ? accent.opacity(0.6) : .clear, lineWidth: 1))
    }
}

// MARK: - One episode

struct EpisodeSheet: View {
    let show: FilmRef
    let episode: Episode
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(Watching.self) private var watching
    @Environment(\.dismiss) private var dismiss
    @State private var palette: PosterPalette?

    private var bg: Color { palette?.background ?? .black }
    private var surface: Color { palette?.surface ?? Theme.card }

    var body: some View {
        let seen = library.isSeen(show.id, episode)
        let rating = library.episodeRating(show.id, episode)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .bottomLeading) {
                        Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                            .overlay { RemoteImage(url: episode.still ?? show.backdrop) }
                            .clipped()
                        LinearGradient(colors: [.clear, bg], startPoint: .center, endPoint: .bottom)
                    }
                    .clipShape(.rect(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(show.title.uppercased()) · \(episode.code)").font(.caption.weight(.heavy)).tracking(1.2)
                            .foregroundStyle(palette?.highlight ?? Theme.accent)
                        Text(episode.name).font(.title2.weight(.bold))
                        HStack(spacing: 6) {
                            if let d = episode.airDate { Text(d.formatted(date: .abbreviated, time: .omitted)) }
                            if let m = episode.runtime, m > 0 { Text("·"); Text(filmClock(TimeInterval(m * 60))) }
                            if let r = episode.communityRating, r > 0 {
                                Text("·")
                                Image(systemName: "star.fill").foregroundStyle(Theme.star)
                                Text((r / 2).formatted(.number.precision(.fractionLength(1))))
                            }
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                    if let o = episode.overview { Text(o).foregroundStyle(.white.opacity(0.85)) }

                    if episode.aired {
                        VStack(spacing: 16) {
                            Button {
                                library.toggleSeen(show, episode)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } label: {
                                Label(seen ? "Watched" : "Mark as watched", systemImage: seen ? "checkmark.circle.fill" : "circle")
                                    .font(.headline)
                                    .foregroundStyle(seen ? Theme.watch : .white)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass).controlSize(.large)
                            if library.isComfort(show.id) {
                                Label("Comfort show — no ratings asked", systemImage: "sofa.fill")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                            } else {
                                VStack(spacing: 8) {
                                    Text(rating == nil ? "Rate this episode" : "Your rating")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
                                    FilmRatingInput(score: rating, dialSize: 180) { library.rateEpisode(show, episode, $0) }
                                }
                            }
                            HStack(spacing: 10) {
                                Button {
                                    router.sheet = .logEpisode(LogEntry(film: show, rating: rating, season: episode.season,
                                                                        episode: episode.number, episodeTitle: episode.name))
                                } label: { Label("Review or log", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                                .buttonStyle(.glassProminent)
                                Button {
                                    watching.start(show, episode: episode, runtime: Catalog.cached(show.id)?.runtimeMinutes)
                                    dismiss()
                                } label: { Image(systemName: "play.fill").frame(width: 24) }
                                .buttonStyle(.glass)
                                .accessibilityLabel("Start watching")
                            }
                            .controlSize(.large)
                        }
                        .padding(18)
                        .glassEffect(.regular, in: .rect(cornerRadius: 26))
                    } else {
                        Label(episode.airDate.map { "Airs \($0.formatted(date: .long, time: .omitted))" } ?? "Hasn't aired yet",
                              systemImage: "calendar")
                            .font(.headline).foregroundStyle(palette?.highlight ?? Theme.accent)
                    }

                    let mine = library.entries(for: show.id).filter { $0.season == episode.season && $0.episode == episode.number }
                    if !mine.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR DIARY").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(.white.opacity(0.65))
                            ForEach(mine) { e in
                                Button { router.sheet = .log(e.film, e) } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(e.watchedOn.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                                            Spacer()
                                            SmallRating(rating: e.rating)
                                        }
                                        if !e.review.isEmpty { Text(e.review).font(.subheadline).foregroundStyle(.white.opacity(0.8)).lineLimit(4) }
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(surface, in: .rect(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(bg.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle(episode.code)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(bg)
        .animation(.easeInOut(duration: 0.5), value: palette)
        .task {
            if let hit = Palette.cached(show.poster) { palette = hit; return }
            palette = await Palette.of(show.poster)
        }
    }
}

// MARK: - Season / series wrap-up

/// At the end of a season (and of the whole show): the average of what you gave each episode,
/// next to a rating that's yours to choose.
struct SeasonWrapSheet: View {
    let show: FilmRef
    let season: Int
    let series: Bool
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var detail: FilmDetail?
    @State private var palette: PosterPalette?

    private var bg: Color { palette?.background ?? .black }
    private var surface: Color { palette?.surface ?? Theme.card }
    private var progress: ShowProgress? { library.progress(show.id) }
    private var seasonInfo: SeasonInfo? { detail?.seasons.first { $0.number == season } }

    private var headline: String {
        guard series else { return "Season \(season) done" }
        return detail?.hasEnded == false ? "All caught up" : "Series complete"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        PosterView(film: FilmRef(id: show.id, title: show.title, year: show.year,
                                                 poster: seasonInfo?.poster ?? show.poster), width: 130, corner: 12)
                        Text(series ? "🎉" : "✨").font(.system(size: 34))
                        Text(headline).font(.largeTitle.weight(.heavy)).multilineTextAlignment(.center)
                        Text(show.title).font(.headline).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 8)

                    if season > 0 {
                        card(label: series ? "SEASON \(season)" : "THE SEASON",
                             average: progress?.average(season: season),
                             bars: barData(season: season),
                             ratingTitle: "Your rating for season \(season)",
                             rating: library.seasonRating(show.id, season)) { library.rateSeason(show, season, $0) }
                    }
                    if series {
                        card(label: "THE WHOLE SHOW",
                             average: progress?.average(),
                             bars: seasonBars,
                             ratingTitle: "Your rating for \(show.title)",
                             rating: library.rating(show.id)) { library.rate(show, $0) }
                    }

                    Button { dismiss() } label: { Text("Done").font(.headline).frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent).controlSize(.large)
                }
                .padding(20)
            }
            .background {
                ZStack {
                    bg
                    if let g = palette?.glow { Circle().fill(g).frame(width: 420, height: 420).blur(radius: 120).opacity(0.5).offset(y: -260) }
                }
                .ignoresSafeArea()
            }
            .scrollContentBackground(.hidden)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(bg)
        .animation(.easeInOut(duration: 0.5), value: palette)
        .task {
            palette = Palette.cached(show.poster)
            if palette == nil { palette = await Palette.of(show.poster) }
        }
        .task {
            detail = try? await Catalog.detail(show.id)
            // A finished show that has ended joins your watched titles; one still running stays in progress.
            if series, detail?.hasEnded == true { library.finishShow(show) }
        }
    }

    private struct Bar: Identifiable { var id: String; var label: String; var score: Double? }

    /// One bar per episode you saw this season, tall as your rating.
    private func barData(season: Int) -> [Bar] {
        guard let p = progress else { return [] }
        return p.seen.keys.filter { EpisodeKey.season(of: $0) == season }
            .compactMap { k in EpisodeKey.episode(of: k).map { (k, $0) } }
            .sorted { $0.1 < $1.1 }
            .map { Bar(id: $0.0, label: "\($0.1)", score: p.episodeRatings[$0.0]) }
    }

    /// For the whole show: one bar per season, at the average of its episodes.
    private var seasonBars: [Bar] {
        guard let p = progress else { return [] }
        let numbers = Set(p.seen.keys.compactMap(EpisodeKey.season(of:))).filter { $0 > 0 }.sorted()
        return numbers.map { Bar(id: "s\($0)", label: "S\($0)", score: p.average(season: $0)?.score) }
    }

    private func card(label: String, average: (score: Double, count: Int)?, bars: [Bar], ratingTitle: String,
                      rating: Double?, onRate: @escaping (Double?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(label).font(.caption.weight(.heavy)).tracking(1.4).foregroundStyle(.white.opacity(0.6))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let average {
                    RatingValue(score: average.score, font: .system(size: 48, weight: .bold, design: .rounded), symbolFont: .title2)
                    Spacer()
                    Text("average of the \(average.count) episode\(average.count == 1 ? "" : "s") you rated")
                        .font(.caption).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.trailing)
                } else {
                    Text("You didn't rate any episodes — give it a rating of your own below.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
            }

            if bars.contains(where: { $0.score != nil }) {
                HStack(alignment: .bottom, spacing: bars.count > 16 ? 2 : 4) {
                    ForEach(bars) { b in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(b.score.map { Score.color($0).opacity(0.35 + 0.65 * $0 / 100) } ?? Color.white.opacity(0.12))
                                .frame(height: max(4, 64 * CGFloat((b.score ?? 0) / 100)))
                            if bars.count <= 16 {
                                Text(b.label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 82, alignment: .bottom)
            }

            Divider().overlay(Theme.line)

            VStack(alignment: .leading, spacing: 10) {
                Text(ratingTitle).font(.subheadline.weight(.semibold))
                FilmRatingInput(score: rating, dialSize: 180, onChange: onRate)
                    .frame(maxWidth: .infinity)
                if let average, rating == nil {
                    let rounded = Score.rounded(average.score)
                    Button { onRate(rounded) } label: {
                        Label("Use my average · \(Score.describe(rounded))", systemImage: "wand.and.stars").font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.glass).controlSize(.small)
                } else if let rating, let average {
                    let diff = rating - average.score
                    Text(abs(diff) < 5 ? "Right in line with your episodes."
                         : diff > 0 ? "Higher than your episodes — the whole was more than its parts."
                         : "Lower than your episodes added up to.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(18)
        .background(surface, in: .rect(cornerRadius: 24))
    }
}

// MARK: - Shows in progress

/// Posters of shows you're partway through, each with how far you've got.
struct ShowProgressRow: View {
    let shows: [FilmRef]
    @Environment(Library.self) private var library
    @AppStorage(FilmRatingStyle.key) private var style: FilmRatingStyle = .score

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(shows) { s in
                    NavigationLink(value: s) {
                        VStack(alignment: .leading, spacing: 6) {
                            PosterView(film: s, width: 112)
                            if let last = lastSeen(s.id) {
                                Text("Last: \(last)").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                            }
                            if let avg = library.progress(s.id)?.average() {
                                Text("\(Score.describe(avg.score, style: style)) avg")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(style == .stars ? Theme.star : Score.color(avg.score))
                            }
                        }
                        .frame(width: 112, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .filmContextMenu(s)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// The furthest episode you've ticked off: "S2 E4".
    private func lastSeen(_ id: String) -> String? {
        library.progress(id)?.lastSeen.map { EpisodeKey.code($0.season, $0.episode) }
    }
}

// MARK: - Currently watching

/// Shows you've pinned, at the top of Home: the next episode to tick off or start, and the last one to rate.
struct CurrentlyWatchingSection: View {
    let shows: [FilmRef]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Currently watching", subtitle: "Tick off the next episode, rate the last")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shows) { s in
                        CurrentlyWatchingCard(show: s)
                            .containerRelativeFrame(.horizontal) { w, _ in shows.count == 1 ? w - 32 : min(340, w - 64) }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

struct CurrentlyWatchingCard: View {
    let show: FilmRef
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(Watching.self) private var watching
    @State private var detail: FilmDetail?
    @State private var next: Episode?
    @State private var caughtUp = false
    @State private var loaded = false

    private var last: (season: Int, episode: Int)? { library.progress(show.id)?.lastSeen }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NavigationLink(value: show) { PosterView(film: show, width: 62, corner: 7) }
                    .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.title).font(.headline).lineLimit(1)
                    if let next {
                        Text("\(caughtUp ? "NEXT TO AIR" : "UP NEXT") · \(next.code)")
                            .font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(Theme.accent)
                        Text(next.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if caughtUp, let d = next.airDate {
                            Text("Airs \(d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                                .font(.caption).foregroundStyle(Theme.dim)
                        } else if let m = next.runtime ?? detail?.runtimeMinutes, m > 0 {
                            Text(filmClock(TimeInterval(m * 60))).font(.caption).foregroundStyle(Theme.dim)
                        }
                    } else if loaded {
                        Text(detail?.hasEnded == true ? "You've seen every episode" : "All caught up")
                            .font(.subheadline).foregroundStyle(Theme.dim)
                    } else {
                        ProgressView().controlSize(.small).padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            .onTapGesture { if let next { router.sheet = .episode(show, next) } else { router.open(show) } }

            if let next, !caughtUp {
                HStack(spacing: 8) {
                    GlassChip(prominent: true, action: {
                        library.setSeen(show, [next], true)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) { Label("Watched", systemImage: "checkmark") }
                    GlassChip(action: {
                        watching.start(show, episode: next, runtime: detail?.runtimeMinutes)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) { Label("Start", systemImage: "play.fill") }
                }
            }

            if let last, !library.isComfort(show.id) {
                let key = EpisodeKey.make(last.season, last.episode)
                let rating = library.progress(show.id)?.episodeRatings[key]
                Divider().overlay(Theme.line)
                HStack(spacing: 12) {
                    Text(rating == nil ? "Rate \(EpisodeKey.code(last.season, last.episode))" : EpisodeKey.code(last.season, last.episode))
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                        .fixedSize()
                    CompactRatingInput(score: rating, starSize: 24) {
                        library.rateEpisode(show, Episode(season: last.season, number: last.episode, name: ""), $0)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .contextMenu {
            Button { router.open(show) } label: { Label("Open show", systemImage: "tv") }
            Button(role: .destructive) { library.toggleCurrentlyWatching(show) } label: { Label("Remove from Currently watching", systemImage: "pin.slash") }
        }
        .task(id: "\(show.id)|\(library.progress(show.id)?.seen.count ?? 0)") { await findNext() }
    }

    /// The first aired episode you haven't ticked off, season by season. When you're caught up,
    /// the next one to air (if TMDB knows it).
    private func findNext() async {
        guard let d = try? await Catalog.detail(show.id) else { loaded = true; return }
        detail = d
        for s in d.regularSeasons where library.seenCount(show.id, season: s.number) < s.episodeCount {
            guard let eps = try? await Catalog.season(show.id, s.number) else { break }
            if let e = eps.first(where: { $0.aired && !library.isSeen(show.id, $0) }) {
                withAnimation(.smooth) { next = e; caughtUp = false; loaded = true }
                return
            }
            // The rest of this season hasn't aired, so neither has anything after it.
            if eps.contains(where: { !$0.aired }) { break }
        }
        withAnimation(.smooth) { next = d.nextEpisode; caughtUp = true; loaded = true }
    }
}
