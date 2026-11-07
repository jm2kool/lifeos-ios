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
        _player = State(initialValue: PlaybackCoordinator(library: service))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .environment(passports)
                .modelContainer(Store.shared.container)
                .task {
                    library.onRefresh = { [library] snapshot in
                        Store.shared.rematch(with: snapshot)
                        library.reloadPersonalRatings()
                    }
                    library.reloadPersonalRatings()
                }
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
