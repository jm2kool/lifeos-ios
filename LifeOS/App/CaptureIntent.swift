import AppIntents
import Foundation

/// Files something you say without opening LifeOS. With Siri ("Capture in LifeOS") Siri asks what to capture and listens in
/// its own small bubble. For the Action Button, make a Shortcut: Dictate Text → Capture with LifeOS → (if the result has any
/// value) Send Message to FRIDAY. You stay in whatever app you were in. Email drafts wait in Drafts; nothing is ever sent.
struct CaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture with LifeOS"
    static let description = IntentDescription("Files what you say as a to-do, email draft (never sent), calendar event, timetable block, note, link or board card, and says what it did. For calendar events it returns a message asking your assistant to add it to Google Calendar; otherwise the result is empty.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "What to capture", requestValueDialog: IntentDialog("What should I capture?"))
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Capture \(\.$text) with LifeOS") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = Store.shared
        let assistant = Assistant.shared
        if assistant.store == nil { assistant.store = store }
        // Intents get roughly half a minute; leave time to save.
        let out = await CaptureFiler.file(text, store: store, assistant: assistant, source: "Siri", timeout: 20)
        store.saveNow()
        if !store.syncURL.isEmpty { _ = try? await CaptureFiler.withTimeout(5) { await store.push() } }
        var say = out.summary
        if out.friday != nil { say += " I've got a message ready for \(store.assistantName) to add it to Google Calendar." }
        return .result(value: out.friday ?? "", dialog: IntentDialog(stringLiteral: say))
    }
}
