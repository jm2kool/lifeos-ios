import UIKit

/// A short diary of what live lyrics did in the background — the card's updates, the keep-alive, interruptions,
/// and whether iOS let LINER. keep running — so a card that freezes can be explained. Settings → Listening →
/// Live lyrics log shows it and can share it.
@MainActor
enum LiveLyricsLog {
    struct Entry: Codable, Hashable { let date: Date; let text: String }

    private(set) static var entries: [Entry] = load()
    private static var file: URL { URL.cachesDirectory.appending(path: "LINER/live-lyrics-log.json") }
    private static var lastHeartbeat = Date.distantPast
    private static var observing = false

    static func add(_ text: String) {
        // The same note again within a minute (a keep-alive failing every tick) adds nothing.
        if let last = entries.last, last.text == text, Date.now.timeIntervalSince(last.date) < 60 { return }
        entries.append(Entry(date: .now, text: text))
        if entries.count > 400 { entries.removeFirst(entries.count - 400) }
        save()
    }

    /// Every minute while in the background: proof of life, and how long iOS says LINER. may keep running
    /// ("unlimited" means the keep-alive counts as playing audio).
    static func heartbeat(keepAlive: Bool, playing: Bool, lastUpdate: Date) {
        guard UIApplication.shared.applicationState == .background, Date.now.timeIntervalSince(lastHeartbeat) > 60 else { return }
        lastHeartbeat = .now
        let left = UIApplication.shared.backgroundTimeRemaining
        let allowance = left > 3600 ? "unlimited" : "\(Int(left)) s"
        let ago = Int(Date.now.timeIntervalSince(lastUpdate))
        add("Alive in background · time allowed: \(allowance) · keep-alive \(keepAlive ? "on" : "OFF") · \(playing ? "playing" : "paused") · last card update \(ago) s ago")
    }

    /// Notes app launches and moves between foreground and background, and whether iOS closed LINER. last time.
    static func startObserving() {
        guard !observing else { return }
        observing = true
        if let last = entries.last, last.text.hasPrefix("Alive in background") || last.text.hasPrefix("Went to background") {
            add("⚠︎ LINER. was closed by iOS while in the background (last sign of life \(last.date.formatted(date: .omitted, time: .standard))). The card froze from then.")
        }
        add("Launched")
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { add("Went to background") }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { add("Back in foreground") }
        }
        center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { add("Closed") }
        }
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { @Sendable _ in
            MainActor.assumeIsolated { add("Memory warning from iOS") }
        }
    }

    static func clear() { entries = []; save() }

    static var text: String {
        entries.map { "\($0.date.formatted(date: .abbreviated, time: .standard))  \($0.text)" }.joined(separator: "\n")
    }

    private static func load() -> [Entry] {
        guard let data = try? Data(contentsOf: URL.cachesDirectory.appending(path: "LINER/live-lyrics-log.json")) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
    }
}
