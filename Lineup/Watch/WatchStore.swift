import Foundation
import WatchConnectivity

/// The watch's own copy of the timetable. It's saved on the watch, so the app works with the phone
/// out of reach and no internet; the phone sends a fresh copy over Bluetooth whenever something changes.
@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var timetable: Timetable
    /// Things ticked off on the pack list, as "day|subject|item". Cleared each day.
    @Published private(set) var packed: Set<String>
    /// Homework ticked off on the watch this session, so it stays on screen with a tick.
    @Published private(set) var ticked: Set<UUID> = []

    /// Ticks the phone hasn't confirmed yet, so an older copy from the phone doesn't undo them.
    private var waiting: [UUID: Bool] = [:]
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("timetable.json")
    private static let packedKey = "packed"

    override init() {
        if ProcessInfo.processInfo.environment["LINEUP_SAMPLE"] == "1" {
            timetable = .example(around: .now)
        } else if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Timetable.self, from: data) {
            timetable = saved
        } else {
            timetable = Timetable()
        }
        let today = Self.dayKey(.now)
        packed = Set((UserDefaults.standard.stringArray(forKey: Self.packedKey) ?? []).filter { $0.hasPrefix(today) })
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Homework and packing

    func toggle(_ assignment: Assignment) {
        guard let i = timetable.assignments.firstIndex(where: { $0.id == assignment.id }) else { return }
        let done = !timetable.assignments[i].done
        timetable.assignments[i].done = done
        ticked.insert(assignment.id)
        waiting[assignment.id] = done
        save()
        // transferUserInfo queues the tick and delivers it whenever the phone is next in range.
        if WCSession.isSupported(), WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo([SyncKey.toggle: assignment.id.uuidString, SyncKey.done: done])
        }
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    func packKey(day: Date, subject: UUID, item: String) -> String {
        "\(Self.dayKey(.now))|\(Self.dayKey(day))|\(subject.uuidString)|\(item)"
    }

    func togglePacked(_ key: String) {
        if packed.contains(key) { packed.remove(key) } else { packed.insert(key) }
        UserDefaults.standard.set(Array(packed), forKey: Self.packedKey)
    }

    // MARK: Sync

    /// Asks the phone for its latest copy, if it's in range.
    func refresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([SyncKey.request: true], replyHandler: { @Sendable reply in
            guard let data = reply[SyncKey.timetable] as? Data else { return }
            Task { @MainActor in self.receive(data) }
        }, errorHandler: nil)
    }

    private func receive(_ data: Data) {
        guard var incoming = try? JSONDecoder().decode(Timetable.self, from: data) else { return }
        for (id, done) in waiting {
            if let i = incoming.assignments.firstIndex(where: { $0.id == id }) {
                if incoming.assignments[i].done == done { waiting[id] = nil } else { incoming.assignments[i].done = done }
            } else {
                waiting[id] = nil
            }
        }
        guard incoming != timetable else { return }
        timetable = incoming
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(timetable) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[SyncKey.timetable] as? Data
        Task { @MainActor in
            if let data { self.receive(data) }
            self.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[SyncKey.timetable] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
}
