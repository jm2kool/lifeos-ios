import SwiftUI

/// Phase 0 build: a spike lab that tests the risky APIs before the real app is built.
@main
struct LINERApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeHomeView()
                .preferredColorScheme(.dark)
        }
    }
}
