import BackgroundTasks
import Foundation
import SwiftData

/// Records play counts over time (SPEC §6.12). Apple only gives all-time counts, so after every library scan
/// we write a row for each song whose count changed. The first scan is the baseline: recaps start that day.
@MainActor
final class SnapshotService {
    static let shared = SnapshotService()
    static let taskID = "com.jm2kool.liner.snapshot"

    private var lastCounts: [UInt64: Int] = [:]
    private var loaded = false

    var baselineDate: Date? { UserDefaults.standard.object(forKey: "recaps.baseline") as? Date }

    private var countsFile: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "LINER", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "lastCounts.json")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: countsFile), let map = try? JSONDecoder().decode([String: Int].self, from: data) {
            lastCounts = Dictionary(map.compactMap { k, v in UInt64(k).map { ($0, v) } }, uniquingKeysWith: { max($0, $1) })
        }
    }

    private func persist() {
        let map = Dictionary(lastCounts.map { (String($0.key), $0.value) }, uniquingKeysWith: { max($0, $1) })
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: countsFile, options: .atomic) }
    }

    /// Call after each scan.
    func record(_ snapshot: LibrarySnapshot) {
        guard !snapshot.songs.isEmpty else { return }
        load()
        let context = Store.shared.context
        let now = Date.now
        if baselineDate == nil {
            // Baseline: every song's current count, so later changes have something to compare with.
            UserDefaults.standard.set(now, forKey: "recaps.baseline")
            for s in snapshot.songs {
                context.insert(PlaySnapshot(date: now, persistentID: s.id, playCount: s.playCount))
            }
        } else {
            for s in snapshot.songs {
                let before = lastCounts[s.id] ?? 0
                if s.playCount > before {
                    context.insert(PlaySnapshot(date: now, persistentID: s.id, playCount: s.playCount))
                }
            }
        }
        lastCounts = Dictionary(snapshot.songs.map { ($0.id, $0.playCount) }, uniquingKeysWith: { max($0, $1) })
        persist()
        Store.shared.save()
    }

    /// The in-app play log.
    func log(_ record: PlayRecord) {
        Store.shared.context.insert(PlayEvent(record: record))
        Store.shared.save()
    }

    // MARK: Background refresh (best effort, about daily)

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { @Sendable task in
            nonisolated(unsafe) let task = task
            Task { @MainActor in
                await LibraryService.current?.refresh()
                task.setTaskCompleted(success: true)
                schedule()
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = .now.addingTimeInterval(12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
