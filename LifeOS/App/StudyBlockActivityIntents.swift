import AppIntents
import ActivityKit
import Foundation

/// Shortcuts action: shows a study block as a Live Activity ("starts in", then time left) without opening LifeOS.
/// Running it again for the same block updates it instead of adding a second one. Works on a free Apple ID: nothing
/// comes from a server (no push), the activity is started right here in perform().
struct StudyBlockActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Show study block"
    static let description = IntentDescription("Shows a study block on your Lock Screen and in the Dynamic Island: a countdown before it starts, then the time left. Doesn't open LifeOS. Running it again for the same block updates it.")

    @Parameter(title: "Block", requestValueDialog: IntentDialog("What are you studying?"))
    var block: String
    @Parameter(title: "Starts", requestValueDialog: IntentDialog("When does it start?"))
    var start: Date
    @Parameter(title: "Ends", requestValueDialog: IntentDialog("When does it end?"))
    var end: Date
    @Parameter(title: "Note", description: "Optional, e.g. a chapter or room.")
    var note: String?

    static var parameterSummary: some ParameterSummary { Summary("Show \(\.$block) from \(\.$start) to \(\.$end)") { \.$note } }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = try await StudyActivityController.show(title: block, start: start, end: end, note: note ?? "", manual: true)
        return .result(dialog: IntentDialog(stringLiteral: said))
    }
}

/// Shortcuts action with no inputs: shows the study block that's on now, or the next one in your timetable.
/// Good for a Time of Day automation a few minutes before your blocks usually start.
struct NextStudyBlockActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Show next study block"
    static let description = IntentDescription("Shows the study block that's on now, or the next one from your LifeOS timetable, as a Live Activity. Doesn't open LifeOS.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        guard let b = StudyActivityController.nextBlock(store) else {
            return .result(dialog: "No study block in the next 8 hours.")
        }
        let said = try await StudyActivityController.show(title: b.title, start: b.start, end: b.end, manual: false)
        return .result(dialog: IntentDialog(stringLiteral: said))
    }
}
