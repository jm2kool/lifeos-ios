import SwiftUI

struct DiaryView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var filter = ""

    struct MonthGroup: Identifiable { let id: String; var entries: [LogEntry] }

    /// Matches the title, the episode, a tag (type #tag for tags only) or words in your review.
    private var grouped: [MonthGroup] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let tagOnly = q.hasPrefix("#")
        let t = tagOnly ? String(q.dropFirst()) : q
        let list = library.entries.filter { e in
            if q.isEmpty { return true }
            if e.tags.contains(where: { $0.hasPrefix(t) }) { return true }
            if tagOnly { return false }
            return e.film.title.localizedCaseInsensitiveContains(t) || e.review.localizedCaseInsensitiveContains(t)
                || (e.episodeTitle?.localizedCaseInsensitiveContains(t) ?? false)
        }
        var out: [MonthGroup] = []
        for e in list {
            let key = e.watchedOn.monthYear
            if out.last?.id == key { out[out.count - 1].entries.append(e) } else { out.append(MonthGroup(id: key, entries: [e])) }
        }
        return out
    }

    var body: some View {
        List {
            if library.entries.isEmpty {
                EmptyState(symbol: "book.pages", title: "Your diary is empty",
                           message: "Log a film and it lands here with the date, your rating and your review.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                Button { router.sheet = .quickLog } label: { Label("Log your first film", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                let groups = grouped
                if filter.isEmpty {
                    YearSummary()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if groups.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No entries match", message: "Try part of a title, a word from a review, or #tag.")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(groups) { group in
                    let month = group.id, entries = group.entries
                    Section {
                        ForEach(entries) { e in
                            NavigationLink(value: e.film) { DiaryRow(entry: e) }
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Theme.line)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { library.delete(e) } label: { Label("Delete", systemImage: "trash") }
                                    Button { router.sheet = .log(e.film, e) } label: { Label("Edit", systemImage: "pencil") }.tint(Theme.list)
                                }
                                .swipeActions(edge: .leading) {
                                    Button { router.sheet = e.logAgainRoute } label: { Label("Log again", systemImage: "arrow.triangle.2.circlepath") }.tint(Theme.watch)
                                }
                                .contextMenu {
                                    Button { router.sheet = .log(e.film, e) } label: { Label("Edit entry", systemImage: "pencil") }
                                    Button { router.sheet = e.logAgainRoute } label: { Label("Log again", systemImage: "arrow.triangle.2.circlepath") }
                                    Button(role: .destructive) { library.delete(e) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    } header: {
                        HStack {
                            Text(month).font(.headline).foregroundStyle(.white)
                            Spacer()
                            Text(Self.count(entries)).font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .ambientBackground(library.entries.prefix(3).map(\.film))
        .navigationTitle("Diary")
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Title, #tag or a word from a review")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Scan a ticket", systemImage: "ticket") { router.sheet = .scanTicket }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Log a film", systemImage: "plus") { router.sheet = .quickLog }
            }
        }
    }
}

extension DiaryView {
    /// "3 films", or "5 entries" when episodes are in the mix.
    static func count(_ entries: [LogEntry]) -> String {
        let n = entries.count
        if entries.allSatisfy({ $0.season == nil && !$0.film.isShow }) { return n == 1 ? "1 film" : "\(n) films" }
        return n == 1 ? "1 entry" : "\(n) entries"
    }
}

struct DiaryRow: View {
    let entry: LogEntry
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(entry.watchedOn.dayNumber).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(entry.watchedOn.weekdayShort.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Theme.dim)
            }
            .frame(width: 40)
            PosterView(film: entry.film, width: 46, corner: 5)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.film.title).font(.body.weight(.semibold)).lineLimit(1)
                    if let l = entry.episodeLabel { Text(l).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent) }
                    else { Text(entry.film.yearText).font(.subheadline).foregroundStyle(Theme.dim) }
                }
                if let t = entry.episodeTitle { Text(t).font(.caption).foregroundStyle(Theme.dim).lineLimit(1) }
                HStack(spacing: 8) {
                    SmallRating(rating: entry.rating)
                    if entry.liked { Image(systemName: "heart.fill").foregroundStyle(Theme.heart) }
                    if entry.rewatch { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.watch) }
                    if !entry.review.isEmpty { Image(systemName: "text.alignleft").foregroundStyle(Theme.dim) }
                    ForEach(entry.tags.prefix(2), id: \.self) { Text("#\($0)").foregroundStyle(Theme.accent) }
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// This year at a glance, with a GitHub-style heatmap of film nights.
struct YearSummary: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @AppStorage(FilmRatingStyle.key) private var filmStyle: FilmRatingStyle = .score

    var body: some View {
        let year = Date.now.year
        let thisYear = library.doc.entries.filter { $0.watchedOn.year == year }
        let films = thisYear.filter { !$0.film.isShow }
        let rated = films.compactMap(\.rating)
        // Episodes count when you ticked them off, diary entry or not.
        let episodes = (library.doc.shows ?? [:]).values.reduce(0) { $0 + $1.seen.values.filter { $0.year == year }.count }
        VStack(alignment: .leading, spacing: 16) {
            Text("\(String(year)) SO FAR").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.dim)
            HStack(spacing: 0) {
                stat("\(films.count)", "films")
                stat("\(episodes)", "episodes")
                stat("\(thisYear.filter(\.liked).count)", "liked")
                if filmStyle == .stars {
                    stat(rated.isEmpty ? "–" : Score.toStars(rated.reduce(0, +) / Double(rated.count)).formatted(.number.precision(.fractionLength(1))), "avg ★")
                } else {
                    stat(rated.isEmpty ? "–" : String(Int((rated.reduce(0, +) / Double(rated.count)).rounded())), "avg score")
                }
            }
            GoalProgress(done: films.count, goal: library.doc.yearGoal)
            Heatmap(dates: library.doc.entries.map(\.watchedOn))
            HStack(spacing: 8) {
                Button { router.sheet = .yearReview(year) } label: {
                    Label("Year in review", systemImage: "sparkles.rectangle.stack").frame(maxWidth: .infinity)
                }
                Button { router.diaryPath.append(StatsRoute()) } label: { Label("All stats", systemImage: "chart.bar").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.glass).controlSize(.small)
            .font(.footnote.weight(.semibold))
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 26, weight: .bold, design: .rounded)).contentTransition(.numericText())
            Text(l).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Your film goal for the year: how far along you are, and whether you're ahead of where you'd need to be.
struct GoalProgress: View {
    let done: Int
    let goal: Int?
    @Environment(Library.self) private var library
    static let choices = [12, 24, 36, 52, 75, 100, 150, 200, 365]

    var body: some View {
        Menu {
            Section("Films to watch in \(String(Date.now.year))") {
                ForEach(Self.choices, id: \.self) { n in
                    Button { library.setYearGoal(n) } label: {
                        if n == goal { Label("\(n) films", systemImage: "checkmark") } else { Text("\(n) films") }
                    }
                }
            }
            if goal != nil { Button("Remove goal", systemImage: "xmark", role: .destructive) { library.setYearGoal(nil) } }
        } label: {
            if let goal {
                HStack(spacing: 12) {
                    ProgressRing(progress: Double(done) / Double(max(goal, 1)), tint: done >= goal ? Theme.watch : Theme.accent)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(done >= goal ? "Goal reached · \(done) of \(goal) films" : "\(done) of \(goal) films").font(.subheadline.weight(.semibold))
                        Text(pace(goal)).font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.dim)
                }
                .foregroundStyle(.white)
            } else {
                Label("Set a goal for \(String(Date.now.year))", systemImage: "target")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
        .buttonStyle(.plain)
    }

    /// Where you'd be if you spread the goal evenly over the year.
    private func pace(_ goal: Int) -> String {
        guard done < goal else { return "\(done - goal) more than you planned" }
        let cal = Calendar.current
        let day = cal.ordinality(of: .day, in: .year, for: .now) ?? 1
        let days = cal.range(of: .day, in: .year, for: .now)?.count ?? 365
        let expected = Int((Double(goal) * Double(day) / Double(days)).rounded())
        let diff = done - expected
        if diff == 0 { return "Right on pace" }
        return diff > 0 ? "\(diff) ahead of pace" : "\(-diff) behind pace · \(goal - done) to go"
    }
}

struct Heatmap: View {
    let dates: [Date]
    var weeks = 26

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var counts: [Date: Int] = [:]
        for d in dates { counts[cal.startOfDay(for: d), default: 0] += 1 }
        let weekdayToday = cal.component(.weekday, from: today) - 1
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekdayToday, to: today)!
        return Canvas { ctx, size in
            let gap: CGFloat = 3
            let cell = min((size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks), (size.height - gap * 6) / 7)
            for w in 0..<weeks {
                for d in 0..<7 {
                    guard let day = cal.date(byAdding: .day, value: w * 7 + d, to: start), day <= today else { continue }
                    let n = counts[day] ?? 0
                    let rect = CGRect(x: CGFloat(w) * (cell + gap), y: CGFloat(d) * (cell + gap), width: cell, height: cell)
                    let color: Color = n == 0 ? .white.opacity(0.07) : n == 1 ? Theme.accent.opacity(0.55) : Theme.accent
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2.5), with: .color(color))
                }
            }
        }
        .frame(height: 7 * 11 + 6 * 3)
        .accessibilityLabel("Films watched over the last six months")
    }
}

extension LogEntry {
    /// A fresh entry for the same thing: the film or show, or the same episode or season.
    var logAgainRoute: SheetRoute {
        season == nil ? .log(film, nil) : .logEpisode(LogEntry(film: film, season: season, episode: episode, episodeTitle: episodeTitle))
    }
}
