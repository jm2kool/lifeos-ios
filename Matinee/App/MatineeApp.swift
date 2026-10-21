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

    /// A random film from the watchlist, never the one already showing.
    func pickRandom(from library: Library) {
        guard !randomPickOpening else { return }
        let list = library.doc.watchlist
        guard !list.isEmpty else {
            library.toast = Toast(text: "Add films to your watchlist first", symbol: "clock")
            return
        }
        let pick = list.filter { $0.id != randomPick?.id }.randomElement() ?? list[0]
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.smooth) { randomPick = pick }
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
