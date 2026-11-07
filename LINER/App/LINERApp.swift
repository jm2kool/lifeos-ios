import SwiftUI

@main
struct LINERApp: App {
    @State private var library: LibraryService
    @State private var player: PlaybackCoordinator
    @State private var passports = PassportPresenter()

    init() {
        let service = LibraryService()
        LibraryService.current = service
        _library = State(initialValue: service)
        let player = PlaybackCoordinator(library: service)
        _player = State(initialValue: player)
        SnapshotService.registerBackgroundTask()
        AppWiring.connect(library: service, player: player)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .environment(passports)
                .modelContainer(Store.shared.container)
                .task { library.reloadPersonalRatings() }
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
