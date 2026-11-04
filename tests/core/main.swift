import Foundation

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/London")!
cal.locale = Locale(identifier: "en_GB")
let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "EEE d MMM HH:mm"
// Wednesday 4 Nov 2026, 15:20
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15, minute: 20))!
let physics = UUID(), maths = UUID(), chem = UUID()
let subjects = [QuickAddParser.SubjectRef(id: physics, name: "Physics"), .init(id: maths, name: "Maths"), .init(id: chem, name: "Chemistry")]
let p = QuickAddParser(subjects: subjects, now: now, calendar: cal)
var failures = 0
func check(_ ok: Bool, _ msg: String) { if !ok { failures += 1; print("FAIL:", msg) } }
for line in ["physics worksheet ch 3 due fri 2h", "Maths test next mon !!", "chem lab report chapters 4-6 by 13 nov 5pm 90m",
             "revise bio unit 2 tomorrow", "essay due 20/11", "phys exam in 2 weeks urgent", "read ch 7 tonight 45 min", "worksheet due 5pm",
             "maths homework thu 9am 1h30", "Chemistry quiz this fri"] {
    let r = p.parse(line)
    print("\(line)\n   → '\(r.title)' kind=\(r.kind) subject=\(r.subjectName ?? "-") ch=\(r.chapters) due=\(r.due.map { f.string(from: $0) } ?? "-") h=\(r.hours.map { String(format: "%.2f", $0) } ?? "-") prio=\(r.priority ?? "-")")
}
let a = p.parse("physics worksheet ch 3 due fri 2h")
check(a.subjectID == physics && a.chapters == [3] && a.hours == 2 && a.title == "Physics worksheet", "basic parse")
check(a.due.map { f.string(from: $0) } == "Fri 6 Nov 08:00", "fri due")
let b = p.parse("chem lab report chapters 4-6 by 13 nov 5pm 90m")
check(b.chapters == [4, 5, 6] && b.kind == "project" && b.hours == 1.5 && b.subjectID == chem, "range parse")
check(b.due.map { f.string(from: $0) } == "Fri 13 Nov 17:00", "date+time")
check(p.parse("Maths test next mon !!").due.map { f.string(from: $0) } == "Mon 16 Nov 08:00", "next mon")
check(p.parse("maths homework thu 9am 1h30").hours == 1.5, "1h30")
check(p.parse("essay due 20/11").due.map { f.string(from: $0) } == "Fri 20 Nov 08:00", "dd/mm")

// FSRS
let fs = FSRS(retention: 0.9)
var m = FSRS.Memory()
let p0 = fs.preview(m, now: now)
print("new card:", Rating.allCases.map { "\($0.label)=\(FSRS.shortInterval(p0[$0]!.due.timeIntervalSince(now)))" }.joined(separator: " "))
m = fs.review(m, .good, now: now)
var t = m.due
for i in 0..<5 {
    let pv = fs.preview(m, now: t)
    print("review \(i + 1) S=\(String(format: "%.2f", m.stability)) D=\(String(format: "%.2f", m.difficulty)):", Rating.allCases.map { "\($0.label)=\(FSRS.shortInterval(pv[$0]!.due.timeIntervalSince(t)))" }.joined(separator: " "))
    check(pv[.hard]!.due <= pv[.good]!.due && pv[.good]!.due < pv[.easy]!.due, "ordering")
    m = fs.review(m, .good, now: t); t = m.due
}
let lapsed = fs.review(m, .again, now: t)
check(lapsed.state == "relearning" && lapsed.lapses == 1 && lapsed.stability < m.stability, "lapse")
let relearnGood = fs.review(lapsed, .good, now: t.addingTimeInterval(120))
print("after lapse+good:", FSRS.shortInterval(relearnGood.due.timeIntervalSince(t)), "S=", relearnGood.stability)

// Planner
let hw = AutoPlanner.Task(id: UUID(), title: "Physics worksheet", subjectID: physics, subjectName: "Physics", kind: "homework",
                          due: cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 8))!, remainingMinutes: 120, priority: "medium")
let exam = AutoPlanner.Task(id: UUID(), title: "Maths exam", subjectID: maths, subjectName: "Maths", kind: "exam",
                            due: cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9))!, remainingMinutes: 360, priority: "high")
let proj = AutoPlanner.Task(id: UUID(), title: "Chem project", subjectID: chem, subjectName: "Chemistry", kind: "project",
                            due: cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!, remainingMinutes: 300, priority: "low")
var windows: [AutoPlanner.Window] = []
for wd in 1...5 { windows.append(.init(weekday: wd, start: 16 * 60, end: 21 * 60, free: true)) }
windows.append(.init(weekday: 6, start: 10 * 60, end: 17 * 60, free: true))
windows.append(.init(weekday: 0, start: 10 * 60, end: 17 * 60, free: true))
windows.append(.init(weekday: 3, start: 18 * 60, end: 19 * 60, free: false))   // Wednesday club
let dinner = AutoPlanner.Interval(start: cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 18))!, end: cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 19))!)
var prefs = AutoPlanner.Prefs(); prefs.maxMinutesPerDay = 180; prefs.noStudyDays = [6]
let planner = AutoPlanner(now: now, days: 14, tasks: [hw, exam, proj], windows: windows, busy: [dinner], keep: [], prefs: prefs,
                          reviewDeck: (id: UUID(), subjectID: nil, dueNow: 24, total: 80), calendar: cal)
let out = planner.plan()
var perDay: [String: Int] = [:]
for d in out.drafts {
    let name = d.assignmentID == hw.id ? "HW" : d.assignmentID == exam.id ? "EXAM" : d.assignmentID == proj.id ? "PROJ" : "REVIEW"
    print(f.string(from: d.start), "–", f.string(from: d.end).suffix(5), d.kind, name, "·", d.goal, "|", d.reason)
    let key = String(f.string(from: d.start).prefix(9)); perDay[key, default: 0] += Int(d.end.timeIntervalSince(d.start) / 60)
    check(d.start >= now, "not in the past")
    check(!(d.start < dinner.end && d.end > dinner.start), "no overlap with busy")
    let wd = cal.component(.weekday, from: d.start) - 1
    check(wd != 6, "no saturday")
    if let id = d.assignmentID, let t = [hw, exam, proj].first(where: { $0.id == id }) { check(d.end <= t.due!, "before due") }
}
for (k, v) in perDay { check(v <= 180, "daily max \(k) \(v)") }
for i in 1..<out.drafts.count { check(out.drafts[i].start >= out.drafts[i - 1].end, "no overlaps between drafts") }
print("warnings:", out.warnings)
let hwMinutes = out.drafts.filter { $0.assignmentID == hw.id }.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
check(hwMinutes >= 120, "homework fully planned (\(hwMinutes))")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURES")
