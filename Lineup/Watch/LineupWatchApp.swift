import SwiftUI

/// Lineup on the wrist: the lesson on now, then the rest of the day, a page at a time.
@main
struct LineupWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(store)
        }
    }
}
