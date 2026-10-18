import Foundation
import SwiftUI
import Observation

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var undo: Bool = false
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

struct UndoEntry: Identifiable {
    let id = UUID()
    let label: String
    let ops: [JSON]
    let at = Date()
}

enum SheetRoute: Identifiable, Equatable {
    case ask(String), capture, focus, inbox(String), feed(String), event(String), addTask, addSaved, addBlock, editTimetable, settings, onboarding, delegate(String), activity
    var id: String {
        switch self {
        case .ask: return "ask"
        case .capture: return "capture"
        case .focus: return "focus"
        case .inbox(let i): return "inbox-\(i)"
        case .feed(let i): return "feed-\(i)"
        case .event(let i): return "event-\(i)"
        case .addTask: return "addTask"
        case .addSaved: return "addSaved"
        case .addBlock: return "addBlock"
        case .editTimetable: return "editTimetable"
        case .settings: return "settings"
        case .onboarding: return "onboarding"
        case .delegate(let t): return "delegate-\(t.hashValue)"
        case .activity: return "activity"
        }
    }
}

enum AppTab: Hashable { case today, inbox, study, library, search }

@MainActor
@Observable
final class Store {
    private(set) var doc: JSON
    @ObservationIgnored private var base: JSON
    @ObservationIgnored private var pending: [JSON]
    var toast: Toast?
    var undoStack: [UndoEntry] = []
    var sheet: SheetRoute?
    var tab: AppTab = .today
    var lockShown = false       // study lock screen
    static let shared = Store()
    var syncStatus: String = "Sync is off. Everything stays on this iPhone."
    var syncOn = false
    var tick = Date()           // drives live clocks
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pushTask: Task<Void, Never>?

    init() {
        let seed = Store.loadSeed()
        var b: JSON
        if let saved = Store.read("doc.json") {
            b = Reducer.normalize(saved)
            if (seed["rev"].int ?? 0) > (b["rev"].int ?? 0) && b["server"].isNull {
                b["content"] = seed["content"]; b["rev"] = seed["rev"]
            }
        } else {
            b = Reducer.normalize(seed)
        }
        let p = Store.read("pending.json")?.array ?? []
        var d = b
        for op in p { try? Reducer.apply(&d, op) }
        base = b
        pending = p
        doc = d
        Task { await self.pull(quiet: true) }
    }

