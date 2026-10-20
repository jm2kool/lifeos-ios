import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(Auth.self) private var auth
    @Environment(Router.self) private var router
    @Environment(Watching.self) private var watching
    @Environment(Taste.self) private var taste
    @State private var showSignIn = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Films", systemImage: "film.stack", value: AppTab.films) {
                NavigationStack(path: $router.filmsPath) { HomeView().destinations() }
            }
            Tab("Diary", systemImage: "book.pages", value: AppTab.diary) {
                NavigationStack(path: $router.diaryPath) { DiaryView().destinations() }
            }
            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack(path: $router.libraryPath) { LibraryView().destinations() }
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                NavigationStack(path: $router.profilePath) { ProfileView().destinations() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $router.searchPath) { SearchView().destinations() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: $router.sheet) { route in
            SheetHost(route: route)
                .environment(library).environment(auth).environment(router).environment(watching).environment(taste)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView().environment(library).environment(auth).environment(router).environment(watching).environment(taste).preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: Bindable(taste).showQuiz) {
            TasteQuizView().environment(library).environment(taste).environment(router)
        }
        .onChange(of: showSignIn) { _, open in
            // Right after sign-in (or choosing no account), offer the swipe quiz once.
            if !open && taste.shouldOffer {
                Task { try? await Task.sleep(for: .seconds(0.6)); taste.showQuiz = true }
            }
        }
        .overlay(alignment: .bottom) {
            // Intermission mode: a "now watching" bar floats above the tab bar while a film is in progress.
            if let s = watching.current {
                NowWatchingBar(session: s)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: watching.current?.id)
        .overlay(alignment: .top) {
            if let t = library.toast {
                ToastView(toast: t) { library.undo() }
                    .padding(.top, 4)
                    .task(id: t.id) {
                        try? await Task.sleep(for: .seconds(t.undo ? 4 : 2.2))
                        withAnimation(.smooth) { if library.toast?.id == t.id { library.toast = nil } }
                    }
            }
        }
        .animation(.smooth(duration: 0.35), value: library.toast)
        .onAppear {
            showSignIn = auth.needsOnboarding
            if !showSignIn && taste.shouldOffer { taste.showQuiz = true }
        }
        .onChange(of: auth.needsOnboarding) { _, v in showSignIn = v }
        .onChange(of: auth.session?.userID) { _, id in
            guard id != nil else { return }
            library.adoptAccountProfile()
            Task { await library.reconcileWithCloud() }
        }
        .task { await previewMode() }
    }

    /// Hooks used by the CI simulator run to capture screenshots.
    private func previewMode() async {
        let env = ProcessInfo.processInfo.environment
        if let t = env["MATINEE_TAB"], let tab = AppTab(rawValue: t) { router.tab = tab }
        if let id = env["MATINEE_FILM"] {
            try? await Task.sleep(for: .seconds(1))
            let f = library.watchedFilms.first { $0.id == id } ?? FilmRef(id: id, title: "")
            router.open(f)
        }
        if env["MATINEE_LOG"] != nil, let f = library.watchedFilms.first {
            try? await Task.sleep(for: .seconds(1.5))
            router.sheet = .log(f, nil)
        }
        if env["MATINEE_LIST"] != nil, let l = library.doc.lists.first {
            router.tab = .library
            try? await Task.sleep(for: .seconds(1))
            router.libraryPath.append(l)
        }
        if env["MATINEE_TOUR"] != nil {
            for tab in [AppTab.films, .diary, .library, .profile, .search] {
                router.tab = tab
                try? await Task.sleep(for: .seconds(3.5))
            }
            router.tab = .films
        }
    }
}

extension View {
    func destinations() -> some View {
        navigationDestination(for: FilmRef.self) { FilmView(film: $0) }
            .navigationDestination(for: FilmList.self) { ListDetailView(listID: $0.id) }
            .navigationDestination(for: GenreRoute.self) { GenreView(genre: $0.name) }
            .navigationDestination(for: CollectionRoute.self) { CollectionView(route: $0) }
    }
}

struct GenreRoute: Hashable { let name: String }

enum CollectionRoute: Hashable {
    case shelf(HomeShelf), watched, liked, watchlist, tag(String), rated(Double), forYou
}

struct SheetHost: View {
    let route: SheetRoute
    var body: some View {
        switch route {
        case .log(let f, let e): LogSheet(film: f, existing: e)
        case .addToList(let f): AddToListSheet(film: f)
        case .newList(let f): ListEditor(seed: f)
        case .editList(let l): ListEditor(editing: l)
        case .pickFavorite(let slot): FavoritePicker(slot: slot)
        case .editProfile: ProfileEditor()
        case .settings: SettingsView()
        case .signIn: SignInView(asSheet: true)
        case .quickLog: QuickLogSheet()
        case .intermission(let id): IntermissionSheet(sessionID: id)
        }
    }
}
