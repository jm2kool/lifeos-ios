import Foundation
import SwiftData
import SwiftUI

/// The app's data on this iPhone (SwiftData), and every change you make to it. Each change is saved at once,
/// then synced, and notifications and widgets are brought up to date.
@Observable @MainActor
final class Store {
    static let shared = Store()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    /// Bumped after every change, so views showing derived numbers refresh.
    private(set) var revision = 0
    var toast: Toast?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var symbol: String = "checkmark.circle.fill"
        var undoBatch: UUID?
    }

    private init() {
        let schema = Schema(Models.all)
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Lumen", schema: schema)])
        } catch {
            // A store that can't be opened (say, after a model change) is set aside rather than crashing the app;
            // everything synced comes back from the server.
            let url = URL.applicationSupportDirectory.appending(path: "Lumen.store")
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix)) }
            container = (try? ModelContainer(for: schema, configurations: [ModelConfiguration("Lumen", schema: schema)]))
                ?? (try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]))
        }
        context.autosaveEnabled = true
    }

    // MARK: Reading

    func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
    func live<T: PersistentModel & Synced>(_ type: T.Type) -> [T] { all(type).filter { !$0.trashed } }
    func find<T: PersistentModel & Synced>(_ type: T.Type, _ id: UUID?) -> T? {
        guard let id else { return nil }
        return all(type).first { $0.id == id }
    }

    var subjects: [StudySubject] { live(StudySubject.self).sorted { ($0.sort, $0.name) < ($1.sort, $1.name) } }
    func subject(_ id: UUID?) -> StudySubject? { find(StudySubject.self, id) }
    func color(for subjectID: UUID?) -> Color { Color(hex: subject(subjectID)?.color ?? "#7C8CFF") }

    /// Your preferences (there's always exactly one).
    var prefs: UserPrefs {
        let mine = Auth.shared.userID.flatMap(UUID.init(uuidString:))
        let rows = live(UserPrefs.self)
        if let p = rows.first(where: { $0.id == mine }) ?? rows.first { return p }
        let p = UserPrefs(id: mine ?? UUID())
        p.timezone = TimeZone.current.identifier
        p.touch()
        context.insert(p)
        try? context.save()
        return p
    }

    var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    func loggedMinutes(assignment id: UUID) -> Int {
        live(FocusSession.self).filter { $0.assignmentID == id }.reduce(0) { $0 + $1.minutes }
    }

    func progress(_ a: Assignment) -> Double {
        if a.status == .done { return 1 }
        guard a.estimatedMinutes > 0 else { return 0 }
        return min(1, Double(loggedMinutes(assignment: a.id)) / Double(a.estimatedMinutes))
    }

    func blocks(from: Date, to: Date) -> [StudyBlock] {
        live(StudyBlock.self).filter { $0.endAt > from && $0.startAt < to }.sorted { $0.startAt < $1.startAt }
    }

    var nextBlock: StudyBlock? {
        live(StudyBlock.self).filter { $0.status == .planned && $0.endAt > Date() }.min { $0.startAt < $1.startAt }
    }

    var pendingProposal: Proposal? {
        live(Proposal.self).filter(\.isPending).max { $0.createdAt < $1.createdAt }
    }

    /// Cards to review now: everything due, plus today's allowance of new cards.
    func dueCards(deck: UUID? = nil, now: Date = Date()) -> [Card] {
        let cards = live(Card.self).filter { deck == nil || $0.deckID == deck }
        let liveDecks = Set(live(Deck.self).map(\.id))
        let usable = cards.filter { $0.deckID.map(liveDecks.contains) ?? false }
        let due = usable.filter { !$0.isNew && $0.dueAt <= now }.sorted { $0.dueAt < $1.dueAt }
        let startOfDay = calendar.startOfDay(for: now)
        let introducedToday = live(ReviewLog.self).filter { $0.reviewedAt >= startOfDay && $0.state == "new" }.count
        let allowance = max(0, prefs.newCardsPerDay - introducedToday)
        let fresh = usable.filter(\.isNew).sorted { $0.createdAt < $1.createdAt }.prefix(allowance)
        return due + fresh
    }

    // MARK: Writing

    /// Saves, then syncs, reschedules notifications and refreshes widgets shortly after.
    func save(sync: Bool = true) {
        try? context.save()
        revision &+= 1
        if sync { SyncEngine.shared.schedulePush() }
        Notifier.shared.scheduleRefresh()
        WidgetBridge.scheduleRefresh()
    }

    func insert<T: PersistentModel & Synced>(_ item: T, by actor: Actor = .me) {
        item.createdAt = Date()
        item.createdBy = actor.rawValue
        item.touch(actor)
        context.insert(item)
    }

    func remove<T: PersistentModel & Synced>(_ item: T) {
        item.trashed = true
        item.touch()
        save()
    }

    func show(_ text: String, symbol: String = "checkmark.circle.fill", undo: UUID? = nil) {
        withAnimation(.snappy) { toast = Toast(text: text, symbol: symbol, undoBatch: undo) }
    }

    // MARK: Assignments

    @discardableResult
    func addAssignment(from parsed: QuickAddParser.Result, subjectID: UUID? = nil) -> Assignment {
        let a = Assignment(id: UUID())
        a.title = parsed.title
        a.kind = AssignmentKind(rawValue: parsed.kind) ?? .homework
        a.subjectID = subjectID ?? parsed.subjectID
        a.dueAt = parsed.due
        a.estimatedHours = parsed.hours ?? defaultHours(for: a.kind)
        a.priority = parsed.priority.flatMap(Priority.init(rawValue:)) ?? .medium
        if let sid = a.subjectID, !parsed.chapters.isEmpty {
            a.chapterUUIDs = parsed.chapters.map { chapter(number: $0, subject: sid).id }
        }
        insert(a)
        save()
        return a
    }

    func defaultHours(for kind: AssignmentKind) -> Double {
        switch kind {
        case .homework: return 1
        case .project: return 4
        case .test: return 3
        case .exam: return 8
        case .revision: return 2
        }
    }

    /// The subject's chapter with this number, made if it doesn't exist yet.
    func chapter(number: Int, subject: UUID) -> Chapter {
        if let c = live(Chapter.self).first(where: { $0.subjectID == subject && $0.number == number }) { return c }
        let c = Chapter(id: UUID())
        c.subjectID = subject
        c.number = number
        c.sort = number
        insert(c)
        return c
    }

    func setStatus(_ a: Assignment, _ s: TaskStatus) {
        a.status = s
        a.touch()
        save()
        if s == .done { Haptics.success(); show("\(a.title) done") }
    }

    // MARK: Blocks and focus

    func setOutcome(_ b: StudyBlock, _ status: BlockStatus, note: String? = nil) {
        b.status = status
        if let note, !note.isEmpty { b.outcomeNote = note }
        b.touch()
        save()
    }

    /// Records time studied. Linked to a block, it also sets the block's outcome.
    func logFocus(start: Date, end: Date, minutes: Int, subjectID: UUID?, assignmentID: UUID?, blockID: UUID?, deckID: UUID?,
                  goal: String?, outcome: Outcome?, note: String?) {
        if minutes > 0 {
            let s = FocusSession(id: UUID())
            s.startedAt = start
            s.endedAt = end
            s.minutes = minutes
            s.subjectID = subjectID
            s.assignmentID = assignmentID
            s.blockID = blockID
            s.deckID = deckID
            s.goal = goal
            s.outcome = outcome
            s.note = note
            insert(s)
        }
        if let blockID, let b = find(StudyBlock.self, blockID), let outcome {
            b.status = outcome.blockStatus
            if let note, !note.isEmpty { b.outcomeNote = note }
            b.touch()
        }
        if let assignmentID, let a = find(Assignment.self, assignmentID), a.status == .todo, minutes > 0 {
            a.status = .inProgress
            a.touch()
        }
        save()
    }

    // MARK: Cards

    func review(_ card: Card, _ rating: Rating, duration: TimeInterval) {
        let scheduler = FSRS(retention: prefs.desiredRetention)
        let before = card.memory
        let elapsed = before.lastReview.map { max(0, Date().timeIntervalSince($0) / 86400) } ?? 0
        let after = scheduler.review(before, rating)
        card.memory = after
        card.touch()
        let log = ReviewLog(id: UUID())
        log.cardID = card.id
        log.deckID = card.deckID
        log.rating = rating.rawValue
        log.reviewedAt = Date()
        log.state = before.state
        log.elapsedDays = elapsed
        log.scheduledDays = after.scheduledDays
        log.stability = after.stability
        log.difficulty = after.difficulty
        log.durationMs = Int(duration * 1000)
        insert(log)
        save()
    }

    // MARK: Plans

    /// Turns a plan into blocks: the planned blocks it replaces go, the new ones arrive, and it's all one Undo.
    func accept(_ p: Proposal, drafts: [PlanDraft]? = nil) {
        let batch = UUID()
        let author = Actor(rawValue: p.createdBy) ?? .instinct
        let final = drafts ?? p.drafts
        let now = Date()
        if p.replaceRaw != "none" {
            for b in live(StudyBlock.self) where b.status == .planned && b.startAt >= max(p.rangeStart, now) && b.startAt < p.rangeEnd
                && (p.replaceRaw == "all" || b.createdBy == Actor.instinct.rawValue || b.createdBy == Actor.auto.rawValue) {
                let before = b.row(user: Auth.shared.userID ?? "")
                b.trashed = true
                b.touch()
                logActivity(batch: batch, actor: author, action: "deleted", entity: StudyBlock.table, id: b.id,
                            summary: "Removed \(b.kind.label.lowercased()) \(Fmt.dayTime(b.startAt))", before: before, after: b.row(user: Auth.shared.userID ?? ""))
            }
        }
        for d in final where d.endAt > d.startAt {
            let b = StudyBlock(id: d.id)
            b.startAt = d.startAt
            b.endAt = d.endAt
            b.kind = BlockKind(rawValue: d.kind) ?? .study
            b.subjectID = d.subjectID
            b.assignmentID = d.assignmentID
            b.deckID = d.deckID
            b.chapterIDs = d.chapterIDs
            b.goal = d.goal
            b.proposalID = p.id
            b.reason = d.reason
            insert(b, by: author)
            b.updatedBy = Actor.me.rawValue
            logActivity(batch: batch, actor: author, action: "created", entity: StudyBlock.table, id: b.id,
                        summary: "Planned \(b.kind.label.lowercased()) \(Fmt.dayTime(b.startAt))\(b.goal.isEmpty ? "" : " · \(b.goal)")",
                        before: nil, after: b.row(user: Auth.shared.userID ?? ""))
        }
        p.statusRaw = "accepted"
        p.edited = drafts != nil
        p.decidedAt = now
        p.touch()
        save()
        Haptics.success()
        show("Plan added · \(final.count) blocks", symbol: "calendar.badge.checkmark", undo: batch)
    }

    func reject(_ p: Proposal, feedback: String?) {
        p.statusRaw = "rejected"
        p.feedback = feedback
        p.decidedAt = Date()
        p.touch()
        save()
    }

    private func logActivity(batch: UUID, actor: Actor, action: String, entity: String, id: UUID, summary: String,
                             before: [String: Any]?, after: [String: Any]?) {
        let a = ActivityItem(id: UUID())
        a.at = Date()
        a.batchID = batch
        a.actor = actor.rawValue
        a.action = action
        a.entity = entity
        a.entityID = id
        a.summary = summary
        a.beforeJSON = before.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        a.afterJSON = after.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        insert(a, by: actor)
    }

    /// Puts everything in one batch back how it was before.
    func undo(batch: UUID) {
        let items = live(ActivityItem.self).filter { $0.batchID == batch && $0.undoneAt == nil }
        guard !items.isEmpty else { return }
        for item in items { revert(item) }
        save()
        Haptics.tap()
        show("Undone", symbol: "arrow.uturn.backward.circle.fill")
    }

    func undo(_ item: ActivityItem) {
        revert(item)
        save()
        show("Undone", symbol: "arrow.uturn.backward.circle.fill")
    }

    private func revert(_ item: ActivityItem) {
        guard let table = item.entity, let id = item.entityID else { return }
        let before = item.beforeJSON.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        func restore<T: PersistentModel & Synced>(_ type: T.Type) {
            if let before {
                let target = find(type, id) ?? { let n = T(id: id); context.insert(n); return n }()
                target.applyRow(Row(before))
                target.touch()
            } else if let target = find(type, id) {
                target.trashed = true
                target.touch()
            }
        }
        switch table {
        case StudyBlock.table: restore(StudyBlock.self)
        case Assignment.table: restore(Assignment.self)
        case Deck.table: restore(Deck.self)
        case Card.table: restore(Card.self)
        case StudySubject.table: restore(StudySubject.self)
        case Chapter.table: restore(Chapter.self)
        case Topic.table: restore(Topic.self)
        case Proposal.table: restore(Proposal.self)
        case AvailabilityWindow.table: restore(AvailabilityWindow.self)
        case BusySlot.table: restore(BusySlot.self)
        case FileAttachment.table: restore(FileAttachment.self)
        default: break
        }
        item.undoneAt = Date()
        item.touch()
    }

    /// The built-in planner's suggestion for the coming days, as a proposal you can accept, edit or reject.
    @discardableResult
    func makeAutoPlan(days: Int = 7) -> Proposal {
        let now = Date()
        let cal = calendar
        let p = prefs
        let rangeEnd = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(Double(days) * 86400)
        let replaced: (StudyBlock) -> Bool = { b in
            b.status == .planned && b.startAt >= now && b.startAt < rangeEnd && (b.createdBy == Actor.instinct.rawValue || b.createdBy == Actor.auto.rawValue)
        }
        let allBlocks = live(StudyBlock.self)
        let kept = allBlocks.filter { !replaced($0) && $0.endAt > now && $0.startAt < rangeEnd && $0.status == .planned }
        let keptMinutes = Dictionary(grouping: kept.filter { $0.assignmentID != nil }, by: { $0.assignmentID! }).mapValues { $0.reduce(0) { $0 + $1.minutes } }
        let tasks: [AutoPlanner.Task] = live(Assignment.self).filter(\.isOpen).map { a in
            let left = a.estimatedMinutes - loggedMinutes(assignment: a.id) - (keptMinutes[a.id] ?? 0)
            return AutoPlanner.Task(id: a.id, title: a.title, subjectID: a.subjectID, subjectName: subject(a.subjectID)?.name,
                                    kind: a.kindRaw, due: a.dueAt, remainingMinutes: max(0, left), priority: a.priorityRaw,
                                    chapterIDs: a.chapterUUIDs)
        }.filter { $0.remainingMinutes > 0 }
        let windows = live(AvailabilityWindow.self).map {
            AutoPlanner.Window(weekday: $0.weekday, start: $0.startMinutes, end: $0.endMinutes, free: $0.isFree)
        }
        let busy = live(BusySlot.self).filter { $0.endAt > now && $0.startAt < rangeEnd }.map { AutoPlanner.Interval(start: $0.startAt, end: $0.endAt) }
        var prefsIn = AutoPlanner.Prefs()
        prefsIn.maxMinutesPerDay = Int(p.maxHoursPerDay * 60)
        prefsIn.blockMinutes = max(15, p.blockMinutes)
        prefsIn.breakMinutes = max(0, p.breakMinutes)
        prefsIn.noStudyDays = Set(p.noStudyDays)
        prefsIn.earliest = Clock.minutes(p.earliestTime)
        prefsIn.latest = Clock.minutes(p.latestTime)
        let decks = live(Deck.self)
        let due = dueCards().count
        let totalCards = live(Card.self).count
        let topDeck = decks.max { a, b in dueCards(deck: a.id).count < dueCards(deck: b.id).count }
        let planner = AutoPlanner(now: now, days: days, tasks: tasks, windows: windows, busy: busy,
                                  keep: kept.map { AutoPlanner.Interval(start: $0.startAt, end: $0.endAt) }, prefs: prefsIn,
                                  reviewDeck: totalCards > 0 ? (id: topDeck?.id, subjectID: topDeck?.subjectID, dueNow: due, total: totalCards) : nil,
                                  calendar: cal)
        let out = planner.plan()
        // Proposals from the built-in planner replace earlier ones that are still waiting.
        for old in live(Proposal.self) where old.isPending { old.statusRaw = "superseded"; old.touch() }
        let proposal = Proposal(id: UUID())
        proposal.rangeStart = now
        proposal.rangeEnd = rangeEnd
        proposal.replaceRaw = "instinct"
        proposal.drafts = out.drafts.map {
            PlanDraft(startAt: $0.start, endAt: $0.end, kind: $0.kind, subjectID: $0.subjectID, assignmentID: $0.assignmentID,
                      deckID: $0.deckID, chapterIDs: $0.chapterIDs.map(\.lower), goal: $0.goal, reason: $0.reason)
        }
        proposal.warnings = out.warnings
        proposal.reasoning = tasks.isEmpty
            ? "Nothing's waiting to be planned — add an assignment and try again."
            : "Earliest deadline first, weighted by priority, with each piece of work spread over the days before it's due."
        insert(proposal, by: .auto)
        save()
        return proposal
    }

    // MARK: Stats

    func minutes(on day: Date) -> Int {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return live(FocusSession.self).filter { $0.startedAt >= start && $0.startedAt < end }.reduce(0) { $0 + $1.minutes }
    }

    var streak: Int {
        let days = Set(live(FocusSession.self).filter { $0.minutes > 0 }.map { calendar.startOfDay(for: $0.startedAt) })
        var d = calendar.startOfDay(for: Date())
        if !days.contains(d) { d = calendar.date(byAdding: .day, value: -1, to: d) ?? d }
        var n = 0
        while days.contains(d) {
            n += 1
            d = calendar.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return n
    }

    /// How much of the planned time in the last two weeks actually happened (partial counts half).
    var adherence: Double? {
        let since = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let past = live(StudyBlock.self).filter { $0.endAt < Date() && $0.startAt >= since }
        guard !past.isEmpty else { return nil }
        let score = past.reduce(0.0) { acc, b in
            switch b.status {
            case .done: return acc + 1
            case .partial: return acc + 0.5
            default: return acc
            }
        }
        return score / Double(past.count)
    }

    // MARK: Account

    private func wipe<T: PersistentModel>(_ type: T.Type) { try? context.delete(model: type) }

    /// Removes everything on this iPhone (used when signing out or switching accounts).
    func wipeLocal() {
        for t in Models.all { wipe(t) }
        try? context.save()
        revision &+= 1
    }
}

