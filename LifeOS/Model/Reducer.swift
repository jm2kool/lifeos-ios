import Foundation

/// Every change in LifeOS is an "op": {"op": "task.add", ...fields}.
/// The same ops are used by you, by Gemini, by your iMessage assistant and by the sync server.
enum Reducer {
    static let columns = ["To do", "Doing", "Done"]
    struct OpError: LocalizedError { let message: String; var errorDescription: String? { message } }
    static let bad: Set<String> = ["__proto__", "prototype", "constructor"]

    static func uid(_ prefix: String) -> String {
        prefix + "-" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(UUID().uuidString.prefix(5)).lowercased()
    }

    /// Fills in missing structure so every view can rely on it.
    static func normalize(_ input: JSON) -> JSON {
        var d = input.isObject ? input : JSON.object([:])
        if d["schema"].isNull { d["schema"] = "lifeos/2" }
        if d["rev"].isNull { d["rev"] = 0 }
        var profile = d["profile"].isObject ? d["profile"] : .object([:])
        if !profile["assistant"].isObject { profile["assistant"] = .object([:]) }
        d["profile"] = profile
        if !d["settings"].isObject { d["settings"] = .object([:]) }
        if !d["content"].isObject { d["content"] = .object([:]) }
        var s = d["state"].isObject ? d["state"] : .object([:])
        for k in ["tasks", "board", "saved", "done", "inboxDone", "focus", "messages", "deletedTasks", "log"] where !s[k].isArray { s[k] = .array([]) }
        for k in ["priority", "snooze", "progress", "draftReviews"] where !s[k].isObject { s[k] = .object([:]) }
        if s["timetable"].string == nil { s["timetable"] = "" }
        d["state"] = s
        if !d["applied"].isArray { d["applied"] = .array([]) }
        return d
    }

    // MARK: helpers
    private static func str(_ v: JSON, _ max: Int = 4000) -> String { String(v.str.prefix(max)) }
    private static func idx(_ list: [JSON], _ id: JSON) -> Int? { list.firstIndex { $0["id"].str == id.str } }
    private static func columnIndex(_ v: JSON) -> Int? {
        if let n = v.int, (0...2).contains(n), case .number = v { return n }
        return columns.firstIndex(of: v.str)
    }
    private static func parts(_ path: String) throws -> [String] {
        let p = path.split(separator: ".").map(String.init)
        if p.isEmpty || p.contains(where: { bad.contains($0) }) { throw OpError(message: "Bad path") }
        return p
    }
    static func get(_ root: JSON, _ path: [String]) -> JSON { path.reduce(root) { $0[$1] } }
    static func set(_ root: inout JSON, _ path: [String], _ value: JSON) {
        guard let first = path.first else { root = value; return }
        var child = root[first]
        if path.count > 1 && !child.isObject && !child.isArray { child = .object([:]) }
        set(&child, Array(path.dropFirst()), value)
        if case .object(var o) = root {
            if value.isNull && path.count == 1 { o.removeValue(forKey: first) } else { o[first] = child }
            root = .object(o)
        } else { root = .object([first: child]) }
    }
    private static func list(_ d: JSON, _ k: String) -> [JSON] { d["state"][k].array }
    private static func put(_ d: inout JSON, _ k: String, _ v: [JSON]) { d["state"][k] = .array(v) }

