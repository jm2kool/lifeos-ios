import AppIntents
import Foundation

/// Put this in a Shortcuts automation that runs when you open a distracting app.
/// During a study block or a focus round it brings you back to Lumen; the rest of the time it does nothing.
struct StudyLockCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Study lock check"
    static let description = IntentDescription("If a study block or focus round is on, opens Lumen so you get back to it. Outside study time it does nothing.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor
    func perform() async throws -> some IntentResult {
        guard StudyLock.locking != nil else { return .result() }
        Router.shared.showLock()
        try? await continueInForeground(nil, alwaysConfirm: false)
        return .result()
    }
}

/// True while you should be studying. Useful with an "If" in Shortcuts, or for Siri.
struct IsStudyTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Is it study time?"
    static let description = IntentDescription("Returns true while a study block or focus round is on and the study lock isn't on a break.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        if let s = StudyLock.locking {
            return .result(value: true, dialog: IntentDialog(stringLiteral: "Yes: \(s.title) until \(Fmt.time(s.end))."))
        }
        return .result(value: false, dialog: "No study block right now.")
    }
}

/// Opens Lumen on the study lock screen.
struct OpenStudyLockIntent: AppIntent {
    static let title: LocalizedStringResource = "Open study lock"
    static let description = IntentDescription("Opens Lumen on the study lock screen.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.showLock()
        return .result()
    }
}

/// Shortcuts action with no inputs: shows the study block that's on now, or the next one, as a Live Activity
/// (Lock Screen and Dynamic Island). Doesn't open Lumen. Good for a Time of Day automation.
struct ShowNextStudyBlockIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Show next study block"
    static let description = IntentDescription("Shows the study block that's on now, or the next one in your Lumen plan, on the Lock Screen and in the Dynamic Island. Doesn't open Lumen.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await StudyActivity.showNext()
        return .result(dialog: IntentDialog(stringLiteral: said))
    }
}

struct LumenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StudyLockCheckIntent(), phrases: ["Check my study lock in \(.applicationName)"],
                    shortTitle: "Study lock check", systemImageName: "lock")
        AppShortcut(intent: ShowNextStudyBlockIntent(), phrases: ["Show my next study block in \(.applicationName)", "Next study block in \(.applicationName)"],
                    shortTitle: "Next study block", systemImageName: "book")
        AppShortcut(intent: IsStudyTimeIntent(), phrases: ["Is it study time in \(.applicationName)", "Should I be studying in \(.applicationName)"],
                    shortTitle: "Is it study time?", systemImageName: "book.closed")
    }
}
