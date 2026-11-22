import Foundation
import WatchConnectivity

/// Sends the timetable to the watch and hears back when homework is ticked off there.
/// WatchConnectivity goes over Bluetooth, so this works without an internet connection.
@MainActor
final class PhoneSync: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneSync()

    /// What the Settings screen says about the watch.
    @Published private(set) var status = "Looking for your Apple Watch…"
    @Published private(set) var lastSent: Date?

    var onToggle: (@MainActor (UUID, Bool) -> Void)?
    var current: (@MainActor () -> Timetable?)?

    private var waiting: Timetable?

    private override init() { super.init() }

    func start(with timetable: Timetable) {
        guard WCSession.isSupported() else {
            status = "This iPhone can't pair with an Apple Watch."
            return
        }
        waiting = timetable
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Hands the latest timetable to the watch. If the watch is out of reach, it gets it when it's back.
    func push(_ timetable: Timetable) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            waiting = timetable
            return
        }
        refreshStatus()
        guard session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(timetable) else { return }
        do {
            try session.updateApplicationContext([SyncKey.timetable: data, SyncKey.sent: Date().timeIntervalSince1970])
            lastSent = .now
        } catch {
            status = "Couldn't reach the watch: \(error.localizedDescription)"
        }
    }

    private func refreshStatus() {
        let session = WCSession.default
        if !session.isPaired {
            status = "No Apple Watch is paired with this iPhone."
        } else if !session.isWatchAppInstalled {
            status = "Lineup isn't on your watch yet. Open the Watch app, find Lineup and tap Install."
        } else {
            status = "Your watch has a copy of your timetable."
        }
    }

    private func activated() {
        refreshStatus()
        if let waiting = waiting ?? current?() {
            self.waiting = nil
            push(waiting)
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.activated() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another watch: start again so the new one gets the timetable.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.activated() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo[SyncKey.toggle] as? String, let id = UUID(uuidString: raw),
              let done = userInfo[SyncKey.done] as? Bool else { return }
        Task { @MainActor in self.onToggle?(id, done) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            let data = self.current?().flatMap { try? JSONEncoder().encode($0) }
            replyHandler(data.map { [SyncKey.timetable: $0] } ?? [:])
        }
    }
}
