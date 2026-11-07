import SwiftUI

@main
struct LINERApp: App {
    @State private var library: LibraryService
    @State private var player: PlaybackCoordinator

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
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
