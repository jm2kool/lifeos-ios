import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif

/// What the widgets show, written by the app. It goes to the App Group folder the app and widgets share;
/// if the re-signing tool dropped the App Group, the widget reads the same snapshot from Supabase instead.
struct WidgetSnapshot: Codable, Equatable {
    struct Block: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var subject: String
        var colorHex: String
        var start: Date
        var end: Date
        var kind: String
    }
    struct Deadline: Codable, Equatable {
        var title: String
        var subject: String
        var colorHex: String
        var due: Date
        var kind: String
    }
    var upcoming: [Block] = []
    var todayMinutes: Int = 0
    var goalMinutes: Int = 120
    var streak: Int = 0
    var deadline: Deadline?
    var dueCards: Int = 0
    var updated: Date = Date()

    /// The next block that hasn't finished yet, as of `date`.
    func next(at date: Date) -> Block? { upcoming.first { $0.end > date } }
}

enum SharedStore {
    static let appGroup = "group.com.jm2kool.lumen"
    static let widgetKinds = ["LumenNextBlock", "LumenToday", "LumenDeadline"]

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("widget.json")
    }
    static var hasSharedFolder: Bool { fileURL != nil }

    static func save(_ s: WidgetSnapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: Fallback through the server

    struct Server { var base: String; var key: String }

    /// The Supabase project baked into the app. The widget reads the app's Info.plist (it lives inside the app).
    static func bakedServer() -> Server? {
        var bundle = Bundle.main
        if bundle.bundleURL.pathExtension == "appex",
           let app = Bundle(url: bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) { bundle = app }
        let url = (bundle.object(forInfoDictionaryKey: "LumenSupabaseURL") as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (bundle.object(forInfoDictionaryKey: "LumenSupabaseAnonKey") as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !url.hasPrefix("$("), URL(string: url)?.host != nil, !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return Server(base: url.hasSuffix("/") ? String(url.dropLast()) : url, key: key)
    }

    /// The same for the app and its widget on this iPhone, so both find the same snapshot on the server.
    @MainActor static var deviceKey: String? { UIDevice.current.identifierForVendor?.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }

    static func fetchRemote(device: String, server: Server) async -> WidgetSnapshot? {
        guard let url = URL(string: server.base + "/rest/v1/rpc/widget_get"),
              let body = try? JSONSerialization.data(withJSONObject: ["p_device": device]) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("lumen", forHTTPHeaderField: "Content-Profile")
        req.setValue(server.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(server.key)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    static func encodeForServer(_ s: WidgetSnapshot) -> Any? {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(s) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

#if canImport(ActivityKit)
/// The running focus timer on the Lock Screen and in the Dynamic Island.
struct FocusAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String              // focus | short | long | done
        var endDate: Date              // when this phase ends if it keeps running
        var paused: Bool
        var remaining: TimeInterval    // seconds left (shown while paused)
        var total: TimeInterval        // this phase's length
        var round: Int
        var rounds: Int

        var startDate: Date { endDate.addingTimeInterval(-total) }
        var progress: Double { total > 0 ? min(1, max(0, (total - remaining) / total)) : 0 }
        var isBreak: Bool { phase == "short" || phase == "long" }
        var label: String {
            switch phase {
            case "short": return "Short break"
            case "long": return "Long break"
            case "done": return "Session done"
            default: return paused ? "Paused" : "Focusing"
            }
        }
    }
    var title: String
    var subject: String
    var colorHex: String
}
#endif

#if canImport(AppIntents)
/// Pause or resume from the Lock Screen or Dynamic Island. Runs in the app's process.
struct ToggleFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume focus"
    static var isDiscoverable: Bool = false
    init() {}
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { FocusTimer.shared.togglePause() }
        #endif
        return .result()
    }
}

/// Ends the focus session from the Lock Screen; the outcome is asked for next time the app opens.
struct EndFocusIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End focus"
    static var isDiscoverable: Bool = false
    init() {}
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { FocusTimer.shared.finish(askOutcome: true) }
        #endif
        return .result()
    }
}
#endif