    // MARK: apply
    static func apply(_ doc: inout JSON, _ op: JSON) throws {
        let name = op["op"].str
        let at: JSON = op["at"].isNull ? .now : op["at"]
        switch name {
        case "task.add":
            let title = str(op["title"], 240).trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { throw OpError(message: "Task needs a title") }
            var t: JSON = ["id": .string(op["id"].string ?? uid("task")), "title": .string(title), "note": .string(str(op["note"], 1500)), "src": .string(op["src"].string ?? "You"), "created": op["created"].isNull ? at : op["created"]]
            if let due = op["due"].string, !due.isEmpty { t["due"] = .string(String(due.prefix(10))) }
            if let p = op["priority"].string { t["priority"] = .string(p) }
            var l = list(doc, "tasks"); if idx(l, t["id"]) == nil { l.append(t) }; put(&doc, "tasks", l)
            put(&doc, "deletedTasks", list(doc, "deletedTasks").filter { $0.str != t["id"].str })
        case "task.update":
            var l = list(doc, "tasks"); guard let i = idx(l, op["id"]) else { throw OpError(message: "No such task") }
            for k in ["title", "note", "due", "src", "priority"] where op.object[k] != nil { l[i][k] = op[k] }
            put(&doc, "tasks", l)
        case "task.done":
            var set = list(doc, "done").map(\.str); let id = op["id"].str
            if op["done"] == .bool(false) { set.removeAll { $0 == id } } else if !set.contains(id) { set.append(id) }
            put(&doc, "done", set.map { .string($0) })
        case "task.remove":
            let id = op["id"].str
            put(&doc, "tasks", list(doc, "tasks").filter { $0["id"].str != id })
            put(&doc, "done", list(doc, "done").filter { $0.str != id })
            var del = list(doc, "deletedTasks"); if !del.contains(.string(id)) { del.append(.string(id)) }; put(&doc, "deletedTasks", del)

        case "board.add":
            let title = str(op["title"].isNull ? op["t"] : op["title"], 240).trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { throw OpError(message: "Card needs a title") }
            var b: JSON = ["id": .string(op["id"].string ?? uid("card")), "t": .string(title), "c": .number(Double(columnIndex(op["column"]) ?? 0)), "created": op["created"].isNull ? at : op["created"]]
            if let due = op["due"].string, !due.isEmpty { b["due"] = .string(String(due.prefix(10))) }
            if op["filed"] == .bool(false) { b["filed"] = false }
            if let n = op["note"].string, !n.isEmpty { b["note"] = .string(n) }
            var l = list(doc, "board"); if idx(l, b["id"]) == nil { l.append(b) }; put(&doc, "board", l)
        case "board.update":
            var l = list(doc, "board"); guard let i = idx(l, op["id"]) else { throw OpError(message: "No such card") }
            if op.object["title"] != nil { l[i]["t"] = op["title"] }
            for k in ["due", "note", "filed"] where op.object[k] != nil { l[i][k] = op[k] }
            if let c = columnIndex(op["column"]) { l[i]["c"] = .number(Double(c)); if c > 0 { l[i]["filed"] = .null } }
            put(&doc, "board", l)
        case "board.move":
            var l = list(doc, "board"); guard let i = idx(l, op["id"]) else { throw OpError(message: "No such card") }
            guard let c = columnIndex(op["column"]) else { throw OpError(message: "Column must be To do, Doing or Done") }
            l[i]["c"] = .number(Double(c)); if c > 0 { l[i]["filed"] = .null }
            put(&doc, "board", l)
        case "board.remove":
            put(&doc, "board", list(doc, "board").filter { $0["id"].str != op["id"].str })

        case "saved.add":
            let url = str(op["url"], 2000).trimmingCharacters(in: .whitespaces)
            if !url.isEmpty && !url.lowercased().hasPrefix("http") { throw OpError(message: "Links must start with http:// or https://") }
            let title = str(op["title"].isNull ? op["t"] : op["title"], 240).trimmingCharacters(in: .whitespaces)
            if title.isEmpty { throw OpError(message: "Saved item needs a title") }
            let s: JSON = ["id": .string(op["id"].string ?? uid("saved")), "t": .string(title), "url": .string(url), "n": .string(str(op["note"].isNull ? op["n"] : op["note"], 1500)), "s": .string(op["source"].string ?? op["s"].string ?? "You"), "c": op["created"].isNull ? at : op["created"]]
            var l = list(doc, "saved"); if idx(l, s["id"]) == nil { l.insert(s, at: 0) }; put(&doc, "saved", l)
        case "saved.update":
            var l = list(doc, "saved"); guard let i = idx(l, op["id"]) else { throw OpError(message: "No such item") }
            if op.object["title"] != nil { l[i]["t"] = op["title"] }
            if op.object["url"] != nil { l[i]["url"] = op["url"] }
            if op.object["note"] != nil { l[i]["n"] = op["note"] }
            put(&doc, "saved", l)
        case "saved.remove":
            put(&doc, "saved", list(doc, "saved").filter { $0["id"].str != op["id"].str })

        case "inbox.done":
            var set = list(doc, "inboxDone").map(\.str); let id = op["id"].str
            if op["done"] == .bool(false) { set.removeAll { $0 == id } } else if !set.contains(id) { set.append(id) }
            put(&doc, "inboxDone", set.map { .string($0) })
        case "inbox.priority":
            let v = op["value"].str
            doc["state"]["priority"][op["id"].str] = v.isEmpty ? .null : .string(v)
        case "inbox.snooze":
            let on = op["on"].bool || !op["until"].isNull
            doc["state"]["snooze"][op["id"].str] = on ? (op["until"].isNull ? .bool(true) : op["until"]) : .null

        case "progress.set":
            doc["state"]["progress"][op["id"].str] = ["done": .bool(op["done"].bool), "label": .string(str(op["label"], 300)), "at": at]
        case "focus.log":
            let m = Int((op["minutes"].double ?? 0).rounded())
            if m < 1 || m > 600 { throw OpError(message: "Minutes must be 1-600") }
            var l = list(doc, "focus")
            l.append(["id": .string(op["id"].string ?? uid("focus")), "date": .string(String(op["date"].str.prefix(10))), "minutes": .number(Double(m)), "label": .string(str(op["label"], 200)), "at": at])
            if l.count > 800 { l.removeFirst(l.count - 800) }
            put(&doc, "focus", l)
        case "focus.remove":
            put(&doc, "focus", list(doc, "focus").filter { $0["id"].str != op["id"].str })
        case "timetable.set":
            doc["state"]["timetable"] = .string(str(op["text"], 20000))
        case "draft.review":
            let action = op["action"].str == "changes" ? "changes" : "approve"
            let key = [op["draftId"].str, op["version"].str, op["week"].str, action].joined(separator: "|")
            doc["state"]["draftReviews"][key] = ["draftId": op["draftId"], "version": op["version"], "week": op["week"], "action": .string(action), "changes": .string(str(op["changes"])), "at": at, "state": op["state"].isNull ? "recorded" : op["state"]]
        case "draft.email":
            // Create or update an email reply draft. A new body becomes a new version.
            var drafts = doc["content"]["drafts"].array
            let id = op["id"].string ?? (op["inboxId"].isNull ? uid("email") : "reply-" + op["inboxId"].str)
            let body = str(op["body"], 8000)
            if body.isEmpty { throw OpError(message: "Email draft needs a body") }
            if let i = idx(drafts, .string(id)) {
                var versions = drafts[i]["versions"].array
                let next = (versions.compactMap { $0["version"].int }.max() ?? 0) + 1
                var v = versions.last ?? .object([:])
                v["version"] = .number(Double(next)); v["createdAt"] = .string(ISO8601DateFormatter().string(from: Date()))
                for k in ["to", "cc", "from", "subject"] where op.object[k] != nil { v[k] = op[k] }
                v["body"] = .string(body); v["by"] = op["by"]
                versions.append(v); drafts[i]["versions"] = .array(versions)
            } else {
                let v: JSON = ["version": 1, "createdAt": .string(ISO8601DateFormatter().string(from: Date())), "from": op["from"], "to": op["to"], "cc": op["cc"], "subject": op["subject"], "body": .string(body), "by": op["by"]]
                drafts.append(["id": .string(id), "title": .string(op["title"].string ?? ("Reply: " + op["subject"].str.replacingOccurrences(of: "Re: ", with: ""))), "type": "email", "inboxId": op["inboxId"], "source": op["by"], "versions": [v]])
            }
            doc["content"]["drafts"] = .array(drafts)
        case "draft.remove":
            doc["content"]["drafts"] = .array(doc["content"]["drafts"].array.filter { $0["id"].str != op["id"].str })

        case "message.add":
            var l = list(doc, "messages")
            l.insert(["id": .string(op["id"].string ?? uid("msg")), "from": .string(op["from"].string ?? "Assistant"), "text": .string(str(op["text"], 2000)), "url": .string(str(op["url"], 2000)), "at": at], at: 0)
            put(&doc, "messages", Array(l.prefix(50)))
        case "message.dismiss":
            put(&doc, "messages", list(doc, "messages").filter { $0["id"].str != op["id"].str })

        case "content.set":
            let p = try parts(op["path"].str); var c = doc["content"]; set(&c, p, op["value"]); doc["content"] = c
        case "content.merge":
            let p = try parts(op["path"].str); var c = doc["content"]
            var cur = get(c, p); if !cur.isObject { cur = .object([:]) }
            for (k, v) in op["value"].object where !bad.contains(k) { cur[k] = v }
            set(&c, p, cur); doc["content"] = c
        case "content.push":
            let p = try parts(op["path"].str); var c = doc["content"]
            var arr = get(c, p).array; arr.append(op["value"]); set(&c, p, .array(arr)); doc["content"] = c
        case "content.upsert":
            let p = try parts(op["path"].str); var c = doc["content"]
            let v = op["value"]; if v["id"].isNull { throw OpError(message: "content.upsert needs value.id") }
            var arr = get(c, p).array
            if let i = idx(arr, v["id"]) { for (k, x) in v.object { arr[i][k] = x } } else { arr.append(v) }
            set(&c, p, .array(arr)); doc["content"] = c
        case "content.put":
            // replaces the whole item with the same id (or adds it); used by undo and import
            let p = try parts(op["path"].str); var c = doc["content"]
            let v = op["value"]; if v["id"].isNull { throw OpError(message: "content.put needs value.id") }
            var arr = get(c, p).array
            if let i = idx(arr, v["id"]) { arr[i] = v } else { arr.append(v) }
            set(&c, p, .array(arr)); doc["content"] = c
        case "content.remove":
            let p = try parts(op["path"].str); var c = doc["content"]
            let cur = get(c, p)
            if cur.isArray { set(&c, p, .array(cur.array.filter { $0["id"].str != op["id"].str || op["id"].isNull })) }
            else if op["id"].isNull { set(&c, p, .null) }
            doc["content"] = c
        case "state.set":
            let p = try parts(op["path"].str); var s = doc["state"]; set(&s, p, op["value"]); doc["state"] = s
        case "state.setKey":
            // one key of a state map; keys may contain dots, so this isn't a path
            let m = op["path"].str
            guard ["priority", "snooze", "progress", "draftReviews"].contains(m) else { throw OpError(message: "state.setKey path must be priority, snooze, progress or draftReviews") }
            let k = op["key"].str; if bad.contains(k) { throw OpError(message: "Bad key") }
            doc["state"][m][k] = op["value"]
        case "profile.set":
            for (k, v) in op["value"].object where !bad.contains(k) { doc["profile"][k] = v }
        case "settings.set":
            for (k, v) in op["value"].object where !bad.contains(k) {
                if v.isObject, doc["settings"][k].isObject { var cur = doc["settings"][k]; for (k2, v2) in v.object { cur[k2] = v2 }; doc["settings"][k] = cur }
                else { doc["settings"][k] = v }
            }
        default:
            throw OpError(message: "Unknown op " + name)
        }
        stamp(&doc, op, at)
        if let opId = op["opId"].string {
            var a = doc["applied"].array; a.append(.string(opId)); if a.count > 400 { a.removeFirst(a.count - 400) }; doc["applied"] = .array(a)
        }
        var log = list(doc, "log")
        let summary = op["title"].string ?? op["text"].string ?? op["path"].string ?? op["subject"].string ?? ""
        log.insert(["op": .string(name), "by": .string(op["by"].string ?? "you"), "at": at, "summary": .string(String(summary.prefix(120)))], at: 0)
        put(&doc, "log", Array(log.prefix(80)))
    }

