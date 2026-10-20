import SwiftUI

struct DiaryView: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var filter = ""

    struct MonthGroup: Identifiable { let id: String; var entries: [LogEntry] }

    private var grouped: [MonthGroup] {
        let q = filter.lowercased().replacingOccurrences(of: "#", with: "")
        let list = library.entries.filter { q.isEmpty || $0.film.title.localizedCaseInsensitiveContains(q) || $0.tags.contains(q) }
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
                YearSummary()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                ForEach(grouped) { group in
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
                                    Button { router.sheet = .log(e.film, nil) } label: { Label("Log again", systemImage: "arrow.triangle.2.circlepath") }.tint(Theme.watch)
                                }
                                .contextMenu {
                                    Button { router.sheet = .log(e.film, e) } label: { Label("Edit entry", systemImage: "pencil") }
                                    Button { router.sheet = .log(e.film, nil) } label: { Label("Log again", systemImage: "arrow.triangle.2.circlepath") }
                                    Button(role: .destructive) { library.delete(e) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    } header: {
                        HStack {
                            Text(month).font(.headline).foregroundStyle(.white)
                            Spacer()
                            Text("\(entries.count) film\(entries.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .ambientBackground(library.entries.prefix(3).map(\.film))
        .navigationTitle("Diary")
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter by title or #tag")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Log a film", systemImage: "plus") { router.sheet = .quickLog }
            }
        }
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
                    Text(entry.film.yearText).font(.subheadline).foregroundStyle(Theme.dim)
                }
                HStack(spacing: 8) {
                    SmallStars(rating: entry.rating)
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

    var body: some View {
        let year = Date.now.year
        let thisYear = library.doc.entries.filter { $0.watchedOn.year == year }
        let rated = thisYear.compactMap(\.rating)
        VStack(alignment: .leading, spacing: 16) {
            Text("\(String(year)) SO FAR").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.dim)
            HStack(spacing: 0) {
                stat("\(thisYear.count)", "films")
                stat("\(thisYear.filter(\.liked).count)", "liked")
                stat("\(thisYear.filter(\.rewatch).count)", "rewatches")
                stat(rated.isEmpty ? "–" : (rated.reduce(0, +) / Double(rated.count)).formatted(.number.precision(.fractionLength(1))), "avg ★")
            }
            Heatmap(dates: library.doc.entries.map(\.watchedOn))
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
