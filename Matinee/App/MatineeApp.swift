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
            if p == .active {
                Task {
                    await auth.refreshIfNeeded()
                    await library.reconcileWithCloud()
                }
            }
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
    case pickFavorite(Int, shows: Bool)
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
        case .pickFavorite(let i, let shows): return "fav-\(shows ? "show" : "film")-\(i)"
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
    /// The swipe deck of random watchlist picks, opened by shaking the phone, Random pick, or double-tapping Library.
    /// nil while it's closed.
    var randomDeck: [FilmRef]?
    /// Changes with every fresh shuffle, so the deck starts again from its first card.
    var randomDeckID = UUID()
    /// Movies or shows. Each time the deck opens it starts on movies.
    var randomKind: MediaFilter = .movies
    var randomPickOpening = false
    @ObservationIgnored private var lastLibraryTap = Date.distantPast
    @ObservationIgnored private var dealTask: Task<Void, Never>?

    /// "How long have you got?" — the longest film (in minutes) a random pick may be. nil = any length.
    var randomMaxMinutes: Int?
    var randomPickSearching = false

    /// Open the deck (or reshuffle it if it's already open). `kind` picks movies or shows; otherwise
    /// it opens on movies, or on shows when the watchlist has no movies.
    func pickRandom(from library: Library, kind: MediaFilter? = nil) {
        guard !randomPickOpening else { return }
        let list = library.doc.watchlist
        guard !list.isEmpty else {
            library.toast = Toast(text: "Add films to your watchlist first", symbol: "clock")
            return
        }
        if let kind, kind != .all { randomKind = kind }
        else if randomDeck == nil { randomKind = list.contains { !$0.isShow } ? .movies : .shows }
        deal(library)
    }

    /// Shuffle the watchlist into a fresh deck of the chosen kind. With a time limit, films are checked
    /// against their runtimes (from TMDB) a handful at a time and join the deck as they pass.
    func deal(_ library: Library) {
        dealTask?.cancel()
        let pool = library.doc.watchlist.filter(randomKind.includes).shuffled()
        randomDeckID = UUID()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        guard randomKind == .movies, let limit = randomMaxMinutes else {
            randomPickSearching = false
            withAnimation(.smooth) { randomDeck = pool }
            return
        }
        withAnimation(.smooth) { randomDeck = [] }
        randomPickSearching = true
        dealTask = Task {
            for chunk in stride(from: 0, to: pool.count, by: 6).map({ Array(pool[$0..<min($0 + 6, pool.count)]) }) {
                var fits: [FilmRef] = []
                await withTaskGroup(of: (FilmRef, Int?).self) { g in
                    for f in chunk { g.addTask { (f, (try? await Catalog.detail(f.id))?.runtimeMinutes) } }
                    for await (f, m) in g { if let m, m > 0, m <= limit { fits.append(f) } }
                }
                guard !Task.isCancelled else { return }
                if randomDeck != nil { randomDeck?.append(contentsOf: fits.shuffled()) }
            }
            guard !Task.isCancelled else { return }
            randomPickSearching = false
            if randomDeck?.isEmpty == true {
                library.toast = Toast(text: "Nothing on your watchlist under \(limit / 60)h \(limit % 60)m", symbol: "clock")
            }
        }
    }

    func closeRandom() {
        dealTask?.cancel()
        randomDeck = nil
        randomPickOpening = false
        randomPickSearching = false
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
