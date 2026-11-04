import Foundation
import SwiftData

/// Sample data for simulator screenshots (CI launches with LUMEN_DEMO=1). Never runs in normal use.
///   LUMEN_TAB=today|planner|focus|cards|syllabus   LUMEN_SHEET=settings|proposal|review|outcome|assignment|generate|assistants
///   LUMEN_PLANNER=schedule|assignments|activity     LUMEN_FOCUS=1 starts a focus session
@MainActor
enum Demo {
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var active: Bool { env["LUMEN_DEMO"] != nil }

    static func prepare() {
        guard active else { return }
        Auth.shared.offline = true
        let store = Store.shared
        if store.live(StudySubject.self).isEmpty { seed(store) }
        let router = Router.shared
        if let t = env["LUMEN_TAB"], let tab = AppTab(rawValue: t) { router.tab = tab }
        if let p = env["LUMEN_PLANNER"], let mode = PlannerView.Mode.allCases.first(where: { $0.rawValue.lowercased() == p }) { router.plannerMode = mode }
        if env["LUMEN_FOCUS"] != nil, let b = store.nextBlock {
            FocusTimer.shared.prepare(block: b)
            FocusTimer.shared.start()
        }
        guard let sheet = env["LUMEN_SHEET"] else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            switch sheet {
            case "settings": router.sheet = .settings
            case "proposal": if let p = store.pendingProposal { router.sheet = .proposal(p.id) }
            case "review": router.openReview()
            case "assignment": if let a = store.live(Assignment.self).first(where: { $0.title.hasPrefix("Chemistry") }) { router.sheet = .assignment(a.id) }
            case "generate": router.sheet = .generateCards(nil)
            case "outcome":
                FocusTimer.shared.finished = .init(context: .init(title: "Physics worksheet", subjectID: store.subjects.first?.id, goal: "Questions 1–6 on Newton's laws"),
                                                   start: Date().addingTimeInterval(-3000), end: Date(), minutes: 48)
            default: break
            }
        }
    }

    private static func seed(_ store: Store) {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: h * 60 + m, to: cal.date(byAdding: .day, value: dayOffset, to: today)!)!
        }
        func subject(_ name: String, _ color: String, _ icon: String, _ sort: Int, exam: Date? = nil) -> StudySubject {
            let s = StudySubject(id: UUID()); s.name = name; s.color = color; s.icon = icon; s.sort = sort; s.examAt = exam
            store.insert(s); return s
        }
        let physics = subject("Physics", "#7C8CFF", "atom", 0, exam: at(24, 9))
        let chemistry = subject("Chemistry", "#5BE3A1", "flask", 1)
        let maths = subject("Maths", "#FFB35C", "function", 2, exam: at(6, 9))
        let english = subject("English", "#FF7A9C", "text.book.closed", 3)

        func chapter(_ s: StudySubject, _ n: Int, _ title: String, _ topics: [(String, TopicStatus)], by: Actor = .me) -> Chapter {
            let c = Chapter(id: UUID()); c.subjectID = s.id; c.number = n; c.title = title; c.sort = n
            store.insert(c, by: by)
            for (i, t) in topics.enumerated() {
                let tp = Topic(id: UUID()); tp.subjectID = s.id; tp.chapterID = c.id; tp.title = t.0; tp.status = t.1; tp.sort = i
                store.insert(tp, by: by)
            }
            return c
        }
        let forces = chapter(physics, 3, "Forces", [("Newton's laws", .mastered), ("Friction", .learning), ("Momentum", .revised), ("Terminal velocity", .notStarted)])
        _ = chapter(physics, 4, "Energy", [("Work and power", .revised), ("Kinetic energy", .learning), ("Efficiency", .notStarted)])
        let organic = chapter(chemistry, 5, "Organic chemistry", [("Alkanes", .mastered), ("Alkenes", .revised), ("Alcohols", .learning)], by: .instinct)
        _ = chapter(maths, 2, "Quadratics", [("Factorising", .mastered), ("Completing the square", .learning), ("The formula", .revised)])
        _ = chapter(english, 1, "Macbeth", [("Ambition", .learning), ("Guilt", .notStarted)])

        func assignment(_ title: String, _ kind: AssignmentKind, _ s: StudySubject, due: Date, hours: Double, _ p: Priority = .medium,
                        by: Actor = .me, reason: String? = nil, chapters: [Chapter] = []) -> Assignment {
            let a = Assignment(id: UUID()); a.title = title; a.kind = kind; a.subjectID = s.id; a.dueAt = due; a.estimatedHours = hours
            a.priority = p; a.chapterUUIDs = chapters.map(\.id); a.reason = reason
            store.insert(a, by: by); return a
        }
        let worksheet = assignment("Physics worksheet", .homework, physics, due: at(1, 8), hours: 2, chapters: [forces])
        let lab = assignment("Chemistry lab report", .project, chemistry, due: at(4, 9), hours: 4, .high, by: .instinct,
                             reason: "Added from your teacher's email on Monday.", chapters: [organic])
        let test = assignment("Quadratics test", .test, maths, due: at(6, 9), hours: 3, .high)
        _ = assignment("Macbeth essay", .homework, english, due: at(9, 8), hours: 2.5)
        worksheet.status = .inProgress

        func block(_ start: Date, _ minutes: Int, _ s: StudySubject?, _ a: Assignment?, _ goal: String, _ kind: BlockKind = .study,
                   status: BlockStatus = .planned, by: Actor = .instinct, reason: String? = nil) {
            let b = StudyBlock(id: UUID()); b.startAt = start; b.endAt = start.addingTimeInterval(TimeInterval(minutes * 60))
            b.subjectID = s?.id; b.assignmentID = a?.id; b.goal = goal; b.kind = kind; b.status = status; b.reason = reason
            store.insert(b, by: by)
        }
        let soon = AutoPlanner.roundUp(now.addingTimeInterval(25 * 60), minutes: 5, calendar: cal)
        block(soon.addingTimeInterval(-3 * 3600), 50, physics, worksheet, "Questions 1–6", status: .done)
        block(soon, 50, physics, worksheet, "Questions 7–12 on friction", reason: "Due tomorrow morning; 50 min left.")
        block(soon.addingTimeInterval(3600), 45, chemistry, lab, "Write up the method", reason: "Spread over three days before Friday.")
        block(soon.addingTimeInterval(2 * 3600), 15, physics, nil, "Review 18 due cards", .review)
        block(at(1, 16), 50, maths, test, "Completing the square practice", .revision)
        block(at(1, 17), 45, chemistry, lab, "Results and graphs")
        block(at(2, 16, 30), 50, maths, test, "Past paper Q1–5", .revision, by: .me)

        let busy = BusySlot(id: UUID()); busy.source = "calendar"; busy.startAt = at(0, 18); busy.endAt = at(0, 19)
        store.insert(busy)
        for d in 1...5 {
            let w = AvailabilityWindow(id: UUID()); w.weekday = d; w.startTime = "16:00"; w.endTime = "21:00"
            store.insert(w)
        }

        // Two weeks of focus
        let minutes = [45, 70, 0, 95, 60, 30, 110, 80, 0, 65, 90, 120, 55, 75]
        let subjects = [physics, chemistry, maths, english]
        for (i, m) in minutes.enumerated() where m > 0 {
            let day = 13 - i
            for (j, part) in [m * 6 / 10, m * 4 / 10].enumerated() where part > 0 {
                let s = FocusSession(id: UUID())
                s.startedAt = at(-day, 16 + j); s.endedAt = s.startedAt.addingTimeInterval(TimeInterval(part * 60)); s.minutes = part
                let subj = subjects[(i + j) % subjects.count]
                s.subjectID = subj.id
                s.assignmentID = subj.id == physics.id ? worksheet.id : subj.id == chemistry.id ? lab.id : subj.id == maths.id ? test.id : nil
                s.outcome = .done
                store.insert(s)
            }
        }

        func deck(_ name: String, _ s: StudySubject, _ ch: Chapter?, _ cards: [(String, String)], due: Int, by: Actor = .me) {
            let d = Deck(id: UUID()); d.name = name; d.subjectID = s.id; d.chapterID = ch?.id
            store.insert(d, by: by)
            for (i, c) in cards.enumerated() {
                let card = Card(id: UUID()); card.deckID = d.id; card.front = c.0; card.back = c.1
                if i < due { card.state = "review"; card.stability = 3; card.difficulty = 5; card.reps = 2; card.lastReviewAt = now.addingTimeInterval(-4 * 86400); card.dueAt = now.addingTimeInterval(-3600) }
                else if i < cards.count - 3 { card.state = "review"; card.stability = 12; card.difficulty = 4.5; card.reps = 3; card.lastReviewAt = now.addingTimeInterval(-86400); card.dueAt = now.addingTimeInterval(Double(i) * 86400) }
                store.insert(card, by: by)
            }
        }
        deck("Forces", physics, forces, [
            ("Newton's second law", "$F = ma$ — force equals mass times acceleration"), ("Unit of force", "The newton, $1\\,N = 1\\,kg\\,m/s^2$"),
            ("What is friction?", "A force that opposes motion between surfaces in contact"), ("Momentum", "$p = mv$"),
            ("Conservation of momentum", "Total momentum before a collision equals total momentum after"), ("Weight", "$W = mg$, with $g \\approx 9.8\\,N/kg$"),
            ("Terminal velocity", "Speed at which drag equals weight, so acceleration is zero"), ("Newton's third law", "Every force has an equal and opposite reaction force"),
            ("Resultant force", "The single force with the same effect as all the forces acting"), ("Impulse", "$F\\Delta t = \\Delta p$"),
        ], due: 6)
        deck("Organic chemistry", chemistry, organic, [
            ("General formula of alkanes", "$C_nH_{2n+2}$"), ("Test for an alkene", "Bromine water turns from orange to colourless"),
            ("Functional group of alcohols", "–OH (hydroxyl)"), ("Ethanol formula", "$C_2H_5OH$"), ("Cracking", "Breaking long hydrocarbons into shorter, more useful ones"),
        ], due: 3, by: .instinct)

        // A plan from Instinct, waiting on Today
        let p = Proposal(id: UUID())
        p.rangeStart = at(2, 0); p.rangeEnd = at(5, 0)
        p.drafts = [
            PlanDraft(startAt: at(3, 16), endAt: at(3, 16, 50), kind: "revision", subjectID: maths.id, assignmentID: test.id, goal: "Quadratic formula: mixed questions", reason: "Test on Tuesday"),
            PlanDraft(startAt: at(3, 17), endAt: at(3, 17, 45), kind: "study", subjectID: chemistry.id, assignmentID: lab.id, goal: "Conclusion and evaluation", reason: "Lab report due Friday"),
            PlanDraft(startAt: at(3, 20, 30), endAt: at(3, 20, 45), kind: "review", subjectID: physics.id, goal: "Forces cards", reason: "Spaced repetition"),
            PlanDraft(startAt: at(4, 16), endAt: at(4, 16, 50), kind: "revision", subjectID: maths.id, assignmentID: test.id, goal: "Full past paper, timed", reason: "Last run-through before the test"),
        ]
        p.reasoning = "You missed Wednesday's maths block, so I moved the quadratics practice earlier and kept Thursday evening light because of football."
        p.warnings = []
        store.insert(p, by: .instinct)

        // What Instinct did yesterday
        let batch = UUID()
        for (i, s) in ["Planned study Thu 16:00 · Results and graphs", "Planned revision Thu 17:00 · Completing the square", "Removed block Thu 19:30"].enumerated() {
            let a = ActivityItem(id: UUID()); a.at = now.addingTimeInterval(-20 * 3600 + Double(i)); a.batchID = batch; a.actor = "instinct"
            a.action = i == 2 ? "deleted" : "created"; a.entityName = "blocks"; a.summary = s; a.reason = "Replanned after your missed block."
            store.insert(a, by: .instinct)
        }
        let p2 = store.prefs
        p2.planModeRaw = PlanMode.ask.rawValue
        for item in store.all(StudySubject.self) { item.dirty = false }
        store.save(sync: false)
    }
}
