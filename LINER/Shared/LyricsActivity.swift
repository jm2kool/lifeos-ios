import ActivityKit
import Foundation

/// The live lyrics Live Activity (shared by the app and the widget extension).
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var previous: String
        var current: String
        var next: String
        var isPlaying: Bool
    }
    var title: String
    var artist: String
}
