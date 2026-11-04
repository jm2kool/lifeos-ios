import Foundation
import SwiftData

/// Keeps this iPhone and Supabase in step. Local changes go up first (the server keeps whichever write is newer),
/// then everything that changed on the server since the last sync comes down, including Instinct's work.
@Observable @MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    enum State: Equatable {
        case idle, syncing, offline
        case needsSetup(String)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastSync: Date? {
        didSet { UserDefaults.standard.set(lastSync, forKey: "sync.last") }
    }

    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Int, Never>?
    @ObservationIgnored private var again = false

    private struct Table {
        let name: String
        let push: @MainActor (ModelContext, String) async throws -> Int
        let pull: @MainActor (ModelContext, Int64) async throws -> (count: Int, cursor: Int64)
    }

    private let tables: [Table]

    private init() {
        lastSync = UserDefaults.standard.object(forKey: "sync.last") as? Date
        tables = [
            Self.table(UserPrefs.self), Self.table(StudySubject.self), Self.table(Chapter.self), Self.table(Topic.self),
            Self.table(Assignment.self), Self.table(FileAttachment.self), Self.table(StudyBlock.self), Self.table(FocusSession.self),
            Self.table(AvailabilityWindow.self), Self.table(BusySlot.self), Self.table(Proposal.self), Self.table(ActivityItem.self),
            Self.table(Deck.self), Self.table(Card.self), Self.table(ReviewLog.self),
        ]
    }

    private static func table<T: PersistentModel & Synced>(_ type: T.Type) -> Table {
        Table(name: T.table, push: { ctx, user in
            let dirty = ((try? ctx.fetch(FetchDescriptor<T>())) ?? []).filter { $0.dirty }
            guard !dirty.isEmpty else { return 0 }
            var start = 0
            while start < dirty.count {
                let chunk = Array(dirty[start..<min(start + 200, dirty.count)])
                let stamps = chunk.map(\.updatedAt)
                try await API.upsert(T.table, rows: chunk.map { $0.row(user: user) })
                // Something edited while the request was out stays dirty for next time.
                for (i, item) in chunk.enumerated() where item.updatedAt == stamps[i] { item.dirty = false }
                start += 200
            }
            return dirty.count
        }, pull: { ctx, from in
            var cursor = from
            var count = 0
            var index: [UUID: T] = [:]
            for item in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] { index[item.id] = item }
            while true {
                let rows = try await API.select(T.table, [("select", "*"), ("rev", "gt.\(cursor)"), ("order", "rev.asc"), ("limit", "500")])
                for raw in rows {
                    let r = Row(raw)
                    if let rev = r.int("rev") { cursor = max(cursor, Int64(rev)) }
                    guard let id = r.uuid("id") else { continue }
                    let remote = r.date("updated_at") ?? .distantPast
                    if let local = index[id] {
                        // A newer change still waiting to go up wins over the server's copy.
                        if local.dirty && local.updatedAt > remote { continue }
                        local.applyRow(r)
                        local.dirty = false
                    } else {
                        let item = T(id: id)
                        item.applyRow(r)
                        item.dirty = false
                        ctx.insert(item)
                        index[id] = item
                    }
                    count += 1
                }
                if rows.count < 500 { break }
            }
            return (count, cursor)
        })
    }

    private func cursorKey(_ table: String, user: String) -> String { "sync.cursor.\(user).\(table)" }

    /// Sends local changes soon (batched, so a burst of edits is one request).
    func schedulePush() {
        guard Auth.shared.signedIn else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await sync(pull: false)
        }
    }

    /// A full sync: push, then pull. Returns how many rows came down.
    @discardableResult
    func sync(pull: Bool = true) async -> Int {
        guard Auth.shared.signedIn, let user = Auth.shared.userID else { return 0 }
        if let running {
            if pull { again = true }
            _ = await running.value
            return 0
        }
        let task = Task { @MainActor () -> Int in
            var pulled = 0
            state = .syncing
            do {
                let ctx = Store.shared.context
                try? ctx.save()
                adoptPreferences(user: user)
                for t in tables { _ = try await t.push(ctx, user) }
                if pull {
                    _ = try? await API.rpc("sweep_missed", [:])
                    for t in tables {
                        let key = cursorKey(t.name, user: user)
                        let from = Int64(UserDefaults.standard.integer(forKey: key))
                        let r = try await t.pull(ctx, from)
                        UserDefaults.standard.set(Int(r.cursor), forKey: key)
                        pulled += r.count
                    }
                    lastSync = Date()
                }
                try? ctx.save()
                state = .idle
            } catch let e as APIError {
                if e.status == 0 { state = .offline }
                else if e.needsSetup { state = .needsSetup("Run the Lumen SQL migration and add `lumen` to Exposed schemas (Supabase → Project Settings → Data API).") }
                else { state = .failed(e.message) }
            } catch {
                state = .failed(error.localizedDescription)
            }
            return pulled
        }
        running = task
        var pulled = await task.value
        running = nil
        if pulled > 0 { Store.shared.save(sync: false) }
        if again {
            again = false
            pulled += await sync(pull: true)
        }
        return pulled
    }

    /// Forgets what's been pulled, so the next sync downloads everything again.
    func resetCursors() {
        guard let user = Auth.shared.userID else { return }
        for t in tables { UserDefaults.standard.removeObject(forKey: cursorKey(t.name, user: user)) }
    }

    /// Preferences use your account id as their id (one row each). Made before signing in, they take that id now,
    /// unless the account already has some, which then win.
    private func adoptPreferences(user: String) {
        guard let mine = UUID(uuidString: user) else { return }
        let ctx = Store.shared.context
        let rows = (try? ctx.fetch(FetchDescriptor<UserPrefs>())) ?? []
        guard !rows.contains(where: { $0.id == mine }) else {
            for r in rows where r.id != mine { ctx.delete(r) }
            return
        }
        if let local = rows.first {
            local.id = mine
            local.touch()
            for r in rows.dropFirst() { ctx.delete(r) }
        }
    }

    /// Called once you're signed in: everything made on this iPhone so far is marked to go up.
    func adoptLocalData() {
        let ctx = Store.shared.context
        func mark<T: PersistentModel & Synced>(_ type: T.Type) {
            for item in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] { item.dirty = true }
        }
        mark(UserPrefs.self); mark(StudySubject.self); mark(Chapter.self); mark(Topic.self); mark(Assignment.self)
        mark(FileAttachment.self); mark(StudyBlock.self); mark(FocusSession.self); mark(AvailabilityWindow.self)
        mark(BusySlot.self); mark(Proposal.self); mark(ActivityItem.self); mark(Deck.self); mark(Card.self); mark(ReviewLog.self)
        try? ctx.save()
    }

    var summary: String {
        switch state {
        case .idle:
            guard let lastSync else { return Auth.shared.signedIn ? "Not synced yet" : "On this iPhone only" }
            return "Synced " + lastSync.formatted(.relative(presentation: .named))
        case .syncing: return "Syncing…"
        case .offline: return "Offline — changes will sync later"
        case .needsSetup(let s): return s
        case .failed(let s): return "Sync problem: \(s)"
        }
    }
}
