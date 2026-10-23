import WidgetKit
import SwiftUI
import ActivityKit
import UIKit

@main
struct MatineeWidgets: WidgetBundle {
    var body: some Widget {
        RandomWatchlistWidget()
        WatchLiveActivity()
    }
}

private let accent = Color(red: 1.0, green: 0.42, blue: 0.24)

// MARK: - Random watchlist film

struct PickEntry: TimelineEntry {
    let date: Date
    let film: SharedStore.Film?
    let poster: UIImage?
    let count: Int
}

struct PickProvider: TimelineProvider {
    func placeholder(in context: Context) -> PickEntry {
        PickEntry(date: .now, film: SharedStore.Film(id: "", title: "Tonight's film", year: nil, poster: nil), poster: nil, count: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (PickEntry) -> Void) {
        Task { completion(await entries(count: 1).first ?? placeholder(in: context)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PickEntry>) -> Void) {
        // A fresh pick every hour for the next few hours.
        Task { completion(Timeline(entries: await entries(count: 4), policy: .atEnd)) }
    }

    /// The shared folder when iOS allows it; otherwise the copy the app keeps on your account server,
    /// remembered here for when you're offline.
    private func watchlist() async -> [SharedStore.Film] {
        let local = SharedStore.loadWatchlist()
        if !local.isEmpty { return local }
        let cacheKey = "remoteWatchlist"
        if let server = SharedStore.bakedServer(), let device = await SharedStore.deviceKey,
           let remote = await SharedStore.fetchRemote(device: device, server: server) {
            if let data = try? JSONEncoder().encode(remote) { UserDefaults.standard.set(data, forKey: cacheKey) }
            return remote
        }
        if let data = UserDefaults.standard.data(forKey: cacheKey), let cached = try? JSONDecoder().decode([SharedStore.Film].self, from: data) {
            return cached
        }
        return []
    }

    private func entries(count: Int) async -> [PickEntry] {
        let list = await watchlist()
        guard !list.isEmpty else { return [PickEntry(date: .now, film: nil, poster: nil, count: 0)] }
        var picks = Array(list.shuffled().prefix(count))
        while picks.count < count { picks.append(list.randomElement()!) }
        var out: [PickEntry] = []
        for (i, f) in picks.enumerated() {
            out.append(PickEntry(date: Calendar.current.date(byAdding: .hour, value: i, to: .now)!, film: f,
                                 poster: await load(f.poster), count: list.count))
        }
        return out
    }

    /// Widgets can't load images while drawing, so fetch a small poster up front.
    private func load(_ url: URL?) async -> UIImage? {
        guard var s = url?.absoluteString else { return nil }
        s = s.replacingOccurrences(of: "/original/", with: "/w342/").replacingOccurrences(of: "/w500/", with: "/w342/")
        guard let u = URL(string: s), let (data, _) = try? await URLSession.shared.data(from: u), let img = UIImage(data: data) else { return nil }
        return img.preparingThumbnail(of: CGSize(width: 342, height: 513)) ?? img
    }
}

struct RandomWatchlistWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: PickProvider()) { entry in
            PickWidgetView(entry: entry)
        }
        .configurationDisplayName("Watchlist pick")
        .description("A random film from your watchlist. Tap it to open the film.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct PickWidgetView: View {
    let entry: PickEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let f = entry.film {
                switch family {
                case .accessoryRectangular: lockScreen(f)
                case .systemMedium: medium(f)
                default: poster(f)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "clock").font(.title2).foregroundStyle(accent)
                    Text("Add films to your watchlist in Matinee").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                    Text("Already have some? Open Matinee → Settings → Widget.").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding()
                .containerBackground(for: .widget) { Color.black }
            }
        }
        .widgetURL(entry.film.map(SharedStore.filmURL))
    }

    private var label: some View {
        Text("TONIGHT'S PICK").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(accent)
    }

    private func posterImage() -> some View {
        Group {
            if let img = entry.poster { Image(uiImage: img).resizable().aspectRatio(contentMode: .fill) }
            else { LinearGradient(colors: [accent.opacity(0.6), .black], startPoint: .top, endPoint: .bottom) }
        }
    }

    private func poster(_ f: SharedStore.Film) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer()
            label
            Text(f.title).font(family == .systemLarge ? .title2.weight(.bold) : .headline.weight(.bold)).lineLimit(2)
            if let y = f.year { Text(String(y)).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75)) }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(14)
        .containerBackground(for: .widget) {
            ZStack {
                Color.black
                posterImage()
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.9), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func medium(_ f: SharedStore.Film) -> some View {
        HStack(spacing: 14) {
            posterImage()
                .frame(width: 92, height: 138)
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                label
                Text(f.title).font(.title3.weight(.bold)).lineLimit(3)
                if let y = f.year { Text(String(y)).font(.subheadline).foregroundStyle(.white.opacity(0.7)) }
                Spacer()
                Text("1 of \(entry.count) on your watchlist").font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .containerBackground(for: .widget) {
            ZStack {
                Color.black
                posterImage().blur(radius: 40).opacity(0.55)
            }
        }
    }

    private func lockScreen(_ f: SharedStore.Film) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Tonight's pick").font(.caption2.weight(.semibold)).widgetAccentable()
            Text(f.title).font(.headline).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Now watching (Live Activity + Dynamic Island)

struct WatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WatchActivityAttributes.self) { context in
            LockScreenWatching(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(url(context.attributes))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.running ? "Watching" : "Intermission", systemImage: s.running ? "play.fill" : "pause.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(accent).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: s).font(.title3.weight(.bold).monospacedDigit()).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        FilmProgress(state: s)
                        if !s.running, let n = s.note, !n.isEmpty {
                            Text("\(s.mood ?? "") “\(n)”").font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: s.running ? "film.fill" : "pause.fill").foregroundStyle(accent)
            } compactTrailing: {
                ElapsedText(state: s).font(.caption.weight(.semibold).monospacedDigit()).frame(maxWidth: 56)
            } minimal: {
                Image(systemName: s.running ? "film.fill" : "pause.fill").foregroundStyle(accent)
            }
            .widgetURL(url(context.attributes))
            .keylineTint(accent)
        }
    }

    private func url(_ a: WatchActivityAttributes) -> URL {
        SharedStore.filmURL(SharedStore.Film(id: a.filmID, title: a.title, year: a.year, poster: nil))
    }
}

