import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif

#if canImport(ActivityKit)
/// The study block Live Activity: before a block ("Physics starts in 8:12"), during it (goal, time left), at the break
/// after it, and "done". Shared by the app (which starts and updates it), the widget extension (which draws it) and the
/// server, which can start it with a push before a block (the JSON keys below are what the push sends).
struct StudyBlockAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable { case upcoming, during, rest, ended }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        var title: String           // the assignment or goal (during a break: the next block's)
        var goal: String = ""
        var subject: String = ""
        var colorHex: String = "#8FA8FF"
        var kind: String = "study"  // study | revision | review | practice
        var start: Date             // when the block starts (during a break: when the next one does)
        var end: Date
        var note: String = ""       // e.g. "Break · next up"

        /// What to show at a moment even if nothing has updated the activity: the widget can't wake the app, so the
        /// views work it out from the dates ("starts in" becomes "time left" once the start passes).
        func shown(at now: Date, stale: Bool) -> Phase {
            switch phase {
            case .upcoming, .rest:
                if now < start && !stale { return phase }
                return now < end ? .during : .ended
            case .during:
                return now >= end || stale ? .ended : .during
            case .ended:
                return .ended
            }
        }

        enum CodingKeys: String, CodingKey { case phase, title, goal, subject, colorHex, kind, start, end, note }

        init(phase: Phase, title: String, goal: String = "", subject: String = "", colorHex: String = "#8FA8FF", kind: String = "study",
             start: Date, end: Date, note: String = "") {
            self.phase = phase; self.title = title; self.goal = goal; self.subject = subject; self.colorHex = colorHex
            self.kind = kind; self.start = start; self.end = end; self.note = note
        }

        /// Optional keys may be missing from a push.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            phase = try c.decode(Phase.self, forKey: .phase)
            title = try c.decode(String.self, forKey: .title)
            goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
            subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
            colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#8FA8FF"
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "study"
            start = try Self.date(c, .start)
            end = try Self.date(c, .end)
            note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        }

        /// A push sends Unix seconds; ActivityKit's own encoding is seconds since 2001. Both are accepted.
        private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date {
            if let n = try? c.decode(Double.self, forKey: key) {
                return n > 1_500_000_000 ? Date(timeIntervalSince1970: n) : Date(timeIntervalSinceReferenceDate: n)
            }
            return try c.decode(Date.self, forKey: key)
        }
    }

    /// The block's id in Lumen (lowercase uuid), so a block is never shown twice.
    var blockID: String
}
#endif

#if canImport(AppIntents)
/// "Skip" or "Done" from the Live Activity, without opening Lumen. Runs in the app's process.
struct MarkStudyBlockIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark study block"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Block") var blockID: String
    @Parameter(title: "Status") var status: String

    init() {}
    init(blockID: String, status: String) {
        self.blockID = blockID
        self.status = status
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let id = blockID, s = status
        await MainActor.run { StudyActivity.mark(blockID: id, status: s) }
        #endif
        return .result()
    }
}
#endif
