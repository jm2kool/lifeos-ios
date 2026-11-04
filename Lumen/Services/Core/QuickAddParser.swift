import Foundation

/// Reads a line like "physics worksheet ch 3 due fri 2h" into the parts of an assignment.
/// Plain rules, no AI, so it's instant and works offline. Anything it doesn't recognise stays in the title.
struct QuickAddParser {
    struct SubjectRef { var id: UUID; var name: String }

    struct Result: Equatable {
        var title: String = ""
        var kind: String = "homework"          // homework | project | test | exam | revision
        var kindFound = false
        var subjectID: UUID?
        var subjectName: String?
        var chapters: [Int] = []
        var due: Date?
        var hours: Double?
        var priority: String?                  // low | medium | high | urgent
    }

    var subjects: [SubjectRef]
    var now: Date = Date()
    var calendar: Calendar = .current
    /// When a day is given without a time, work is due at the start of that day's school day.
    var defaultDueHour = 8
    var dayFirst = true

    init(subjects: [SubjectRef], now: Date = Date(), calendar: Calendar = .current) {
        self.subjects = subjects
        self.now = now
        self.calendar = calendar
        self.dayFirst = (calendar.locale ?? Locale.current).identifier.hasSuffix("_US") == false
    }

    private static let weekdays: [(names: [String], number: Int)] = [
        (["sunday", "sun"], 1), (["monday", "mon"], 2), (["tuesday", "tues", "tue"], 3), (["wednesday", "weds", "wed"], 4),
        (["thursday", "thurs", "thur", "thu"], 5), (["friday", "fri"], 6), (["saturday", "sat"], 7),
    ]
    private static let months: [(names: [String], number: Int)] = [
        (["january", "jan"], 1), (["february", "feb"], 2), (["march", "mar"], 3), (["april", "apr"], 4), (["may"], 5),
        (["june", "jun"], 6), (["july", "jul"], 7), (["august", "aug"], 8), (["september", "sept", "sep"], 9),
        (["october", "oct"], 10), (["november", "nov"], 11), (["december", "dec"], 12),
    ]
    private static let kindWords: [(words: [String], kind: String)] = [
        (["final exam", "finals", "exam", "exams", "mock", "mocks", "gcse", "a-level"], "exam"),
        (["midterm", "test", "quiz", "assessment"], "test"),
        (["project", "presentation", "lab report", "report", "coursework", "portfolio"], "project"),
        (["revision", "revise", "review", "study"], "revision"),
        (["homework", "hw", "worksheet", "assignment", "problems", "problem set", "pset", "exercises", "essay", "questions", "reading"], "homework"),
    ]
    private static let subjectShorthand: [String: [String]] = [
        "phys": ["physics"], "chem": ["chemistry"], "bio": ["biology"], "math": ["maths", "mathematics", "math"],
        "maths": ["maths", "mathematics", "math"], "eng": ["english"], "lit": ["literature", "english literature"],
        "hist": ["history"], "geo": ["geography"], "geog": ["geography"], "cs": ["computer science", "computing"],
        "compsci": ["computer science", "computing"], "econ": ["economics"], "psych": ["psychology"], "pe": ["physical education", "pe"],
        "re": ["religious studies", "re"], "fr": ["french"], "es": ["spanish"], "de": ["german"], "bus": ["business"],
        "ict": ["computing", "ict"], "dt": ["design and technology", "design technology"], "art": ["art"], "music": ["music"],
    ]

