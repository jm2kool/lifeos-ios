import AppIntents
import Foundation

/// Put this in a Shortcuts automation that runs when you open a distracting app.
/// During a study block it brings you back to LifeOS; the rest of the time it does nothing.
struct StudyLockCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Study lock check"
    static let description = IntentDescription("If one of your study blocks is on, opens LifeOS so you get back to it. Outside study blocks it does nothing.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = Store.shared
        guard store.lockingBlock != nil else { return .result() }
        store.lockShown = true
        try? await continueInForeground(nil, alwaysConfirm: false)
        return .result()
    }
}

/// True while a study block is on. Useful with an "If" in Shortcuts, or for Siri.
struct IsStudyTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Is it study time?"
    static let description = IntentDescription("Returns true while one of your study blocks is on and the study lock isn't on a break.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let store = Store.shared
        if let b = store.lockingBlock {
            return .result(value: true, dialog: IntentDialog(stringLiteral: "Yes: \(b.title) until \(store.time(b.end))."))
        }
        return .result(value: false, dialog: "No study block right now.")
    }
}

/// Opens LifeOS on the study lock screen.
struct OpenStudyLockIntent: AppIntent {
    static let title: LocalizedStringResource = "Open study lock"
    static let description = IntentDescription("Opens LifeOS on the study lock screen.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Store.shared.lockShown = true
        return .result()
    }
}

struct LifeOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StudyLockCheckIntent(), phrases: ["Check my study lock in \(.applicationName)"],
                    shortTitle: "Study lock check", systemImageName: "lock")
        AppShortcut(intent: CaptureIntent(), phrases: ["Capture in \(.applicationName)", "Add to \(.applicationName)", "Note in \(.applicationName)", "Tell \(.applicationName)"],
                    shortTitle: "Capture", systemImageName: "mic")
        AppShortcut(intent: NextStudyBlockActivityIntent(), phrases: ["Show my next study block in \(.applicationName)", "Next study block in \(.applicationName)"],
                    shortTitle: "Next study block", systemImageName: "book")
        AppShortcut(intent: IsStudyTimeIntent(), phrases: ["Is it study time in \(.applicationName)", "Should I be studying in \(.applicationName)"],
                    shortTitle: "Is it study time?", systemImageName: "book.closed")
    }
}
