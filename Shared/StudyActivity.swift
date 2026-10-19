import Foundation
import ActivityKit

/// The study block Live Activity: shown before a block ("Reflection of Light starts in 10 min"), during it (topic, time left)
/// and at the break after it. Shared by the app (which starts and updates it) and the widget extension (which draws it).
struct StudyBlockAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable { case upcoming, during, rest, ended }
    struct ContentState: Codable, Hashable {
        var phase: Phase
        var title: String           // the block's topic (during a break: the next block's)
        var start: Date             // when the block starts (during a break: when the next one starts)
        var end: Date               // when the block ends
        var note: String = ""       // e.g. "Break" or "Next: Waves"

        /// What the activity should show at a moment, even if the app hasn't updated it: the widget can't wake the app, so the
        /// views work it out from the dates (an upcoming block turns into "during" once its start passes).
        func shown(at now: Date, stale: Bool) -> Phase {
            switch phase {
            case .upcoming, .rest:   // stale date = start: from then on it's the block itself
                if now < start && !stale { return phase }
                return now < end ? .during : .ended
            case .during:            // stale date = end
                return now >= end || stale ? .ended : .during
            case .ended: return .ended
            }
        }
    }
    var blockID: String
    /// Started from Shortcuts or Siri (not from your timetable): the app's own refresh leaves it alone until it's over.
    var manual: Bool? = nil

    /// One id per block, the same whether the app or a Shortcut shows it, so the same block is never shown twice.
    static func id(title: String, start: Date) -> String {
        let name = title.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return "sb-\(name)@\(Int(start.timeIntervalSince1970 / 60))"
    }
}