/// Counts up live while the film is running; frozen at the stop point on intermission.
struct ElapsedText: View {
    let state: WatchActivityAttributes.ContentState
    var body: some View {
        if state.running {
            Text(timerInterval: state.virtualStart...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        } else {
            Text(clock(state.banked))
        }
    }
}

struct FilmProgress: View {
    let state: WatchActivityAttributes.ContentState
    var body: some View {
        if let r = state.runtime, r > 0 {
            if state.running {
                ProgressView(timerInterval: state.virtualStart...state.virtualStart.addingTimeInterval(r), countsDown: false) {
                    EmptyView()
                } currentValueLabel: { EmptyView() }
                .tint(accent)
            } else {
                ProgressView(value: min(1, state.banked / r)).tint(accent)
            }
        }
    }
}

struct LockScreenWatching: View {
    let context: ActivityViewContext<WatchActivityAttributes>
    var body: some View {
        let s = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.running ? "NOW WATCHING" : "INTERMISSION").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(accent)
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    ElapsedText(state: s).font(.title2.weight(.bold).monospacedDigit())
                    if let r = s.runtime { Text("of \(clock(r))").font(.caption).foregroundStyle(.white.opacity(0.6)) }
                }
            }
            FilmProgress(state: s)
            if !s.running, let n = s.note, !n.isEmpty {
                Text("\(s.mood ?? "") “\(n)”").font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private func clock(_ t: TimeInterval) -> String {
    let m = Int(t / 60), h = m / 60
    return h > 0 ? "\(h)h \(m % 60)m" : "\(m)m"
}
