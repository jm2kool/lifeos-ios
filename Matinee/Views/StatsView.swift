import SwiftUI
import Charts

/// Your viewing broken down: genres, decades, countries, and the directors and actors you keep coming back to.
struct StatsView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var year: Int?
    private var facts: FactStore { FactStore.shared }

    private var years: [Int] { Set(library.doc.entries.map(\.watchedOn.year)).sorted(by: >) }

    var body: some View {
        let s = LibraryStats(library, facts: facts, year: year)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                totals(s)
                if let f = facts.filling {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(f.done), total: Double(max(f.total, 1))).tint(Theme.accent)
                        Text("Reading \(f.done)/\(f.total) films").font(.caption).foregroundStyle(Theme.dim).fixedSize()
                    }
                    .padding(.horizontal, 20)
                }
                yearButton
                if !s.genres.isEmpty { bars("Genres", s.genres, color: Theme.accent) }
                if !s.decades.isEmpty { decades(s.decades) }
                if !s.directors.isEmpty { people("Directors", s.directors, unit: "film") }
                if !s.actors.isEmpty { people("Actors", s.actors, unit: "film") }
                if !s.countries.isEmpty { bars("Countries", s.countries, color: Theme.list) }
                if !s.takes.isEmpty || s.vsCrowd != nil { crowd(s) }
                if s.films.isEmpty {
                    EmptyState(symbol: "chart.bar", title: "No films yet", message: "Log or mark films as watched and your stats build up here.")
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 30)
        }
        .ambientBackground(Array(library.allFavorites.prefix(3)))
        .navigationTitle(year.map { "Stats · \(String($0))" } ?? "Stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if years.count > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Period", selection: $year) {
                            Text("All time").tag(Int?.none)
                            ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                        }
                    } label: { Label(year.map { String($0) } ?? "All time", systemImage: "calendar").labelStyle(.titleAndIcon) }
                }
            }
        }
        .task { await facts.fill(library.watchedFilms) }
    }

    /// You against TMDB's members: on average, and the films where you differ most.
    private func crowd(_ s: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("You vs the crowd", subtitle: s.vsCrowd.map(crowdLine) ?? "Where your score and TMDB members' differ most")
            VStack(spacing: 10) {
                ForEach(s.takes) { t in
                    NavigationLink(value: t.film) {
                        HStack(spacing: 12) {
                            PosterView(film: t.film, width: 40, corner: 4, glows: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.film.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(t.diff > 0 ? "You liked it more than most" : "Most people liked it more")
                                    .font(.caption).foregroundStyle(t.diff > 0 ? Theme.watch : Theme.heart)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                RatingValue(score: t.mine, font: .headline)
                                Text("crowd \(Score.describe(t.crowd))").font(.caption2).foregroundStyle(Theme.dim)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func crowdLine(_ d: Double) -> String {
        let stars = FilmRatingStyle.current == .stars
        let size = stars ? "\((abs(d) / 20).formatted(.number.precision(.fractionLength(1))))★" : "\(Int(abs(d).rounded())) points"
        if abs(d) < (stars ? 2 : 3) { return "You score films about the same as TMDB members" }
        return "You score films \(size) \(d > 0 ? "higher" : "lower") than TMDB members, on average"
    }

    private func totals(_ s: LibraryStats) -> some View {
        let h = s.minutes / 60
        return VStack(spacing: 14) {
            HStack(spacing: 0) {
                stat("\(s.films.count)", "films")
                stat(h >= 24 ? "\(h / 24)d \(h % 24)h" : "\(h)h", "watched")
                stat("\(s.episodes)", "episodes")
            }
            HStack(spacing: 0) {
                stat("\(s.shows)", year == nil ? "shows finished" : "shows watched")
                stat("\(library.doc.entries.filter { $0.rewatch && (year == nil || $0.watchedOn.year == year) }.count)", "rewatches")
                stat(library.averageRating.map { FilmRatingStyle.current == .stars ? Score.toStars($0).formatted(.number.precision(.fractionLength(1))) + "★" : Score.text($0) } ?? "–", "average")
            }
            if s.known < s.films.count && facts.filling == nil {
                Text("Genres and people cover \(s.known) of \(s.films.count) films so far.").font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 16)
    }

    private var yearButton: some View {
        Button { router.sheet = .yearReview(Date.now.year) } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your \(String(Date.now.year)) in review").font(.headline)
                    Text("Top films, hours watched, your busiest month and more").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
            }
            .padding(16)
            .contentShape(.rect(cornerRadius: 22))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private func bars(_ title: String, _ data: [Tally], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title)
            Chart(data) { t in
                BarMark(x: .value("Films", t.count), y: .value(title, t.name))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) { Text("\(t.count)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.dim) }
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.caption) } }
            .frame(height: CGFloat(data.count) * 30 + 10)
            .padding(.horizontal, 20)
        }
    }

    private func decades(_ data: [Tally]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Decades")
            Chart(data) { t in
                BarMark(x: .value("Decade", t.name), y: .value("Films", t.count))
                    .foregroundStyle(Theme.star.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
            .padding(.horizontal, 20)
        }
    }

    private func people(_ title: String, _ data: [Tally], unit: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title, subtitle: "Tap one to see what else of theirs you've seen")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(data) { t in
                        if let p = t.person {
                            NavigationLink(value: PersonRoute(id: p.id, name: p.name)) {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle().fill(Theme.card)
                                        Text(p.name.prefix(1)).font(.title2.bold()).foregroundStyle(Theme.dim)
                                        if p.photo != nil { RemoteImage(url: p.photo).clipShape(Circle()) }
                                    }
                                    .frame(width: 72, height: 72)
                                    Text(p.name).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                                    Text("\(t.count) \(unit)\(t.count == 1 ? "" : "s")").font(.caption2).foregroundStyle(Theme.accent)
                                }
                                .frame(width: 84)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }
}