    func parse(_ input: String) -> Result {
        var r = Result()
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = original
        var lower = text.lowercased()

        /// Removes a matched range from both copies so later rules don't see it and it leaves the title.
        func cut(_ range: NSRange) {
            guard let rr = Range(range, in: text) else { return }
            text.replaceSubrange(rr, with: " ")
            lower = text.lowercased()
        }
        func match(_ pattern: String) -> NSTextCheckingResult? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower))
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            guard i < m.numberOfRanges, m.range(at: i).location != NSNotFound, let rr = Range(m.range(at: i), in: lower) else { return nil }
            return String(lower[rr])
        }

        // Estimate: "2h", "1.5 hrs", "90m", "1h30", "1h 30m", "45 min"
        if let m = match(#"\b(\d+(?:[.,]\d+)?)\s*(?:h|hr|hrs|hour|hours)\s*(?:(\d{1,2})\s*(?:m|min|mins|minutes)?)?\b"#) {
            let h = Double(group(m, 1)?.replacingOccurrences(of: ",", with: ".") ?? "") ?? 0
            let extra = Double(group(m, 2) ?? "") ?? 0
            r.hours = h + extra / 60
            cut(m.range)
        } else if let m = match(#"\b(\d{1,3})\s*(?:m|min|mins|minutes)\b"#) {
            r.hours = (Double(group(m, 1) ?? "") ?? 0) / 60
            cut(m.range)
        }

        // Priority
        if let m = match(#"(?:^|\s)(!{1,3})(?=\s|$)"#) {
            let n = group(m, 1)?.count ?? 1
            r.priority = n >= 3 ? "urgent" : n == 2 ? "high" : "medium"
            cut(m.range)
        } else if let m = match(#"\b(urgent|asap|high priority|important|low priority|p1|p2|p3)\b"#) {
            switch group(m, 1) ?? "" {
            case "urgent", "asap", "p1": r.priority = "urgent"
            case "high priority", "important", "p2": r.priority = "high"
            case "p3": r.priority = "medium"
            default: r.priority = "low"
            }
            cut(m.range)
        }

        // Chapters: "ch 3", "chapter 3-5", "ch 3, 4 & 6", "chs 2 and 3"
        if let m = match(#"\b(?:ch|chs|chap|chaps|chapter|chapters|unit|units)\.?\s*(\d{1,3}(?:\s*(?:-|–|to|,|&|and|\+)\s*\d{1,3})*)\b"#) {
            let spec = group(m, 1) ?? ""
            r.chapters = Self.numbers(in: spec)
            cut(m.range)
        }

        // Due date and time
        let (due, dueRange) = findDue(lower)
        if let due, let dueRange { r.due = due; cut(dueRange) }

        // Kind
        for entry in Self.kindWords {
            if entry.words.contains(where: { lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b", options: .regularExpression) != nil }) {
                r.kind = entry.kind      // the word stays in the title ("Physics worksheet")
                r.kindFound = true
                break
            }
        }

        // Subject: an exact name first (longest first), then a shorthand or a prefix of three letters or more.
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }).map(String.init)
        let sorted = subjects.sorted { $0.name.count > $1.name.count }
        if let s = sorted.first(where: { lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0.name.lowercased()))\\b", options: .regularExpression) != nil }) {
            r.subjectID = s.id; r.subjectName = s.name
        } else {
            outer: for w in words where w.count >= 2 {
                if let names = Self.subjectShorthand[w], let s = subjects.first(where: { names.contains($0.name.lowercased()) }) {
                    r.subjectID = s.id; r.subjectName = s.name; break outer
                }
                if w.count >= 3, let s = subjects.first(where: { $0.name.lowercased().hasPrefix(w) }) {
                    r.subjectID = s.id; r.subjectName = s.name; break outer
                }
            }
        }

        // What's left is the title.
        var title = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;-–·"))
        title = title.replacingOccurrences(of: #"\s+(?:due|by|on|for|at)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let first = title.first { title = first.uppercased() + title.dropFirst() }
        r.title = title.isEmpty ? (r.subjectName.map { "\($0) \(r.kind)" } ?? "New assignment") : title
        return r
    }

    /// "3-5" → [3, 4, 5]; "3, 4 & 6" → [3, 4, 6].
    static func numbers(in spec: String) -> [Int] {
        var out: [Int] = []
        let normal = spec.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: " to ", with: "-")
        for part in normal.components(separatedBy: CharacterSet(charactersIn: ",&+")).flatMap({ $0.components(separatedBy: " and ") }) {
            let bits = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if bits.count == 2, bits[0] <= bits[1], bits[1] - bits[0] < 50 { out += Array(bits[0]...bits[1]) }
            else { out += bits }
        }
        var seen = Set<Int>()
        return out.filter { seen.insert($0).inserted }
    }

    // MARK: Dates

    private func findDue(_ lower: String) -> (Date?, NSRange?) {
        let lead = #"(?:\b(?:due|by|on|for|before)\s+)?"#
        let time = #"(?:\s*(?:at|@)?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?|\s+(noon|midday|midnight|tonight|eod|morning|evening|afternoon))?"#
        let candidates: [String] = [
            lead + #"\b(today|tonight|tomorrow|tmrw|tmr|tomorow)\b"# + time,
            lead + #"\b(?:(next|this)\s+)?(sunday|sun|monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat)\b"# + time,
            lead + #"\bin\s+(\d{1,2})\s+(day|days|week|weeks)\b"#,
            lead + #"\b(next week|end of (?:the )?week|weekend)\b"#,
            lead + #"\b(\d{1,2})(?:st|nd|rd|th)?\s+(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\b"# + time,
            lead + #"\b(january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec)\s+(\d{1,2})(?:st|nd|rd|th)?\b"# + time,
            lead + #"\b(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?\b"# + time,
            #"\b(?:due|by|at)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#,
        ]
        let today = calendar.startOfDay(for: now)
        for (index, pattern) in candidates.enumerated() {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) else { continue }
            func g(_ i: Int) -> String? {
                guard i < m.numberOfRanges, m.range(at: i).location != NSNotFound, let rr = Range(m.range(at: i), in: lower) else { return nil }
                return String(lower[rr])
            }
            var day: Date?
            var timeStart = 0
            switch index {
            case 0:
                let w = g(1) ?? ""
                day = (w == "today" || w == "tonight") ? today : calendar.date(byAdding: .day, value: 1, to: today)
                if w == "tonight", g(2) == nil, g(5) == nil {
                    return (calendar.date(bySettingHour: 21, minute: 0, second: 0, of: today), m.range)
                }
                timeStart = 2
            case 1:
                let modifier = g(1)
                let name = g(2) ?? ""
                guard let target = Self.weekdays.first(where: { $0.names.contains(name) })?.number else { continue }
                let current = calendar.component(.weekday, from: today)
                var ahead = (target - current + 7) % 7
                if ahead == 0 { ahead = modifier == "this" ? 0 : 7 }
                if modifier == "next" && ahead < 7 { ahead += 7 }   // "next fri" is the Friday of next week
                day = calendar.date(byAdding: .day, value: ahead, to: today)
                timeStart = 3
            case 2:
                let n = Int(g(1) ?? "") ?? 1
                let unit = g(2) ?? "days"
                day = calendar.date(byAdding: .day, value: unit.hasPrefix("week") ? n * 7 : n, to: today)
            case 3:
                let phrase = g(1) ?? ""
                let current = calendar.component(.weekday, from: today)
                if phrase == "next week" {
                    day = calendar.date(byAdding: .day, value: (2 - current + 7) % 7 == 0 ? 7 : (2 - current + 7) % 7, to: today)
                } else if phrase == "weekend" {
                    day = calendar.date(byAdding: .day, value: (7 - current + 7) % 7, to: today)
                } else {
                    day = calendar.date(byAdding: .day, value: (6 - current + 7) % 7, to: today)
                }
            case 4, 5:
                let dayNum = Int(index == 4 ? g(1) ?? "" : g(2) ?? "") ?? 1
                let monthName = index == 4 ? g(2) ?? "" : g(1) ?? ""
                guard let month = Self.months.first(where: { $0.names.contains(monthName) })?.number else { continue }
                day = nextDate(month: month, day: dayNum, year: nil)
                timeStart = 3
            case 6:
                let a = Int(g(1) ?? "") ?? 0, b = Int(g(2) ?? "") ?? 0
                var year = g(3).flatMap { Int($0) }
                if let y = year, y < 100 { year = 2000 + y }
                let (dd, mm) = (a > 12 || dayFirst) ? (a, b) : (b, a)
                guard (1...12).contains(mm), (1...31).contains(dd) else { continue }
                day = nextDate(month: mm, day: dd, year: year)
                timeStart = 4
            default:
                // "due 5pm": today, or tomorrow if that time has gone.
                guard var h = Int(g(1) ?? "") else { continue }
                let min = Int(g(2) ?? "") ?? 0
                if g(3) == "pm" && h < 12 { h += 12 }
                if g(3) == "am" && h == 12 { h = 0 }
                var d = calendar.date(bySettingHour: h, minute: min, second: 0, of: today) ?? now
                if d < now { d = calendar.date(byAdding: .day, value: 1, to: d) ?? d }
                return (d, m.range)
            }
            guard let base = day else { continue }
            var hour = defaultDueHour, minute = 0
            if timeStart > 0 {
                if let h = g(timeStart).flatMap({ Int($0) }), h <= 24 {
                    hour = h
                    minute = g(timeStart + 1).flatMap { Int($0) } ?? 0
                    let ampm = g(timeStart + 2)
                    if ampm == "pm" && hour < 12 { hour += 12 }
                    if ampm == "am" && hour == 12 { hour = 0 }
                    if ampm == nil && hour < 7 { hour += 12 }   // "fri 5" means 5pm
                } else if let word = g(timeStart + 3) {
                    switch word {
                    case "noon", "midday": hour = 12
                    case "midnight": hour = 23; minute = 59
                    case "tonight", "evening": hour = 21
                    case "eod": hour = 17
                    case "morning": hour = 9
                    case "afternoon": hour = 15
                    default: break
                    }
                }
            }
            return (calendar.date(bySettingHour: min(23, hour), minute: min(59, minute), second: 0, of: base), m.range)
        }
        return (nil, nil)
    }

    private func nextDate(month: Int, day: Int, year: Int?) -> Date? {
        let thisYear = calendar.component(.year, from: now)
        var c = DateComponents(year: year ?? thisYear, month: month, day: day)
        guard var d = calendar.date(from: c) else { return nil }
        if year == nil, d < calendar.startOfDay(for: now) {
            c.year = thisYear + 1
            d = calendar.date(from: c) ?? d
        }
        return d
    }
}
