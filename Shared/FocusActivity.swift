import Foundation
import ActivityKit
import AppIntents

/// What the focus Live Activity shows. Shared by the app (which starts and updates it) and the widget extension (which draws it).
struct FocusAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date           // when it ends if it keeps running
        var paused: Bool
        var remaining: TimeInterval // seconds left (used while paused)
        var total: TimeInterval     // length of the session in seconds
        var done: Bool = false

        /// The moment the session would have started, for a live progress bar.
        var startDate: Date { endDate.addingTimeInterval(-total) }
        var progress: Double { total > 0 ? min(1, max(0, (total - remaining) / total)) : 0 }
    }
    var label: String
}

/// Pause or resume from the Lock Screen / Dynamic Island. Runs in the app's process.
struct ToggleFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume focus"
    static var isDiscoverable: Bool = false
    init() {}
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { FocusTimer.shared.attach(); FocusTimer.shared.togglePause() }
        #endif
        return .result()
    }
}

/// End the session from the Lock Screen / Dynamic Island; the time so far is logged.
struct EndFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End focus"
    static var isDiscoverable: Bool = false
    init() {}
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { FocusTimer.shared.attach(); FocusTimer.shared.stop() }
        #endif
        return .result()
    }
}
