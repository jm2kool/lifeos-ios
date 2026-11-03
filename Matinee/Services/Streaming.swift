import Foundation
import SwiftUI
import UserNotifications

/// Your streaming services (Settings → My services) and which watchlist titles you can watch on them right now.
/// Data from JustWatch via TMDB, for the country set in Settings → Film data.
@Observable @MainActor
final class Availability {
    static let shared = Availability()

    /// Film id → the services of yours that carry it (streaming, free or with ads).
    private(set) var onServices: [String: [WatchProvider]] = [:]
    /// While checking the watchlist: how many done out of how many.
    private(set) var checking: (done: Int, total: Int)?
    @ObservationIgnored private var signature = ""
    @ObservationIgnored private var lastRun = Date.distantPast

    static let alertsKey = "notifyStreaming"
    static var alertsOn: Bool { UserDefaults.standard.object(forKey: alertsKey) as? Bool ?? true }
    private static let seenKey = "streamingSeen", seenForKey = "streamingSeenFor"

    func services(for id: String) -> [WatchProvider] { onServices[id] ?? [] }

    /// Check your watchlist (the newest 150) against your services. Cheap to call often: it only runs again when
    /// the watchlist, your services or your country change, or every few hours to catch new arrivals.
    func refresh(_ library: Library, force: Bool = false) async {
        let services = Set(library.services)
        let films = Array(library.doc.watchlist.prefix(150))
        let key = "\(Catalog.watchRegion)|\(services.sorted())"
        let sig = key + "|" + films.map(\.id).joined(separator: ",")
        guard checking == nil, force || sig != signature || Date.now.timeIntervalSince(lastRun) > 6 * 3600 else { return }
        if !signature.hasPrefix(key + "|") { onServices = [:] }   // new services or country: start afresh
        signature = sig
        lastRun = .now
        guard !services.isEmpty, Catalog.hasToken, !films.isEmpty else { onServices = [:]; return }
        checking = (0, films.count)
        defer { checking = nil }
        for start in stride(from: 0, to: films.count, by: 6) {
            let chunk = Array(films[start..<min(start + 6, films.count)])
            await withTaskGroup(of: (String, [WatchProvider]).self) { g in
                for f in chunk { g.addTask { (f.id, await Catalog.providers(f.id)?.onServices(services) ?? []) } }
                for await (id, list) in g { onServices[id] = list.isEmpty ? nil : list }
            }
            checking = (min(start + 6, films.count), films.count)
        }
        // Titles that left the watchlist don't count any more.
        let ids = Set(films.map(\.id))
        onServices = onServices.filter { ids.contains($0.key) }
        await announceArrivals(films, key: key)
    }

    /// "Now streaming": a notification when a watchlist title turns up on one of your services. The first check
    /// (and any check after you change services or country) only takes note, so nothing old is announced.
    private func announceArrivals(_ films: [FilmRef], key: String) async {
        let d = UserDefaults.standard
        let now = Set(onServices.keys)
        let before = d.string(forKey: Self.seenForKey) == key ? d.stringArray(forKey: Self.seenKey).map { Set($0) } : nil
        d.set(Array(now), forKey: Self.seenKey)
        d.set(key, forKey: Self.seenForKey)
        guard let before, Self.alertsOn, await Reminders.authorized else { return }
        for f in films.filter({ now.contains($0.id) && !before.contains($0.id) }).prefix(3) {
            let c = UNMutableNotificationContent()
            let names = services(for: f.id).prefix(2).map(\.name).joined(separator: " and ")
            c.title = "Now streaming: \(f.title)"
            c.body = "From your watchlist — it's on \(names.isEmpty ? "one of your services" : names)."
            c.sound = .default
            c.threadIdentifier = "streaming"
            c.userInfo = ["url": Reminders.filmURL(f).absoluteString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "stream-\(f.id)", content: c, trigger: trigger))
        }
    }
}

/// Settings → My services: tick the streaming services you pay for.
struct ServicesPicker: View {
    @Environment(Library.self) private var library
    @AppStorage(Catalog.regionKey) private var chosenRegion = ""
    @State private var all: [WatchProvider] = []
    @State private var loaded = false
    @State private var query = ""

    private var mine: Set<Int> { Set(library.services) }
    private var shown: [WatchProvider] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
        return list.filter { mine.contains($0.id) } + list.filter { !mine.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if all.isEmpty {
                    Text(Catalog.hasToken ? "Couldn't load the services for \(Catalog.regionName(Catalog.watchRegion)). Check your connection."
                                          : "Connect TMDB first, in Settings → Film data.")
                        .font(.subheadline).foregroundStyle(Theme.dim)
                }
                ForEach(shown) { p in
                    let on = mine.contains(p.id)
                    Button { toggle(p.id) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: p.logo).frame(width: 36, height: 36).clipShape(.rect(cornerRadius: 8))
                            Text(p.name).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(on ? Theme.watch : Theme.dim)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            } footer: {
                Text("Services in \(Catalog.regionName(Catalog.watchRegion)). Your watchlist can then show what you can watch tonight at no extra cost, and Matinee tells you when a watchlist title arrives on one of them. Availability from JustWatch.")
            }
        }
        .oledBackground()
        .navigationTitle("My services")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Find a service")
        .task(id: chosenRegion) {
            loaded = false
            all = await Catalog.allServices()
            loaded = true
        }
    }

    private func toggle(_ id: Int) {
        var ids = library.services
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
        library.setServices(ids)
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// Home: watchlist titles you can watch right now on a service you already pay for.
struct ReadyToStreamSection: View {
    var media: MediaFilter = .all
    @Environment(Library.self) private var library
    private var availability: Availability { Availability.shared }

    var body: some View {
        let films = library.doc.watchlist.filter { media.includes($0) && !availability.services(for: $0.id).isEmpty }
        Group {
            if !library.services.isEmpty && !films.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Ready to stream", subtitle: "From your watchlist, on your services") {
                        NavigationLink("See all", value: CollectionRoute.onServices)
                    }
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(films.prefix(20)) { f in
                                NavigationLink(value: f) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        PosterView(film: f, width: 112)
                                            .overlay(alignment: .bottomTrailing) { ServiceBadge(provider: availability.services(for: f.id).first).padding(6) }
                                        Text(availability.services(for: f.id).map(\.name).prefix(2).joined(separator: " · "))
                                            .font(.caption2.weight(.semibold)).foregroundStyle(Theme.dim).lineLimit(1)
                                    }
                                    .frame(width: 112, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .filmContextMenu(f)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
        }
        .task(id: library.services) { await availability.refresh(library) }
    }
}

/// A service's logo, small and rounded, for the corner of a poster.
struct ServiceBadge: View {
    let provider: WatchProvider?
    var size: CGFloat = 26
    var body: some View {
        if let p = provider {
            RemoteImage(url: p.logo)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size * 0.24))
                .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(.black.opacity(0.6), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.5), radius: 4)
                .accessibilityLabel("On \(p.name)")
        }
    }
}
