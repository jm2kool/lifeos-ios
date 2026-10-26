import SwiftUI
import UIKit

@main
struct MatineeApp: App {
    @State private var library = Library.shared
    @State private var auth = Auth.shared
    @State private var router = Router()
    @State private var watching = Watching.shared
    @State private var taste = Taste.shared
    @Environment(\.scenePhase) private var phase

    init() {
        let env = ProcessInfo.processInfo.environment
        if env["MATINEE_PREVIEW"] != nil {
            Library.shared.seedDemo()
            Watching.shared.seedDemo(FilmRef(id: "tmdb-496243", title: "Parasite", year: 2019))
            if env["MATINEE_TASTE"] == nil { Taste.shared.seedDemo() }
            if env["MATINEE_SIGNIN"] == nil { Auth.shared.continueAsGuest() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(auth)
                .environment(router)
                .environment(watching)
                .environment(taste)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .background(Color.black)
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await auth.refreshIfNeeded() } }
        }
    }
}

enum AppTab: String, Hashable, CaseIterable {
    case films, diary, library, profile, search
}

enum SheetRoute: Identifiable, Equatable {
    case log(FilmRef, LogEntry?)
    case addToList(FilmRef)
    case newList(FilmRef?)
    case editList(FilmList)
    case pickFavorite(Int)
    case editProfile
    case settings
    case signIn
    case quickLog
    case intermission(UUID)
    case logEpisode(LogEntry)                  // a new diary entry for an episode or season of a show
    case episode(FilmRef, Episode)
    case wrap(FilmRef, Int, Bool)               // show, season, and whether it finished the show

    var id: String {
        switch self {
        case .log(let f, let e): return "log-\(f.id)-\(e?.id.uuidString ?? "")"
        case .addToList(let f): return "add-\(f.id)"
        case .newList(let f): return "new-\(f?.id ?? "")"
        case .editList(let l): return "edit-\(l.id)"
        case .pickFavorite(let i): return "fav-\(i)"
        case .editProfile: return "profile"
        case .settings: return "settings"
        case .signIn: return "signin"
        case .quickLog: return "quicklog"
        case .intermission(let id): return "intermission-\(id)"
        case .logEpisode(let e): return "logep-\(e.film.id)-\(e.episodeLabel ?? "")"
        case .episode(let f, let e): return "ep-\(f.id)-\(e.id)"
        case .wrap(let f, let s, let series): return "wrap-\(f.id)-\(s)-\(series)"
        }
    }
}

@Observable @MainActor
final class Router {
    var tab: AppTab = .films
    var sheet: SheetRoute?
    var filmsPath = NavigationPath()
    var diaryPath = NavigationPath()
    var libraryPath = NavigationPath()
    var profilePath = NavigationPath()
    var searchPath = NavigationPath()
    /// The film card shown by shaking the phone, Random pick, or double-tapping Library.
    var randomPick: FilmRef?
    var randomPickOpening = false
    @ObservationIgnored private var lastLibraryTap = Date.distantPast

    /// "How long have you got?" — the longest film (in minutes) a random pick may be. nil = any length.
    var randomMaxMinutes: Int?
    var randomPickSearching = false

    /// A random film from the watchlist, never the one already showing, that fits the time you have.
    func pickRandom(from library: Library) {
        guard !randomPickOpening else { return }
        let list = library.doc.watchlist
        guard !list.isEmpty else {
            library.toast = Toast(text: "Add films to your watchlist first", symbol: "clock")
            return
        }
        let pool = list.filter { $0.id != randomPick?.id }
        guard let limit = randomMaxMinutes else {
            show(pool.randomElement() ?? list[0])
            return
        }
        // Check runtimes (from TMDB) a handful at a time until one fits.
        randomPickSearching = true
        Task {
            defer { randomPickSearching = false }
            let shuffled = pool.shuffled()
            for chunk in stride(from: 0, to: shuffled.count, by: 6).map({ Array(shuffled[$0..<min($0 + 6, shuffled.count)]) }) {
                var fits: [FilmRef] = []
                await withTaskGroup(of: (FilmRef, Int?).self) { g in
                    for f in chunk { g.addTask { (f, (try? await Catalog.detail(f.id))?.runtimeMinutes) } }
                    for await (f, m) in g { if let m, m > 0, m <= limit { fits.append(f) } }
                }
                if let f = fits.randomElement() { show(f); return }
            }
            library.toast = Toast(text: "Nothing on your watchlist under \(limit / 60)h \(limit % 60)m", symbol: "clock")
        }
    }

    private func show(_ f: FilmRef) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.smooth) { randomPick = f }
    }

    /// Tab selection that notices a quick double tap on Library.
    func select(_ t: AppTab, library: Library) {
        if t == .library {
            let now = Date()
            if now.timeIntervalSince(lastLibraryTap) < 0.45 {
                lastLibraryTap = .distantPast
                pickRandom(from: library)
            } else {
                lastLibraryTap = now
            }
        }
        tab = t
    }

    func open(_ f: FilmRef) {
        switch tab {
        case .films: filmsPath.append(f)
        case .diary: diaryPath.append(f)
        case .library: libraryPath.append(f)
        case .profile: profilePath.append(f)
        case .search: searchPath.append(f)
        }
    }
}
