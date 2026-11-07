import SwiftUI

@main
struct LINERApp: App {
    @State private var library: LibraryService

    init() {
        let service = LibraryService()
        LibraryService.current = service
        _library = State(initialValue: service)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