    /// Labels the item an op touched with who changed it ("changedBy"), as the server does.
    private static func stamp(_ doc: inout JSON, _ op: JSON, _ at: JSON) {
        let name = op["op"].str, by = JSON.string(String((op["by"].string ?? "you").prefix(40)))
        func mark(_ l: [JSON], _ id: JSON) -> [JSON]? {
            guard let i = idx(l, id) else { return nil }
            var l = l; l[i]["changedBy"] = by; l[i]["changedAt"] = at; return l
        }
        if let k = ["task": "tasks", "board": "board", "saved": "saved"][String(name.split(separator: ".").first ?? "")], !name.hasSuffix(".remove"), !name.hasSuffix(".done") {
            if let l = mark(list(doc, k), op["id"]) { put(&doc, k, l) }
        } else if name == "content.upsert" || name == "content.put", let p = try? parts(op["path"].str) {
            var c = doc["content"]
            if let l = mark(get(c, p).array, op["value"]["id"]) { set(&c, p, .array(l)); doc["content"] = c }
        }
    }

    /// Ops that undo `op` when applied to the document as it was before `op`.
    static func inverse(of op: JSON, in doc: JSON) -> [JSON] {
        let id = op["id"]
        func find(_ k: String) -> JSON? { doc["state"][k].array.first { $0["id"].str == id.str } }
        switch op["op"].str {
        case "task.add": return id.isNull ? [] : [["op": "task.remove", "id": id]]
        case "task.update": guard let t = find("tasks") else { return [] }
            var o: JSON = ["op": "task.update", "id": id]; for k in ["title", "note", "due", "src", "priority"] where op.object[k] != nil { o[k] = t[k].isNull ? .string("") : t[k] }; return [o]
        case "task.done": return [["op": "task.done", "id": id, "done": .bool(doc["state"]["done"].array.contains { $0.str == id.str })]]
        case "task.remove": guard let t = find("tasks") else { return [] }
            var o = t; o["op"] = "task.add"; var r = [o]
            if doc["state"]["done"].array.contains(where: { $0.str == id.str }) { r.append(["op": "task.done", "id": id, "done": true]) }
            return r
        case "board.add": return id.isNull ? [] : [["op": "board.remove", "id": id]]
        case "board.update", "board.move": guard let b = find("board") else { return [] }
            return [["op": "board.update", "id": id, "title": b["t"], "due": b["due"].isNull ? .string("") : b["due"], "note": b["note"].isNull ? .string("") : b["note"], "column": b["c"]]]
        case "board.remove": guard let b = find("board") else { return [] }
            return [["op": "board.add", "id": id, "title": b["t"], "column": b["c"], "due": b["due"], "note": b["note"], "created": b["created"]]]
        case "saved.add": return id.isNull ? [] : [["op": "saved.remove", "id": id]]
        case "saved.update": guard let s = find("saved") else { return [] }
            return [["op": "saved.update", "id": id, "title": s["t"], "url": s["url"], "note": s["n"]]]
        case "saved.remove": guard let s = find("saved") else { return [] }
            return [["op": "saved.add", "id": id, "title": s["t"], "url": s["url"], "note": s["n"], "source": s["s"], "created": s["c"]]]
        case "inbox.done": return [["op": "inbox.done", "id": id, "done": .bool(doc["state"]["inboxDone"].array.contains { $0.str == id.str })]]
        case "inbox.priority": return [["op": "inbox.priority", "id": id, "value": .string(doc["state"]["priority"][id.str].str)]]
        case "inbox.snooze": return [["op": "inbox.snooze", "id": id, "on": .bool(!doc["state"]["snooze"][id.str].isNull)]]
        case "progress.set": return [["op": "state.set", "path": .string("progress." + id.str), "value": doc["state"]["progress"][id.str]]]
        case "timetable.set": return [["op": "timetable.set", "text": doc["state"]["timetable"]]]
        case "draft.email", "draft.remove": return [["op": "content.set", "path": "drafts", "value": doc["content"]["drafts"]]]
        case "message.add": return id.isNull ? [] : [["op": "message.dismiss", "id": id]]
        case "content.set", "content.merge", "content.push", "content.upsert", "content.remove":
            return [["op": "content.set", "path": op["path"], "value": doc["content"].at(op["path"].str)]]
        case "state.set": return [["op": "state.set", "path": op["path"], "value": doc["state"].at(op["path"].str)]]
        case "profile.set": var v = JSON.object([:]); for k in op["value"].object.keys { v[k] = doc["profile"][k].isNull ? .string("") : doc["profile"][k] }; return [["op": "profile.set", "value": v]]
        case "settings.set": var v = JSON.object([:]); for k in op["value"].object.keys { v[k] = doc["settings"][k].isNull ? .string("") : doc["settings"][k] }; return [["op": "settings.set", "value": v]]
        default: return []
        }
    }

