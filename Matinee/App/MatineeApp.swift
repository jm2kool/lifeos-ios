import SwiftUI

@main
struct MatineeApp: App {
    @State private var library = Library.shared
    @State private var auth = Auth.shared
    @State private var router = Router()
    @Environment(\.scenePhase) private var phase

    init() {
        let env = ProcessInfo.processInfo.environment
        if env["MATINEE_PREVIEW"] != nil {
            Library.shared.seedDemo()
            if env["MATINEE_SIGNIN"] == nil { Auth.shared.continueAsGuest() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(auth)
                .environment(router)
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
