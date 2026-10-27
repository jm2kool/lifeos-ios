import SwiftUI
import Charts

/// Your year in film, a card at a time: how much you watched, your top films, your busiest month,
/// your genres and habits, and (with Apple Intelligence) a few lines written about it on your iPhone.
struct YearInReviewView: View {
    let year: Int
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var shown: Int
    @State private var page = 0
    @State private var summary: String?
    @State private var writing = false
    @State private var shareImage: UIImage?
    @State private var palette: [Color] = [Theme.accent, Theme.heart]

    init(year: Int) {
        self.year = year
        _shown = State(initialValue: year)
    }

    private var years: [Int] {
        let ys = Set(library.doc.entries.map(\.watchedOn.year) + [Date.now.year])
        return ys.sorted(by: >)
    }

    var body: some View {
        let r = YearReview(year: shown, library: library, facts: FactStore.shared)
        NavigationStack {
            Group {
                if r.filmCount == 0 && r.episodes == 0 {
                    EmptyState(symbol: "calendar", title: "Nothing logged in \(String(shown))",
                               message: "Films and episodes you log this year will add up here.")
                } else {
                    TabView(selection: $page) {
                        intro(r).tag(0)
                        if !r.topRated.isEmpty { topFilms(r).tag(1) }
                        months(r).tag(2)
                        taste(r).tag(3)
                        habits(r).tag(4)
                        if !r.topShows.isEmpty { shows(r).tag(5) }
                        outro(r).tag(6)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }
            }
            .background {
                ZStack {
                    Color.black
                    LinearGradient(colors: palette.map { $0.opacity(0.55) } + [.black], startPoint: .topLeading, endPoint: .bottom)
                        .animation(.easeInOut(duration: 0.8), value: page)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
                if years.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Menu {
                            ForEach(years, id: \.self) { y in Button(String(y)) { shown = y; page = 0; summary = nil; shareImage = nil } }
                        } label: {
                            HStack(spacing: 4) { Text(String(shown)).font(.headline); Image(systemName: "chevron.down").font(.caption.weight(.bold)) }
                        }
                    }
                }
                if let img = shareImage {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview("My \(String(shown)) in film", image: Image(uiImage: img))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .presentationBackground(.black)
        .task(id: shown) {
            await FactStore.shared.fill(library.doc.entries.filter { $0.watchedOn.year == shown }.map(\.film))
            let fresh = YearReview(year: shown, library: library, facts: FactStore.shared)
            await loadPalette(fresh)
            shareImage = await YearShareCard.render(fresh)
            if Intelligence.isAvailable && summary == nil {
                writing = true
                summary = await Intelligence.yearSummary(fresh)
                writing = false
            }
        }
    }

    private func loadPalette(_ r: YearReview) async {
        var out: [Color] = []
        for f in r.topRated.prefix(3) { if let p = await Palette.of(f.film.poster) { out.append(p.glow) } }
        if out.count >= 2 { withAnimation(.easeInOut(duration: 1)) { palette = out } }
    }

    // MARK: Pages

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 60)
    }

    private func kicker(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption.weight(.heavy)).tracking(1.6).foregroundStyle(.white.opacity(0.7))
    }