    // MARK: duplicates (same rules as the server's _core.mjs)
    private static let stopWords: Set<String> = ["the", "a", "an", "and", "of", "for", "to", "in", "on", "at", "with", "re", "fwd", "fw"]
    static func words(_ s: String) -> Set<String> {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return Set(folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init).filter { !stopWords.contains($0) })
    }
    /// Nearly the same title: at least three quarters of the words in common, ignoring case, punctuation and order.
    static func alike(_ a: String, _ b: String) -> Bool {
        let x = words(a), y = words(b)
        if x.isEmpty || y.isEmpty { return false }
        return Double(x.intersection(y).count) / Double(x.union(y).count) >= 0.75
    }
    /// Visible events that look like copies of each other (same day, nearly the same title, within 90 minutes).
    /// The copy to keep comes first: one with a time beats an all-day one.
    static func duplicateEvents(_ doc: JSON) -> [[Event]] {
        let list = doc["content"]["events"].array.filter { !$0["id"].isNull }.map(Event.init).filter(\.active)
        func minutes(_ s: String) -> Int? {
            guard let r = s.range(of: #"T\d\d:\d\d"#, options: .regularExpression) else { return nil }
            let t = s[r].dropFirst()
            return (Int(t.prefix(2)) ?? 0) * 60 + (Int(t.suffix(2)) ?? 0)
        }
        var used = Set<Int>(), out: [[Event]] = []
        for (i, a) in list.enumerated() where !used.contains(i) {
            var g = [a]
            for (j, b) in list.enumerated() where j > i && !used.contains(j) && a.id != b.id && a.start.prefix(10) == b.start.prefix(10) && alike(a.title, b.title) {
                if let x = minutes(a.start), let y = minutes(b.start), abs(x - y) > 90 { continue }
                g.append(b); used.insert(j)
            }
            if g.count > 1 { out.append(g.sorted { ($0.timed ? 1 : 0) > ($1.timed ? 1 : 0) }) }
        }
        return out
    }

    /// Gives add-ops a stable id up front so they can be undone and synced.
    static func prepared(_ op: JSON) -> JSON {
        var o = op
        if o["opId"].isNull { o["opId"] = .string(uid("op")) }
        if o["at"].isNull { o["at"] = .now }
        let name = o["op"].str
        if ["task.add", "board.add", "saved.add", "message.add", "focus.log"].contains(name), o["id"].isNull {
            o["id"] = .string(uid(String(name.split(separator: ".")[0])))
        }
        return o
    }

    static let allOps = ["task.add", "task.update", "task.done", "task.remove", "board.add", "board.update", "board.move", "board.remove",
                         "saved.add", "saved.update", "saved.remove", "inbox.done", "inbox.priority", "inbox.snooze", "progress.set",
                         "focus.log", "timetable.set", "draft.review", "draft.email", "draft.remove", "message.add", "message.dismiss",
                         "content.set", "content.merge", "content.push", "content.upsert", "content.put", "content.remove", "state.set", "state.setKey",
                         "focus.remove", "profile.set", "settings.set"]
}
