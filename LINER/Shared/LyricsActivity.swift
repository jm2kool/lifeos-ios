import ActivityKit
import Foundation

/// The live lyrics Live Activity (shared by the app and the widget extension). The song is part of the state,
/// so one activity carries on from song to song instead of a new one popping up each time.
struct LyricsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        /// The line being sung (-1 before the first, or when there are no synced lyrics), so each new line can
        /// slide up into place.
        var index: Int
        var previous: String
        var current: String
        var next: String
        var isPlaying: Bool
    }
}