    private func big(_ t: String) -> some View {
        Text(t).font(.system(size: 76, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
    }

    private func intro(_ r: YearReview) -> some View {
        card {
            Spacer()
            kicker("Your \(String(r.year)) in film")
            big("\(r.filmCount)")
            Text(r.filmCount == 1 ? "film" : "films").font(.title.weight(.bold))
            if r.minutes > 0 {
                let h = r.minutes / 60
                Text("That's \(h) hours\(h >= 24 ? " — \(h / 24) whole days" : "") in front of a screen.").font(.title3).foregroundStyle(.white.opacity(0.85))
            }
            if r.episodes > 0 { Text("Plus \(r.episodes) episodes of TV.").font(.title3).foregroundStyle(.white.opacity(0.85)) }
            if let f = r.first {
                HStack(spacing: 12) {
                    PosterView(film: f.film, width: 54, corner: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("It all started with").font(.caption).foregroundStyle(Theme.dim)
                        Text(f.film.title).font(.headline)
                        Text(f.watchedOn.formatted(.dateTime.day().month(.wide))).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.top, 10)
            }
            Spacer()
            Text("Swipe for more →").font(.footnote.weight(.semibold)).foregroundStyle(Theme.dim)
        }
    }

    private func topFilms(_ r: YearReview) -> some View {
        card {
            kicker("Your top films")
            Text("The ones you rated highest").font(.title2.weight(.bold))
            VStack(spacing: 12) {
                ForEach(Array(r.topRated.enumerated()), id: \.offset) { i, t in
                    HStack(spacing: 14) {
                        Text("\(i + 1)").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.5)).frame(width: 30)
                        PosterView(film: t.film, width: i == 0 ? 70 : 52, corner: 6)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.film.title).font(i == 0 ? .title3.weight(.bold) : .headline).lineLimit(2)
                            Text(t.film.yearText).font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        RatingValue(score: t.score)
                    }
                }
            }
            Spacer()
        }
    }