    // MARK: persistence
    nonisolated static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LifeOS", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    nonisolated static func read(_ name: String) -> JSON? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return JSON.parse(d)
    }
    nonisolated static func write(_ name: String, _ v: JSON) {
        try? v.data().write(to: dir.appendingPathComponent(name), options: .atomic)
    }
    nonisolated static func loadSeed() -> JSON {
        if let u = Bundle.main.url(forResource: "seed", withExtension: "json"), let d = try? Data(contentsOf: u), let j = JSON.parse(d) { return j }
        return Reducer.normalize(.object([:]))
    }
    private func rebuild() {
        var d = base
        for op in pending { try? Reducer.apply(&d, op) }
        doc = d
    }
    private func persistSoon() {
        saveTask?.cancel()
        let b = base, p = JSON.array(pending)
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(250))
            Store.write("doc.json", b); Store.write("pending.json", p)
        }
    }

    // MARK: changes
    /// Apply ops. With `undo`, the change can be reverted from the toast or Activity.
    @discardableResult
    func act(_ ops: [JSON], by: String = "you", undo label: String? = nil, quiet: Bool = false) -> Bool {
        var work = doc
        var inverses: [[JSON]] = []
        var accepted: [JSON] = []
        for raw in ops {
            var op = Reducer.prepared(raw)
            if op["by"].isNull { op["by"] = .string(by) }
            let inv = Reducer.inverse(of: op, in: work)
            do { try Reducer.apply(&work, op); accepted.append(op); inverses.append(inv) }
            catch { if !quiet { show((error as? LocalizedError)?.errorDescription ?? "That change couldn't be made") }; if ops.count == 1 { return false } }
        }
        guard !accepted.isEmpty else { return false }
        withAnimation(.smooth(duration: 0.35)) { doc = work }
        pending.append(contentsOf: accepted)
        if let label {
            let undoOps = inverses.reversed().flatMap { $0 }
            if !undoOps.isEmpty {
                undoStack.append(UndoEntry(label: label, ops: undoOps))
                if undoStack.count > 30 { undoStack.removeFirst() }
                if !quiet { toast = Toast(text: label, undo: true) }
            }
        }
        persistSoon(); schedulePush()
        return true
    }
    @discardableResult func act(_ op: JSON, by: String = "you", undo label: String? = nil, quiet: Bool = false) -> Bool {
        let list: [JSON] = [op]
        return act(list, by: by, undo: label, quiet: quiet)
    }

    func undoLast() {
        guard let e = undoStack.popLast() else { return }
        act(e.ops, by: "you", undo: nil, quiet: true)
        show("Undone")
    }
    func show(_ text: String) { toast = Toast(text: text) }

    /// Replace everything (import, start fresh).
    func replace(with newDoc: JSON) {
        base = Reducer.normalize(newDoc); pending = []; undoStack = []
        rebuild(); persistSoon(); schedulePush()
    }

    // MARK: sync (optional; same server your iMessage assistant talks to)
    var syncURL: String { doc["settings"]["sync"]["url"].str.trimmingCharacters(in: .whitespaces) }
    private func request(_ method: String, body: JSON? = nil) async throws -> JSON {
        guard !syncURL.isEmpty, var comps = URLComponents(string: syncURL.hasSuffix("/api/lifeos") ? syncURL : syncURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/lifeos") else {
            throw Reducer.OpError(message: "off")
        }
        if method == "GET" { comps.queryItems = [URLQueryItem(name: "since", value: base["rev"].str)] }
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = Keychain.get("syncKey"), !key.isEmpty { req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = body.data() }
        let (data, res) = try await URLSession.shared.data(for: req)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        let j = JSON.parse(data) ?? .null
        if code == 401 { throw Reducer.OpError(message: "Add your sync key in Settings") }
        if code >= 400 { throw Reducer.OpError(message: j["error"].string ?? "Sync failed (\(code))") }
        return j
    }
    private func adopt(_ remote: JSON) {
        guard remote["state"].isObject else { return }
        let acked = Set(remote["applied"].array.map(\.str))
        pending.removeAll { acked.contains($0["opId"].str) }
        base = Reducer.normalize(remote); base["server"] = true
        rebuild(); persistSoon()
    }
    func pull(quiet: Bool = false) async {
        guard !syncURL.isEmpty else { syncOn = false; syncStatus = "Sync is off. Everything stays on this iPhone."; return }
        do {
            let j = try await request("GET")
            if j["doc"].isObject {
                let remote = j["doc"]
                let remoteEmpty = remote["content"].object.isEmpty && remote["state"]["tasks"].array.isEmpty && remote["profile"]["name"].str.isEmpty
                let localHas = !doc["content"].object.isEmpty || !doc["profile"]["name"].str.isEmpty
                if remoteEmpty && localHas {
                    // First sync: the server is empty, so upload this iPhone's data instead of wiping it.
                    var up = doc; up["server"] = .null
                    let r = try await request("PUT", body: ["doc": up, "by": "app"])
                    if r["doc"].isObject { adopt(r["doc"]) }
                } else {
                    withAnimation(.smooth) { adopt(remote) }
                }
            }
            syncOn = true; syncStatus = "Synced " + Date().formatted(date: .omitted, time: .shortened)
            if !pending.isEmpty { await push() }
        } catch {
            syncOn = false; syncStatus = error.localizedDescription
            if !quiet { show(syncStatus) }
        }
    }
    func push() async {
        guard !pending.isEmpty, !syncURL.isEmpty else { return }
        do {
            let j = try await request("POST", body: ["ops": .array(pending), "rev": base["rev"]])
            if j["doc"].isObject { adopt(j["doc"]) }
            syncOn = true; syncStatus = "Synced " + Date().formatted(date: .omitted, time: .shortened)
        } catch { syncStatus = error.localizedDescription }
    }
    private func schedulePush() {
        guard !syncURL.isEmpty else { return }
        pushTask?.cancel()
        pushTask = Task { try? await Task.sleep(for: .milliseconds(800)); await push() }
    }
    var unsyncedCount: Int { pending.count }
}
