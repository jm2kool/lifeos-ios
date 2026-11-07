import SwiftUI

/// The glass tab bar (SPEC §8): Home, Library, Recaps, My LINER., Search — or the permission screen.
struct RootView: View {
    enum TabID: String { case home, library, recaps, stats, search }

    @Environment(LibraryService.self) private var library
    @Environment(\.scenePhase) private var phase
    @AppStorage("root.tab") private var tab: TabID = .home

    var body: some View {
        Group {
            if library.isAuthorized {
                tabs
            } else {
                PermissionView()
            }
        }
        .task { if library.isAuthorized && !library.hasLoaded { await library.refresh() } }
        .onChange(of: phase) { _, now in
            if now == .active && library.hasLoaded { Task { await library.refresh() } }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: TabID.home) { HomeView() }
            Tab("Library", systemImage: "square.stack", value: TabID.library) { LibraryView() }
            Tab("Recaps", systemImage: "calendar", value: TabID.recaps) { RecapsView() }
            Tab("My \(AppBrand.name)", systemImage: "chart.bar.xaxis", value: TabID.stats) { MyStatsView() }
            Tab(value: TabID.search, role: .search) { SearchView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview { RootView().environment(PreviewData.library).preferredColorScheme(.dark) }
