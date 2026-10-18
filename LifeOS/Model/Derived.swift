import Foundation

/// Everything the screens compute from the document: your day, countdowns, coverage, streaks.
extension Store {
    var content: JSON { doc["content"] }
    var state: JSON { doc["state"] }
    var profileName: String { doc["profile"]["name"].str }
    var assistantName: String { doc["profile"]["assistant"]["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "your assistant" }
    var assistantAddress: String { doc["profile"]["assistant"]["imessage"].str }
    /// Where "Send via assistant" emails go: the assistant's email, or its iMessage address if that is an email.
    var assistantEmail: String {
        let e = doc["profile"]["assistant"]["email"].str.trimmingCharacters(in: .whitespaces)
        if !e.isEmpty { return e }
        return assistantAddress.contains("@") ? assistantAddress : ""
    }

    // MARK: time
    var tz: TimeZone { TimeZone(identifier: doc["profile"]["timezone"].str) ?? .current }
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = tz; c.locale = Locale(identifier: "en_IN"); return c }
    func dayKey(_ d: Date = Date()) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    var today: String { dayKey() }
    func date(_ day: String, minutes: Int = 0) -> Date {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        let start = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? Date()
        return start.addingTimeInterval(Double(minutes) * 60)
    }
    func addDays(_ day: String, _ n: Int) -> String { dayKey(cal.date(byAdding: .day, value: n, to: date(day, minutes: 720)) ?? Date()) }
    func dayDiff(_ a: String, _ b: String) -> Int { Int(((date(a, minutes: 720).timeIntervalSince(date(b, minutes: 720))) / 86400).rounded()) }
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    static let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    func parse(_ s: String) -> Date? {
        if s.count == 10 { return date(s) }
        return Store.iso.date(from: s) ?? Store.isoFrac.date(from: s)
    }
    func fmt(_ d: Date, _ style: Date.FormatStyle) -> String { d.formatted(style.locale(Locale(identifier: "en_IN"))) }
    func time(_ d: Date) -> String {
        var f = Date.FormatStyle(date: .omitted, time: .shortened); f.timeZone = tz
        return d.formatted(f).lowercased().replacingOccurrences(of: " ", with: "\u{202F}")
    }
    func dayLabel(_ day: String, long: Bool = true) -> String {
        var f = Date.FormatStyle().weekday(long ? .wide : .abbreviated).day().month(long ? .wide : .abbreviated); f.timeZone = tz
        return date(day, minutes: 720).formatted(f)
    }
    func relDay(_ day: String) -> String {
        let n = dayDiff(day, today)
        if n == 0 { return "Today" }; if n == 1 { return "Tomorrow" }; if n == -1 { return "Yesterday" }
        if n > 1 && n < 7 { var f = Date.FormatStyle().weekday(.wide); f.timeZone = tz; return date(day, minutes: 720).formatted(f) }
        return dayLabel(day, long: false)
    }
    func duration(_ secs: TimeInterval) -> String {
        let t = max(0, Int(secs)), d = t / 86400, h = t % 86400 / 3600, m = t % 3600 / 60
        if d > 0 { return "\(d)d \(h)h" }; if h > 0 { return "\(h)h \(m)m" }; return "\(max(1, m))m"
    }
    func ago(_ ms: Double) -> String {
        let m = (Date().timeIntervalSince1970 * 1000 - ms) / 60000
        if m < 1 { return "just now" }; if m < 60 { return "\(Int(m))m ago" }; if m < 2880 { return "\(Int(m / 60))h ago" }; return "\(Int(m / 1440))d ago"
    }
    func checked(_ iso: String) -> (label: String, stale: Bool) {
        guard let d = parse(iso) else { return ("Check time not recorded", true) }
        let h = Date().timeIntervalSince(d) / 3600
        return ("Checked " + dayLabel(dayKey(d), long: false) + ", " + time(d) + " · " + ago(d.timeIntervalSince1970 * 1000), h > 12)
    }

    // MARK: tasks & board
    var tasks: [TaskItem] { state["tasks"].array.map(TaskItem.init) }
    func isDone(_ id: String) -> Bool { state["done"].array.contains { $0.str == id } }
    var openTasks: [TaskItem] { tasks.filter { !isDone($0.id) } }
    var doneTasks: [TaskItem] { tasks.filter { isDone($0.id) } }
    var cards: [Card] { state["board"].array.map(Card.init) }
    func cards(in column: Int) -> [Card] { cards.filter { $0.column == column }.sorted { ($0.due ?? "9") < ($1.due ?? "9") } }
    enum Due { case none, overdue, soon, later }
    func dueState(_ due: String?, column: Int = 0) -> Due {
        guard let due, due.count == 10, column != 2 else { return .none }
        let d = dayDiff(due, today)
        return d <= 0 ? .overdue : d <= 2 ? .soon : .later
    }
    func dueText(_ due: String?) -> String {
        guard let due, due.count == 10 else { return "" }
        return due < today ? "Overdue · " + relDay(due) : "Due " + relDay(due).lowercased()
    }
    var saved: [SavedItem] { state["saved"].array.map(SavedItem.init) }

    // MARK: calendar
    var events: [Event] { content["events"].array.map(Event.init).filter(\.active).sorted { (parse($0.start) ?? .distantFuture) < (parse($1.start) ?? .distantFuture) } }
    var allEvents: [Event] { content["events"].array.map(Event.init) }
    func start(_ e: Event) -> Date { parse(e.start) ?? Date() }
    func end(_ e: Event) -> Date {
        if let s = e.end, let d = parse(s) { return s.count == 10 ? d.addingTimeInterval(86400) : d }
        return e.timed ? start(e).addingTimeInterval(3600) : date(e.start).addingTimeInterval(86400)
    }
    func day(_ e: Event) -> String { e.timed ? dayKey(start(e)) : e.start }
    var upcoming: [Event] { events.filter { end($0) > Date() } }

    // MARK: inbox
    var mail: [Mail] { content["inbox"].array.map(Mail.init) }
    func inboxDone(_ id: String) -> Bool { state["inboxDone"].array.contains { $0.str == id } }
    func priority(_ m: Mail) -> String { state["priority"][m.id].string ?? m.priority }
    func snoozed(_ id: String) -> Bool { !state["snooze"][id].isNull }
    var inboxTodo: [Mail] { mail.filter { !inboxDone($0.id) && !snoozed($0.id) } }
    func replyDraft(for m: Mail) -> Draft? { drafts.first { $0.isEmail && $0.inboxId == m.id } }

    // MARK: feed
    var feed: [FeedItem] {
        let items = content["feed"].array.enumerated().map { FeedItem($0.element, index: $0.offset) }
        let now = Date()
        func stamp(_ f: FeedItem) -> Date? { parse(f.publishedAt) }
        func score(_ f: FeedItem) -> Double {
            let age = stamp(f).map { max(0, now.timeIntervalSince($0) / 86400) } ?? 14
            let rel = f.importance.map { min(5, max(0, $0)) } ?? (f.isMusic ? 4 : f.category.lowercased().contains("study") || f.category.lowercased().contains("exam") ? 3 : 1)
            return (f.pinned ? 100 : 0) + rel * exp(-age / 3)
        }
        return items.sorted { score($0) > score($1) }
    }

    // MARK: timetable (YYYY-MM-DD headers, then "7:00-13:00 Title" lines)
    struct TTBlock { var a: Int; var b: Int?; var t: String }
    static func ttMinutes(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        var ap = ""; var body = s
        if s.hasSuffix("am") || s.hasSuffix("pm") { ap = String(s.suffix(2)); body = String(s.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        let p = body.split(separator: ":")
        guard let h0 = Int(p.first ?? ""), p.count <= 2 else { return nil }
        let mi = p.count == 2 ? Int(p[1]) ?? -1 : 0
        var h = h0
        if !ap.isEmpty { if h < 1 || h > 12 { return nil }; h = h % 12 + (ap == "pm" ? 12 : 0) }
        if h > 24 || mi < 0 || mi > 59 { return nil }
        return h * 60 + mi
    }
    static func ttParse(_ text: String) -> (days: [String: [TTBlock]], order: [String], bad: [Int]) {
        var days: [String: [TTBlock]] = [:], order: [String] = [], bad: [Int] = []; var cur: String?
        let lineRe = try! NSRegularExpression(pattern: #"^(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)(?:\s*[-–—]\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?))?\s+(.+)$"#, options: [.caseInsensitive])
        for (i, raw) in text.components(separatedBy: .newlines).enumerated() {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { continue }
            if l.count <= 24, l.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil || (l.range(of: #"^\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression) != nil && l.range(of: #"^\d{4}-\d{2}-\d{2}\s*[-–]\s*\d"#, options: .regularExpression) == nil && l.count <= 24) {
                let d = String(l.prefix(10)); cur = d; if days[d] == nil { days[d] = []; order.append(d) }; continue
            }
            let ns = l as NSString
            guard let cur, let m = lineRe.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { bad.append(i + 1); continue }
            let a = ttMinutes(ns.substring(with: m.range(at: 1)))
            let b = m.range(at: 2).location != NSNotFound ? ttMinutes(ns.substring(with: m.range(at: 2))) : nil
            if a == nil || (m.range(at: 2).location != NSNotFound && b == nil) { bad.append(i + 1); continue }
            days[cur, default: []].append(TTBlock(a: a!, b: b, t: ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)))
        }
        return (days, order, bad)
    }
    var timetableDays: [String: [TTBlock]] {
        var base = Store.ttParse(content["timetable"].str).days
        for (k, v) in Store.ttParse(state["timetable"].str).days { base[k] = v }
        return base
    }
    static func ttText(_ days: [String: [TTBlock]]) -> String {
        func h24(_ m: Int) -> String { String(format: "%d:%02d", (m % 1440) / 60, m % 60) }
        return days.keys.sorted().map { d in
            d + "\n" + days[d]!.sorted { $0.a < $1.a }.map { ($0.b != nil ? h24($0.a) + "-" + h24($0.b!) : h24($0.a)) + " " + $0.t }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
    var timetableBlocks: [Block] {
        var out: [Block] = []
        for (day, list) in timetableDays {
            let l = list.sorted { $0.a < $1.a }
            for (i, e) in l.enumerated() {
                var end = e.b ?? (i + 1 < l.count ? l[i + 1].a : e.a + 60)
                if end <= e.a && e.b != nil { end += 1440 }
                out.append(Block(id: "tt-\(day)-\(e.a)-\(e.t)", day: day, title: e.t, start: date(day, minutes: e.a), end: date(day, minutes: end), kind: .timetable, detail: ""))
            }
        }
        return out.sorted { $0.start < $1.start }
    }
    var studyBlocks: [Block] {
        let st = content["study"]
        func m(_ s: String) -> Int? { let p = s.split(separator: ":"); guard p.count == 2, let h = Int(p[0]), let mi = Int(p[1]) else { return nil }; return h * 60 + mi }
        return st["blocks"].array.compactMap { b in
            let day = b["date"].string ?? st["date"].str
            guard let a = m(b["start"].str), let z = m(b["end"].str), day.count == 10 else { return nil }
            let rest = b["title"].str.lowercased().hasPrefix("lunch") || b["title"].str.lowercased().hasPrefix("dinner") || b["title"].str.lowercased().hasPrefix("break") || b["title"].str.lowercased().hasPrefix("nap")
            return Block(id: "st-" + b["id"].str + day + b["start"].str, day: day, title: b["title"].str, start: date(day, minutes: a), end: date(day, minutes: z), kind: rest ? .rest : .study, detail: b["status"].str)
        }
    }
    /// Timetable, study plan and timed calendar events on one line.
    var timeline: [Block] {
        let calBlocks = events.filter(\.timed).map { Block(id: "ev-" + $0.id, day: day($0), title: $0.title, start: start($0), end: end($0), kind: .calendar, detail: $0.note) }
        var seen = Set<String>()
        return (timetableBlocks + studyBlocks + calBlocks).sorted { $0.start < $1.start }.filter { seen.insert($0.title.lowercased() + "\($0.start.timeIntervalSince1970)").inserted }
    }
    func blocks(on day: String) -> [Block] { timeline.filter { $0.day == day } }
    var now: (current: Block?, next: Block?) {
        let n = Date(), l = timeline
        let cur = l.filter { $0.start <= n && n < $0.end }.sorted { ($0.kind == .calendar ? 1 : 0, -$0.start.timeIntervalSince1970) < ($1.kind == .calendar ? 1 : 0, -$1.start.timeIntervalSince1970) }.first
        return (cur, l.first { $0.start > n })
    }

    // MARK: countdown to the next exam or deadline
    var bigThing: Event? {
        let list = (events + content["milestones"].array.map { Event(["title": $0["title"], "start": $0["start"]]) })
            .filter { let t = $0.title.lowercased(); return ["exam", "tallentex", "board", "test", "deadline", "launch"].contains { t.contains($0) } && !["prep", "class", "review", "mock", "tuition"].contains { t.contains($0) } }
            .filter { $0.timed ? start($0) > Date() : $0.start >= today }
            .sorted { start($0) < start($1) }
        guard let first = list.first else { return nil }
        return list.first { $0.timed && day($0) == first.start } ?? first
    }
    func countdown(_ e: Event) -> (value: String, unit: String, sub: String) {
        let d = dayDiff(day(e), today)
        let sub = dayLabel(day(e), long: false) + (e.timed ? ", " + time(start(e)) : "")
        if d >= 1 { return ("\(d)", d == 1 ? "day" : "days", sub) }
        return (duration(start(e).timeIntervalSinceNow), "", "Today" + (e.timed ? ", " + time(start(e)) : ""))
    }

    // MARK: coverage checklists
    static func hash(_ s: String) -> String {
        var h: UInt32 = 2166136261
        for u in s.unicodeScalars {
            let code = u.value > 0xFFFF ? 0xD800 + ((u.value - 0x10000) >> 10) : u.value
            h = (h ^ code) &* 16777619
        }
        return String(h, radix: 36)
    }
    var coverage: [CoverageSet] {
        let p = content["examPrep"]; var sets: [CoverageSet] = []
        func add(_ g: String, _ n: String, _ l: [JSON]) { if !l.isEmpty { sets.append(CoverageSet(group: g, name: n, items: l.map { CoverageItem(id: "cov_" + Store.hash(n + "|" + $0.str), text: $0.str) })) } }
        for (n, k) in [("Maths", "mathsIndex"), ("English", "englishIndex"), ("Physics", "physicsIndex"), ("History and civics", "historyIndex"), ("Geography", "geoIndex")] { add("School coverage", n, p[k].array) }
        for (n, l) in p["tallentexUnits"].object.sorted(by: { $0.key < $1.key }) { add("TALLENTEX coverage", n, l.array) }
        for s in content["coverage"].array { add(s["group"].string ?? "Coverage", s["name"].str, s["items"].array) }
        return sets
    }
    func marked(_ id: String) -> Bool { state["progress"][id]["done"].bool }
    func doneCount(_ s: CoverageSet) -> Int { s.items.filter { marked($0.id) }.count }
    static func clean(_ t: String) -> String {
        var s = t; for p in ["🟢", "🟡", "🔴", "✅", "⚪"] where s.hasPrefix(p) { s = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespaces) }
        return s
    }

    // MARK: focus & streak
    func focusMinutes(_ day: String) -> Int { state["focus"].array.filter { $0["date"].str == day }.reduce(0) { $0 + ($1["minutes"].int ?? 0) } }
    var streak: Int {
        let days = Set(content["streak"]["days"].array.map(\.str) + state["focus"].array.filter { ($0["minutes"].int ?? 0) >= 20 }.map { $0["date"].str })
        var d = today; if !days.contains(d) { d = addDays(d, -1) }
        var n = 0; while days.contains(d) { n += 1; d = addDays(d, -1) }
        return n
    }

    // MARK: drafts
    var drafts: [Draft] { content["drafts"].array.map(Draft.init).filter { !$0.hidden } }
    func review(_ d: Draft, _ v: Int, _ week: String, _ action: String = "approve") -> JSON? {
        let r = state["draftReviews"][[d.id, String(v), week, action].joined(separator: "|")]; return r.isNull ? nil : r
    }
    var pendingDrafts: [Draft] {
        drafts.filter { d in d.id != "delivery-test" && d.parts.contains { review(d, d.latest?.version ?? 1, $0.id) == nil } }
    }

    // MARK: study plan "right now"
    var studyNow: (title: String, time: String, note: String) {
        let st = content["study"], L = content["studyLabels"]
        let n = Date(), c = cal.dateComponents([.hour, .minute], from: n), mins = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        func m(_ s: String) -> Int { let p = s.split(separator: ":"); return (Int(p.first ?? "") ?? 0) * 60 + (Int(p.last ?? "") ?? 0) }
        if today != st["date"].str { return (L["noBlock"].string ?? "No study block published for today", L["savedPlan"].str, L["freshPlan"].str) }
        let blocks = st["blocks"].array.filter { !$0["start"].str.isEmpty }
        if let a = blocks.first(where: { mins >= m($0["start"].str) && mins < m($0["end"].str) }) { return (a["title"].str, a["time"].str, L["scheduled"].str) }
        if let x = blocks.first(where: { m($0["start"].str) > mins }) { return ("Next: " + x["title"].str, x["time"].str, L["between"].str) }
        return (L["ended"].string ?? "Done for today", L["nextMorning"].str, L["noAssumption"].str)
    }

    // MARK: greeting & assistant pulse
    var greeting: String {
        let g = content["greeting"], h = cal.component(.hour, from: Date())
        if g["context"]["date"].str == today, !g["context"]["lines"].array.isEmpty {
            let lines = g["context"]["lines"].array; return lines[Int(Date().timeIntervalSince1970 / 3600) % lines.count].str
        }
        let k = (h >= 21 || h < 5) ? "night" : h < 12 ? "morning" : h < 17 ? "afternoon" : "evening"
        if let s = g[k].string { return s }
        let name = profileName.isEmpty ? "" : ", " + profileName
        return ["morning": "Good morning", "afternoon": "Good afternoon", "evening": "Good evening", "night": "Good night"][k]! + name
    }
    var pulse: JSON { content["pulse"] }
    var messages: [JSON] { state["messages"].array }
}
