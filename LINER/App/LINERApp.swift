import SwiftUI

@main
struct LINERApp: App {
    @State private var library: LibraryService
    @State private var player: PlaybackCoordinator
    @State private var passports = PassportPresenter()
    @State private var splash = Demo.showsSplash

    init() {
        Demo.prepare()
        let service = Demo.isOn ? LibraryService(preview: DemoLibrary.snapshot) : LibraryService()
        LibraryService.current = service
        _library = State(initialValue: service)
        let player = PlaybackCoordinator(library: service)
        _player = State(initialValue: player)
        SnapshotService.registerBackgroundTask()
        AppWiring.connect(library: service, player: player)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(library)
                    .environment(player)
                    .environment(passports)
                    .modelContainer(Store.shared.container)
                    .task { library.reloadPersonalRatings(); CoverOverrides.shared.load() }
                    .task { await Demo.run(player: player) }
                if splash {
                    SplashView { withAnimation(.easeOut(duration: 0.3)) { splash = false } }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(.dark)
            .tint(.white)
            .toggleStyle(LinerToggleStyle())
        }
    }
}