    private func months(_ r: YearReview) -> some View {
        card {
            kicker("Month by month")
            if let m = r.busiestMonth {
                Text("\(m.name) was your big month").font(.title2.weight(.bold))
                Text("\(m.count) films").font(.title3).foregroundStyle(.white.opacity(0.8))
            }
            let peak = r.months.max() ?? 0
            Chart(Array(r.months.enumerated()), id: \.offset) { item in
                BarMark(x: .value("Month", Calendar.current.shortMonthSymbols[item.offset]), y: .value("Films", item.element))
                    .foregroundStyle(item.element == peak ? Theme.accent.gradient : Color.white.opacity(0.35).gradient)
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .frame(height: 220)
            Spacer()
        }
    }

    private func taste(_ r: YearReview) -> some View {
        card {
            kicker("Your taste")
            if let g = r.genres.first {
                Text("You were all about \(g.name.lowercased())").font(.title2.weight(.bold))
            } else {
                Text("A bit of everything").font(.title2.weight(.bold))
            }
            ForEach(r.genres) { g in
                HStack {
                    Text(g.name).font(.headline)
                    Spacer()
                    Text("\(g.count)").font(.headline.monospacedDigit()).foregroundStyle(Theme.accent)
                }
                GeometryReader { geo in
                    Capsule().fill(Theme.accent.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(g.count) / CGFloat(max(1, r.genres.first?.count ?? 1)))
                }
                .frame(height: 6)
            }
            if let d = r.director, let p = d.person {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.card)
                        if p.photo != nil { RemoteImage(url: p.photo).clipShape(Circle()) }
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Director of the year").font(.caption).foregroundStyle(Theme.dim)
                        Text(p.name).font(.headline)
                        Text("\(d.count) films").font(.caption).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.top, 12)
            }
            if let avg = r.average {
                HStack {
                    Text("Your average score").font(.subheadline).foregroundStyle(Theme.dim)
                    Spacer()
                    RatingValue(score: avg)
                }
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    private func habits(_ r: YearReview) -> some View {
        card {
            kicker("Your habits")
            Text("How you watched").font(.title2.weight(.bold))
            VStack(spacing: 14) {
                if let w = r.weekday { fact("calendar", "\(w.name)s", "your favourite night — \(w.count) films") }
                if r.streak > 1 { fact("flame.fill", "\(r.streak) days", "your longest run of films in a row") }
                if r.rewatches > 0 { fact("arrow.triangle.2.circlepath", "\(r.rewatches) rewatches", "old favourites you went back to") }
                if r.liked > 0 { fact("heart.fill", "\(r.liked) loved", "films you gave a heart") }
                if let t = r.tags.first { fact("number", "#\(t.name)", "your most-used tag, \(t.count) times") }
            }
            Spacer()
        }
    }

    private func fact(_ symbol: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Theme.accent).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.weight(.bold))
                Text(label).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 18))
    }

    private func shows(_ r: YearReview) -> some View {
        card {
            kicker("On TV")
            Text("\(r.episodes) episodes").font(.title2.weight(.bold))
            ForEach(Array(r.topShows.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 14) {
                    PosterView(film: s.show, width: 56, corner: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.show.title).font(.headline)
                        Text("\(s.episodes) episodes").font(.subheadline).foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer()
        }
    }

    private func outro(_ r: YearReview) -> some View {
        card {
            kicker("That's a wrap")
            if let summary {
                Label("Written on your iPhone", systemImage: "apple.intelligence").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                Text(summary).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            } else if writing {
                HStack(spacing: 10) { ProgressView(); Text("Writing your year up…").foregroundStyle(Theme.dim) }
            } else {
                Text("\(r.filmCount) films, \(r.minutes / 60) hours, and a lot of popcorn.").font(.title2.weight(.bold))
            }
            if let img = shareImage {
                Image(uiImage: img).resizable().aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(.rect(cornerRadius: 16))
                    .frame(maxWidth: .infinity)
                ShareLink(item: Image(uiImage: img), preview: SharePreview("My \(String(r.year)) in film", image: Image(uiImage: img))) {
                    Label("Share your year", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            Spacer()
        }
    }
}

/// The story-sized picture of your year: top five posters, the big numbers, and Matinee's mark.
struct YearShareCard: View {
    let review: YearReview
    let posters: [UIImage]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.7), Theme.heart.opacity(0.45), .black], startPoint: .topLeading, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 44) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MY \(String(review.year)) IN FILM").font(.system(size: 44, weight: .heavy)).tracking(4).foregroundStyle(.white.opacity(0.8))
                    Text("\(review.filmCount) films").font(.system(size: 150, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5)
                    HStack(spacing: 40) {
                        if review.minutes > 0 { number("\(review.minutes / 60)", "hours") }
                        if review.episodes > 0 { number("\(review.episodes)", "episodes") }
                        if review.rewatches > 0 { number("\(review.rewatches)", "rewatches") }
                    }
                }
                if !posters.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("TOP FILMS").font(.system(size: 36, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.7))
                        HStack(spacing: 18) {
                            ForEach(Array(posters.prefix(5).enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img).resizable().aspectRatio(2 / 3, contentMode: .fill)
                                    .frame(width: 168, height: 252).clipShape(.rect(cornerRadius: 14))
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    if let g = review.genres.first { line("Top genre", g.name) }
                    if let m = review.busiestMonth { line("Busiest month", m.name) }
                    if let d = review.director { line("Director of the year", d.name) }
                    if let w = review.weekday { line("Favourite night", w.name) }
                }
                Spacer()
                HStack(spacing: 14) {
                    MatineeMark().frame(width: 64, height: 64)
                    Text("Matinee").font(.system(size: 50, weight: .heavy, design: .serif))
                }
            }
            .foregroundStyle(.white)
            .padding(80)
            .padding(.top, 80)
        }
        .frame(width: 1080, height: 1920)
        .background(Color.black)
    }

    private func number(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.system(size: 70, weight: .heavy, design: .rounded))
            Text(l).font(.system(size: 32, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 38, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(v).font(.system(size: 42, weight: .bold))
        }
    }

    @MainActor
    static func render(_ r: YearReview) async -> UIImage? {
        var imgs: [UIImage] = []
        for t in r.topRated.prefix(5) {
            if let url = t.film.poster, let img = await ImageStore.shared.load(url) { imgs.append(img) }
        }
        let renderer = ImageRenderer(content: YearShareCard(review: r, posters: imgs))
        renderer.scale = 1
        return renderer.uiImage
    }
}
