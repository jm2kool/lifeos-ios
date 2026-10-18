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
    var libraryPath: [LibraryPage] = []   // lets a suggestion open a page (and item) inside Library
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
    /// The server's base address, e.g. https://lifeos.vercel.app (accepts the old …/api/lifeos form too).
    private var serverRoot: String {
        var s = syncURL
        if s.hasSuffix("/api/lifeos") { s.removeLast("/api/lifeos".count) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
    private func request(_ method: String, body: JSON? = nil) async throws -> JSON {
        try await api(method, "lifeos", query: method == "GET" ? ["since": base["rev"].str] : [:], body: body)
    }
    /// Calls /api/<path> on your LifeOS server with the sync key in the Authorization header (never in the URL).
    func api(_ method: String, _ path: String, query: [String: String] = [:], body: JSON? = nil, timeout: TimeInterval = 20) async throws -> JSON {
        guard !syncURL.isEmpty, var comps = URLComponents(string: serverRoot + "/api/" + path) else { throw Reducer.OpError(message: "Sync is off: add your server in Settings") }
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw Reducer.OpError(message: "The server address isn't valid") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = Keychain.get("syncKey"), !key.isEmpty { req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = body.data() }
        let (data, res) = try await URLSession.shared.data(for: req)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 0
        let j = JSON.parse(data) ?? .null
        if code == 401 { throw Reducer.OpError(message: j["error"].string.map { "Sync key: " + $0 } ?? "Add your sync key in Settings") }
        if code >= 400 { throw Reducer.OpError(message: [j["error"].string ?? "Server error (\(code))", j["fix"].string].compactMap { $0 }.joined(separator: " ")) }
        return j
    }

    // MARK: import
    struct ImportPlan: Identifiable {
        let id = UUID()
        let file: JSON
        let viaServer: Bool
        let summary: String       // "Would import 3 tasks, 40 events, 11 inbox items; 2 likely duplicates skipped."
        let skipped: [String]     // what the duplicate check left out, and why
        let failed: [String]
    }
    /// Checks a file before importing. With sync on, the server merges it with what it has (nothing is replaced).
    func planImport(_ file: JSON) async throws -> ImportPlan {
        if syncURL.isEmpty {
            let c = Store.counts(file)
            let dups = Reducer.duplicateEvents(file).map { g in "\(g.dropFirst().map(\.title).joined(separator: ", ")) (same as \(g[0].title), \(g[0].start.prefix(10)))" }
            return ImportPlan(file: file, viaServer: false, summary: "This replaces what is on this iPhone with \(c). Sync is off, so nothing is sent anywhere.", skipped: dups.map { "Possible duplicate: " + $0 }, failed: [])
        }
        await push()
        let j = try await api("POST", "import", body: ["doc": file, "dryRun": true], timeout: 60)
        return ImportPlan(file: file, viaServer: true, summary: j["summary"].str, skipped: Store.describe(j["items"].array, "duplicate"), failed: Store.describe(j["items"].array, "failed"))
    }
    /// Runs the import and returns the confirmation to show ("Imported 3 tasks, 40 events, 11 inbox items…").
    func runImport(_ plan: ImportPlan) async throws -> String {
        guard plan.viaServer else {
            replace(with: plan.file)
            return "Imported \(Store.counts(plan.file)) on this iPhone."
        }
        let j = try await api("POST", "import", body: ["doc": plan.file, "returnDoc": true], timeout: 60)
        if j["doc"].isObject { withAnimation(.smooth) { adopt(j["doc"]) } }
        syncOn = true; syncStatus = "Synced " + Date().formatted(date: .omitted, time: .shortened)
        // read it back so the confirmation reflects what the server really holds
        guard let check = try? await api("GET", "lifeos"), check["doc"].isObject else { return j["summary"].str }
        adopt(check["doc"])
        return j["summary"].str + "\nYour server now has \(Store.counts(check["doc"]))."
    }
    static func counts(_ d: JSON) -> String {
        let t = d["state"]["tasks"].array.count, e = d["content"]["events"].array.count, i = d["content"]["inbox"].array.count
        return "\(t) task\(t == 1 ? "" : "s"), \(e) event\(e == 1 ? "" : "s"), \(i) inbox item\(i == 1 ? "" : "s")"
    }
    private static func describe(_ items: [JSON], _ status: String) -> [String] {
        items.filter { $0["status"].str == status }.map { x in
            let what = x["title"].string ?? "\(x["kind"].str) #\(x["index"].int.map { $0 + 1 } ?? 0)"
            if status == "failed" { return what + ": " + x["error"].str }
            return what + (x["duplicateTitle"].string.map { " (same as “\($0)”)" } ?? x["reason"].string.map { " (\($0))" } ?? "")
        }
    }

    // MARK: where a Gemini suggestion points
    /// Opens the screen a suggestion is about, with the item already open: a draft, an email, an event, the board…
    func open(_ t: JSON) {
        let page = t["page"].str, id = t["id"].str
        sheet = nil
        switch page {
        case "draft", "drafts":
            tab = .library
            libraryPath = drafts.contains { $0.id == id } ? [.drafts, .draft(id)] : [.drafts]
        case "inbox", "email":
            tab = .inbox
            if mail.contains(where: { $0.id == id }) { present(.inbox(id)) }
        case "calendar", "event":
            tab = .library; libraryPath = [.calendar]
            if allEvents.contains(where: { $0.id == id }) { present(.event(id)) }
        case "board", "card": tab = .library; libraryPath = [.board]
        case "timetable": tab = .library; libraryPath = [.timetable]
        case "saved": tab = .library; libraryPath = [.saved]
        case "feed":
            tab = .library; libraryPath = [.feed]
            if feed.contains(where: { $0.id == id }) { present(.feed(id)) }
        case "study": tab = .study
        default: tab = .today
        }
    }
    /// Sheets can't open while another is closing, so wait a moment.
    private func present(_ route: SheetRoute) {
        Task { try? await Task.sleep(for: .milliseconds(350)); sheet = route }
    }

    /// Where a suggestion points. Uses Gemini's own target when it names something that exists,
    /// otherwise matches the words against pending drafts, emails, cards, tasks and upcoming events.
    func target(for text: String, hint: JSON = .null) -> JSON? {
        if hint.isObject, !hint["page"].str.isEmpty, !hint["id"].str.isEmpty, exists(hint["id"].str) { return ["page": hint["page"], "id": hint["id"]] }
        let lower = text.lowercased(), w = Reducer.words(text)
        let wantsDraft = ["draft", "repl", "approve", "review the plan"].contains { lower.contains($0) }
        var best: (JSON, Int)?
        func consider(_ page: String, _ id: String, _ title: String, bonus: Int = 0) {
            let n = Reducer.words(title).intersection(w).count
            guard n > 0 else { return }
            if n + bonus >= 2, n + bonus > (best?.1 ?? 0) { best = (["page": .string(page), "id": .string(id)], n + bonus) }
        }
        for d in pendingDrafts { consider("draft", d.id, d.title + " " + (d.latest?.subject ?? ""), bonus: wantsDraft ? 1 : 0) }
        for m in inboxTodo {
            if wantsDraft, let d = replyDraft(for: m) { consider("draft", d.id, m.title + " " + m.senderName, bonus: 1) }
            else { consider("inbox", m.id, m.title + " " + m.senderName) }
        }
        for c in cards where c.column < 2 { consider("board", c.id, c.title) }
        for e in upcoming.prefix(30) { consider("calendar", e.id, e.title) }
        if let best { return best.0 }
        if hint.isObject, !hint["page"].str.isEmpty { return ["page": hint["page"]] }
        // no item matched: go by what kind of thing it is
        if wantsDraft { return pendingDrafts.count == 1 ? ["page": "draft", "id": .string(pendingDrafts[0].id)] : ["page": "drafts"] }
        let kinds: [(String, [String])] = [("inbox", ["email", "inbox", "mail"]), ("study", ["study", "revise", "revision", "chapter", "practice", "focus"]),
                                           ("calendar", ["exam", "class", "tuition", "event", "calendar"]), ("board", ["board", "card"]), ("timetable", ["timetable"])]
        return kinds.first { $0.1.contains { lower.contains($0) } }.map { ["page": .string($0.0)] }
    }
    private func exists(_ id: String) -> Bool {
        drafts.contains { $0.id == id } || mail.contains { $0.id == id } || allEvents.contains { $0.id == id } || cards.contains { $0.id == id } || feed.contains { $0.id == id }
    }
    /// "Opens draft · Reply: MUN conference" for the bar under a suggestion.
    func targetLabel(_ t: JSON) -> String {
        let id = t["id"].str
        switch t["page"].str {
        case "draft", "drafts": return drafts.first { $0.id == id }.map { "Opens draft · " + $0.title } ?? "Opens Drafts"
        case "inbox", "email": return mail.first { $0.id == id }.map { "Opens email · " + $0.title } ?? "Opens Inbox"
        case "calendar", "event": return allEvents.first { $0.id == id }.map { "Opens " + $0.title + " · " + relDay(day($0)) } ?? "Opens Calendar"
        case "board", "card": return cards.first { $0.id == id }.map { "Opens Board · " + $0.title } ?? "Opens Board"
        case "feed": return "Opens Feed"
        case "study": return "Opens Study"
        case "timetable": return "Opens Timetable"
        case "saved": return "Opens Saved"
        default: return "Opens Today"
        }
    }

    // MARK: changes made by others (your assistants, Gemini on the server)
    /// Log entries made with a key other than this iPhone's, since you last looked. Gemini's Today refresh itself isn't listed.
    var unseenChanges: [JSON] {
        state["log"].array.filter { e in
            !e["id"].isNull && e["undone"].isNull && !["owner", ""].contains(e["key"].str) && (e["at"].double ?? 0) > seenChangesAt
                && !(e["op"].str == "content.set" && e["target"].str == "pulse")
        }
    }
    var seenChangesAt: Double = {
        let v = UserDefaults.standard.double(forKey: "seenChangesAt")
        if v > 0 { return v }
        let now = Date().timeIntervalSince1970 * 1000; UserDefaults.standard.set(now, forKey: "seenChangesAt"); return now
    }()
    func markChangesSeen() {
        seenChangesAt = max(seenChangesAt, state["log"].array.compactMap { $0["at"].double }.max() ?? 0)
        UserDefaults.standard.set(seenChangesAt, forKey: "seenChangesAt")
    }
    /// Undoes logged changes on the server (yours or anyone's). Each undo is itself logged and can be undone.
    func undoOnServer(_ ids: [String], label: String = "Undone") async {
        guard !ids.isEmpty else { return }
        do {
            await push()
            let j = try await api("POST", "lifeos", body: ["undo": .array(ids.map { .string($0) })])
            if j["doc"].isObject { withAnimation(.smooth) { adopt(j["doc"]) } }
            show(label)
        } catch { show(error.localizedDescription) }
    }
    /// "FRIDAY" for a change someone else made; nil for your own.
    func changedBy(_ by: String) -> String? {
        let b = by.trimmingCharacters(in: .whitespaces)
        if b.isEmpty || ["you", "app"].contains(b.lowercased()) || b == profileName { return nil }
        return b
    }
    /// A short human description of a log entry: "Added task “Revise Sound”".
    func describe(_ e: JSON) -> String {
        let verbs: [String: String] = [
            "task.add": "Added task", "task.update": "Edited task", "task.done": "Ticked off a task", "task.remove": "Deleted task",
            "board.add": "Added card", "board.update": "Edited card", "board.move": "Moved card", "board.remove": "Deleted card",
            "saved.add": "Saved", "saved.update": "Edited saved item", "saved.remove": "Removed saved item",
            "inbox.done": "Marked email done", "inbox.priority": "Set email priority", "inbox.snooze": "Snoozed email",
            "draft.email": "Drafted email", "draft.remove": "Deleted draft", "draft.review": "Reviewed draft",
            "timetable.set": "Changed timetable", "message.add": "Pinned a note", "message.dismiss": "Dismissed a note",
            "content.upsert": "Updated", "content.put": "Updated", "content.remove": "Removed", "content.set": "Changed",
            "focus.log": "Logged focus time", "import": "Imported", "undo": "Undid", "doc.replace": "Replaced everything",
        ]
        let op = e["op"].str, sum = e["summary"].str
        if op == "import" || op == "undo" { return sum.isEmpty ? (verbs[op] ?? op) : sum }
        let v = verbs[op] ?? op
        return sum.isEmpty ? v : v + " “" + sum + "”"
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
