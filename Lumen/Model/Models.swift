import Foundation
import SwiftData

/// Everything that syncs: each kind of record maps to one table in the `lumen` schema.
/// `dirty` marks local changes still to send; `trashed` is a soft delete every device hears about.
protocol Synced: AnyObject {
    static var table: String { get }
    var id: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var trashed: Bool { get set }
    var dirty: Bool { get set }
    var createdBy: String { get set }
    var updatedBy: String { get set }
    var reason: String? { get set }
    init(id: UUID)
    /// The table's own columns.
    func fields() -> [String: Any]
    /// Reads the table's own columns from a server row.
    func apply(_ r: Row)
}

extension Synced {
    func row(user: String) -> [String: Any] {
        var f = fields()
        f["id"] = id.lower
        f["user_id"] = user
        f["created_at"] = ISO.string(createdAt)
        f["updated_at"] = ISO.string(updatedAt)
        f["deleted"] = trashed
        f["created_by"] = createdBy
        f["updated_by"] = updatedBy
        f["reason"] = reason.json
        return f
    }

    func applyRow(_ r: Row) {
        if let d = r.date("created_at") { createdAt = d }
        if let d = r.date("updated_at") { updatedAt = d }
        trashed = r.bool("deleted") ?? false
        createdBy = r.str("created_by") ?? "me"
        updatedBy = r.str("updated_by") ?? "me"
        reason = r.str("reason")
        apply(r)
    }

    /// Marks a local change, to be synced.
    func touch(_ actor: Actor = .me) {
        updatedAt = Date()
        updatedBy = actor.rawValue
        dirty = true
    }

    var byInstinct: Bool { createdBy == Actor.instinct.rawValue || updatedBy == Actor.instinct.rawValue }
}

// MARK: - Syllabus

@Model final class StudySubject {
    @Attribute(.unique) var id: UUID
    var name: String = ""
    var color: String = "#7C8CFF"
    var icon: String = "book.closed"
    var examAt: Date?
    var sort: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }
}

extension StudySubject: Synced {
    static var table: String { "subjects" }
    func fields() -> [String: Any] {
        ["name": name, "color": color, "icon": icon, "exam_at": examAt.json, "sort": sort]
    }
    func apply(_ r: Row) {
        name = r.str("name") ?? name
        color = r.str("color") ?? color
        icon = r.str("icon") ?? icon
        examAt = r.date("exam_at")
        sort = r.int("sort") ?? 0
    }
}

@Model final class Chapter {
    @Attribute(.unique) var id: UUID
    var subjectID: UUID?
    var number: Int?
    var title: String = ""
    var sort: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }

    var displayTitle: String {
        if let n = number { return title.isEmpty ? "Chapter \(n)" : "\(n). \(title)" }
        return title.isEmpty ? "Chapter" : title
    }
    var shortTitle: String { number.map { "Ch \($0)" } ?? (title.isEmpty ? "Chapter" : title) }
}

extension Chapter: Synced {
    static var table: String { "chapters" }
    func fields() -> [String: Any] {
        ["subject_id": subjectID.json, "number": number.map { $0 as Any } ?? NSNull(), "title": title, "sort": sort]
    }
    func apply(_ r: Row) {
        subjectID = r.uuid("subject_id")
        number = r.int("number")
        title = r.str("title") ?? ""
        sort = r.int("sort") ?? 0
    }
}

@Model final class Topic {
    @Attribute(.unique) var id: UUID
    var subjectID: UUID?
    var chapterID: UUID?
    var title: String = ""
    var statusRaw: String = TopicStatus.notStarted.rawValue
    var notes: String?
    var sort: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }

    var status: TopicStatus {
        get { TopicStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }
}

extension Topic: Synced {
    static var table: String { "topics" }
    func fields() -> [String: Any] {
        ["subject_id": subjectID.json, "chapter_id": chapterID.json, "title": title, "status": statusRaw, "notes": notes.json, "sort": sort]
    }
    func apply(_ r: Row) {
        subjectID = r.uuid("subject_id")
        chapterID = r.uuid("chapter_id")
        title = r.str("title") ?? ""
        statusRaw = r.str("status") ?? statusRaw
        notes = r.str("notes")
        sort = r.int("sort") ?? 0
    }
}

// MARK: - Assignments

@Model final class Assignment {
    @Attribute(.unique) var id: UUID
    var title: String = ""
    var kindRaw: String = AssignmentKind.homework.rawValue
    var subjectID: UUID?
    var chapterIDs: [String] = []
    var dueAt: Date?
    var estimatedHours: Double = 1
    var priorityRaw: String = Priority.medium.rawValue
    var statusRaw: String = TaskStatus.todo.rawValue
    var notes: String = ""
    var completedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }

    var kind: AssignmentKind {
        get { AssignmentKind(rawValue: kindRaw) ?? .homework }
        set { kindRaw = newValue.rawValue }
    }
    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .done ? (completedAt ?? Date()) : nil
        }
    }
    var chapterUUIDs: [UUID] {
        get { chapterIDs.compactMap { UUID(uuidString: $0) } }
        set { chapterIDs = newValue.map(\.lower) }
    }
    var estimatedMinutes: Int { Int((estimatedHours * 60).rounded()) }
    var isOpen: Bool { status != .done && !trashed }
}

extension Assignment: Synced {
    static var table: String { "assignments" }
    func fields() -> [String: Any] {
        ["title": title, "kind": kindRaw, "subject_id": subjectID.json, "chapter_ids": chapterIDs, "due_at": dueAt.json,
         "estimated_hours": (estimatedHours * 100).rounded() / 100, "priority": priorityRaw, "status": statusRaw,
         "notes": notes, "completed_at": completedAt.json]
    }
    func apply(_ r: Row) {
        title = r.str("title") ?? title
        kindRaw = r.str("kind") ?? kindRaw
        subjectID = r.uuid("subject_id")
        chapterIDs = r.uuids("chapter_ids")
        dueAt = r.date("due_at")
        estimatedHours = r.double("estimated_hours") ?? estimatedHours
        priorityRaw = r.str("priority") ?? priorityRaw
        statusRaw = r.str("status") ?? statusRaw
        notes = r.str("notes") ?? ""
        completedAt = r.date("completed_at")
    }
}

@Model final class FileAttachment {
    @Attribute(.unique) var id: UUID
    var assignmentID: UUID?
    var name: String = ""
    var path: String = ""
    var mime: String?
    var size: Int = 0
    var uploaded: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }
}

extension FileAttachment: Synced {
    static var table: String { "attachments" }
    func fields() -> [String: Any] {
        ["assignment_id": assignmentID.json, "name": name, "path": path, "mime": mime.json, "size": size]
    }
    func apply(_ r: Row) {
        assignmentID = r.uuid("assignment_id")
        name = r.str("name") ?? name
        path = r.str("path") ?? path
        mime = r.str("mime")
        size = r.int("size") ?? 0
        uploaded = true
    }
}

// MARK: - Planning

@Model final class StudyBlock {
    @Attribute(.unique) var id: UUID
    var startAt: Date = Date()
    var endAt: Date = Date().addingTimeInterval(3000)
    var kindRaw: String = BlockKind.study.rawValue
    var subjectID: UUID?
    var assignmentID: UUID?
    var chapterIDs: [String] = []
    var topicIDs: [String] = []
    var deckID: UUID?
    var goal: String = ""
    var statusRaw: String = BlockStatus.planned.rawValue
    var outcomeNote: String?
    var proposalID: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .study }
        set { kindRaw = newValue.rawValue }
    }
    var status: BlockStatus {
        get { BlockStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
    var minutes: Int { max(0, Int(endAt.timeIntervalSince(startAt) / 60)) }
    var isNow: Bool { startAt <= Date() && endAt > Date() }
    /// Planned, but its time has passed with no outcome yet.
    var needsOutcome: Bool { status == .planned && endAt < Date() }
}

extension StudyBlock: Synced {
    static var table: String { "blocks" }
    func fields() -> [String: Any] {
        ["start_at": ISO.string(startAt), "end_at": ISO.string(endAt), "kind": kindRaw, "subject_id": subjectID.json,
         "assignment_id": assignmentID.json, "chapter_ids": chapterIDs, "topic_ids": topicIDs, "deck_id": deckID.json,
         "goal": goal, "status": statusRaw, "outcome_note": outcomeNote.json, "proposal_id": proposalID.json]
    }
    func apply(_ r: Row) {
        startAt = r.date("start_at") ?? startAt
        endAt = r.date("end_at") ?? endAt
        kindRaw = r.str("kind") ?? kindRaw
        subjectID = r.uuid("subject_id")
        assignmentID = r.uuid("assignment_id")
        chapterIDs = r.uuids("chapter_ids")
        topicIDs = r.uuids("topic_ids")
        deckID = r.uuid("deck_id")
        goal = r.str("goal") ?? ""
        statusRaw = r.str("status") ?? statusRaw
        outcomeNote = r.str("outcome_note")
        proposalID = r.uuid("proposal_id")
    }
}

@Model final class FocusSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var minutes: Int = 0
    var subjectID: UUID?
    var assignmentID: UUID?
    var blockID: UUID?
    var deckID: UUID?
    var goal: String?
    var outcomeRaw: String?
    var note: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }

    var outcome: Outcome? {
        get { outcomeRaw.flatMap(Outcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }
}

extension FocusSession: Synced {
    static var table: String { "focus_sessions" }
    func fields() -> [String: Any] {
        ["started_at": ISO.string(startedAt), "ended_at": ISO.string(endedAt), "minutes": minutes, "subject_id": subjectID.json,
         "assignment_id": assignmentID.json, "block_id": blockID.json, "deck_id": deckID.json, "goal": goal.json,
         "outcome": outcomeRaw.json, "note": note.json]
    }
    func apply(_ r: Row) {
        startedAt = r.date("started_at") ?? startedAt
        endedAt = r.date("ended_at") ?? endedAt
        minutes = r.int("minutes") ?? 0
        subjectID = r.uuid("subject_id")
        assignmentID = r.uuid("assignment_id")
        blockID = r.uuid("block_id")
        deckID = r.uuid("deck_id")
        goal = r.str("goal")
        outcomeRaw = r.str("outcome")
        note = r.str("note")
    }
}

@Model final class AvailabilityWindow {
    @Attribute(.unique) var id: UUID
    var weekday: Int = 1            // 0 = Sunday … 6 = Saturday
    var startTime: String = "16:00"
    var endTime: String = "20:00"
    var kindRaw: String = "free"    // free | busy
    var label: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }

    var isFree: Bool { kindRaw == "free" }
    var startMinutes: Int { Clock.minutes(startTime) }
    var endMinutes: Int { Clock.minutes(endTime) }
}

extension AvailabilityWindow: Synced {
    static var table: String { "availability" }
    func fields() -> [String: Any] {
        ["weekday": weekday, "start_time": startTime, "end_time": endTime, "kind": kindRaw, "label": label.json]
    }
    func apply(_ r: Row) {
        weekday = r.int("weekday") ?? weekday
        startTime = r.str("start_time") ?? startTime
        endTime = r.str("end_time") ?? endTime
        kindRaw = r.str("kind") ?? kindRaw
        label = r.str("label")
    }
}

@Model final class BusySlot {
    @Attribute(.unique) var id: UUID
    var startAt: Date = Date()
    var endAt: Date = Date()
    var source: String = "manual"   // calendar | manual
    var title: String?
    var allDay: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }
}

extension BusySlot: Synced {
    static var table: String { "busy_slots" }
    func fields() -> [String: Any] {
        ["start_at": ISO.string(startAt), "end_at": ISO.string(endAt), "source": source, "title": title.json, "all_day": allDay]
    }
    func apply(_ r: Row) {
        startAt = r.date("start_at") ?? startAt
        endAt = r.date("end_at") ?? endAt
        source = r.str("source") ?? source
        title = r.str("title")
        allDay = r.bool("all_day") ?? false
    }
}

@Model final class UserPrefs {
    @Attribute(.unique) var id: UUID
    var timezone: String = TimeZone.current.identifier
    var maxHoursPerDay: Double = 4
    var blockMinutes: Int = 50
    var breakMinutes: Int = 10
    var noStudyDays: [Int] = []
    var earliestTime: String = "08:00"
    var latestTime: String = "22:00"
    var planModeRaw: String = PlanMode.ask.rawValue
    var pomodoroFocus: Int = 25
    var pomodoroShort: Int = 5
    var pomodoroLong: Int = 15
    var pomodoroRounds: Int = 4
    var reviewTime: String = "19:00"
    var newCardsPerDay: Int = 20
    var desiredRetention: Double = 0.9
    var dailyGoalMinutes: Int = 120
    var shareCalendarTitles: Bool = false
    var webhookURL: String = ""
    var webhookSecret: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }

    var planMode: PlanMode {
        get { PlanMode(rawValue: planModeRaw) ?? .ask }
        set { planModeRaw = newValue.rawValue }
    }
}

extension UserPrefs: Synced {
    static var table: String { "preferences" }
    func fields() -> [String: Any] {
        ["timezone": timezone, "max_hours_per_day": maxHoursPerDay, "block_minutes": blockMinutes, "break_minutes": breakMinutes,
         "no_study_days": noStudyDays, "earliest_time": earliestTime, "latest_time": latestTime, "plan_mode": planModeRaw,
         "pomodoro_focus": pomodoroFocus, "pomodoro_short": pomodoroShort, "pomodoro_long": pomodoroLong,
         "pomodoro_rounds": pomodoroRounds, "review_time": reviewTime, "new_cards_per_day": newCardsPerDay,
         "desired_retention": (desiredRetention * 100).rounded() / 100, "daily_goal_minutes": dailyGoalMinutes,
         "share_calendar_titles": shareCalendarTitles,
         "webhook_url": webhookURL.isEmpty ? NSNull() as Any : webhookURL as Any,
         "webhook_secret": webhookSecret.isEmpty ? NSNull() as Any : webhookSecret as Any]
    }
    func apply(_ r: Row) {
        timezone = r.str("timezone") ?? timezone
        maxHoursPerDay = r.double("max_hours_per_day") ?? maxHoursPerDay
        blockMinutes = r.int("block_minutes") ?? blockMinutes
        breakMinutes = r.int("break_minutes") ?? breakMinutes
        noStudyDays = r.ints("no_study_days")
        earliestTime = r.str("earliest_time") ?? earliestTime
        latestTime = r.str("latest_time") ?? latestTime
        planModeRaw = r.str("plan_mode") ?? planModeRaw
        pomodoroFocus = r.int("pomodoro_focus") ?? pomodoroFocus
        pomodoroShort = r.int("pomodoro_short") ?? pomodoroShort
        pomodoroLong = r.int("pomodoro_long") ?? pomodoroLong
        pomodoroRounds = r.int("pomodoro_rounds") ?? pomodoroRounds
        reviewTime = r.str("review_time") ?? reviewTime
        newCardsPerDay = r.int("new_cards_per_day") ?? newCardsPerDay
        desiredRetention = r.double("desired_retention") ?? desiredRetention
        dailyGoalMinutes = r.int("daily_goal_minutes") ?? dailyGoalMinutes
        shareCalendarTitles = r.bool("share_calendar_titles") ?? false
        webhookURL = r.str("webhook_url") ?? ""
        webhookSecret = r.str("webhook_secret") ?? ""
    }
}

/// One block in a suggested plan, as Instinct sends it.
struct PlanDraft: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var startAt: Date
    var endAt: Date
    var kind: String = "study"
    var subjectID: UUID?
    var assignmentID: UUID?
    var deckID: UUID?
    var chapterIDs: [String] = []
    var goal: String = ""
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, goal, reason
        case startAt = "start_at", endAt = "end_at", subjectID = "subject_id", assignmentID = "assignment_id"
        case deckID = "deck_id", chapterIDs = "chapter_ids"
    }

    init(id: UUID = UUID(), startAt: Date, endAt: Date, kind: String = "study", subjectID: UUID? = nil, assignmentID: UUID? = nil,
         deckID: UUID? = nil, chapterIDs: [String] = [], goal: String = "", reason: String? = nil) {
        self.id = id; self.startAt = startAt; self.endAt = endAt; self.kind = kind; self.subjectID = subjectID
        self.assignmentID = assignmentID; self.deckID = deckID; self.chapterIDs = chapterIDs; self.goal = goal; self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)).flatMap { UUID(uuidString: $0) } ?? UUID()
        func date(_ k: CodingKeys) throws -> Date {
            let s = try c.decode(String.self, forKey: k)
            guard let d = ISO.parse(s) else { throw DecodingError.dataCorruptedError(forKey: k, in: c, debugDescription: "bad date") }
            return d
        }
        startAt = try date(.startAt)
        endAt = try date(.endAt)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "study"
        subjectID = (try? c.decodeIfPresent(String.self, forKey: .subjectID)).flatMap { UUID(uuidString: $0) }
        assignmentID = (try? c.decodeIfPresent(String.self, forKey: .assignmentID)).flatMap { UUID(uuidString: $0) }
        deckID = (try? c.decodeIfPresent(String.self, forKey: .deckID)).flatMap { UUID(uuidString: $0) }
        chapterIDs = (try? c.decodeIfPresent([String].self, forKey: .chapterIDs)) ?? []
        goal = (try? c.decodeIfPresent(String.self, forKey: .goal)) ?? ""
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id.lower, forKey: .id)
        try c.encode(ISO.string(startAt), forKey: .startAt)
        try c.encode(ISO.string(endAt), forKey: .endAt)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(subjectID?.lower, forKey: .subjectID)
        try c.encodeIfPresent(assignmentID?.lower, forKey: .assignmentID)
        try c.encodeIfPresent(deckID?.lower, forKey: .deckID)
        try c.encode(chapterIDs, forKey: .chapterIDs)
        try c.encode(goal, forKey: .goal)
        try c.encodeIfPresent(reason, forKey: .reason)
    }

    var minutes: Int { max(0, Int(endAt.timeIntervalSince(startAt) / 60)) }
}

@Model final class Proposal {
    @Attribute(.unique) var id: UUID
    var rangeStart: Date = Date()
    var rangeEnd: Date = Date()
    var replaceRaw: String = "instinct"      // instinct | all | none
    var blocksJSON: Data = Data("[]".utf8)
    var reasoning: String = ""
    var warningsJSON: Data = Data("[]".utf8)
    var statusRaw: String = "pending"        // pending | accepted | rejected | superseded
    var edited: Bool = false
    var feedback: String?
    var decidedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "instinct"
    var updatedBy: String = "instinct"
    var reason: String?
    init(id: UUID) { self.id = id }

    var drafts: [PlanDraft] {
        get { (try? JSONDecoder().decode([PlanDraft].self, from: blocksJSON)) ?? [] }
        set { blocksJSON = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
    var warnings: [String] {
        get {
            guard let any = try? JSONSerialization.jsonObject(with: warningsJSON) as? [Any] else { return [] }
            return any.compactMap { ($0 as? String) ?? (($0 as? [String: Any])?["message"] as? String) }
        }
        set { warningsJSON = (try? JSONSerialization.data(withJSONObject: newValue)) ?? Data("[]".utf8) }
    }
    var isPending: Bool { statusRaw == "pending" && !trashed }
}

extension Proposal: Synced {
    static var table: String { "proposals" }
    func fields() -> [String: Any] {
        ["range_start": ISO.string(rangeStart), "range_end": ISO.string(rangeEnd), "replace": replaceRaw,
         "blocks": (try? JSONSerialization.jsonObject(with: blocksJSON)) ?? [Any](), "reasoning": reasoning,
         "warnings": (try? JSONSerialization.jsonObject(with: warningsJSON)) ?? [Any](), "status": statusRaw, "edited": edited,
         "feedback": feedback.json, "decided_at": decidedAt.json]
    }
    func apply(_ r: Row) {
        rangeStart = r.date("range_start") ?? rangeStart
        rangeEnd = r.date("range_end") ?? rangeEnd
        replaceRaw = r.str("replace") ?? replaceRaw
        blocksJSON = r.json("blocks") ?? Data("[]".utf8)
        reasoning = r.str("reasoning") ?? ""
        warningsJSON = r.json("warnings") ?? Data("[]".utf8)
        statusRaw = r.str("status") ?? statusRaw
        edited = r.bool("edited") ?? false
        feedback = r.str("feedback")
        decidedAt = r.date("decided_at")
    }
}

/// One thing Instinct (or a planner) did, kept so it can be undone.
@Model final class ActivityItem {
    @Attribute(.unique) var id: UUID
    var at: Date = Date()
    var batchID: UUID?
    var actor: String = "instinct"
    var action: String = "updated"
    /// The table it changed ("entity" itself is reserved by Core Data, which SwiftData sits on).
    var entityName: String?
    var entityID: UUID?
    var summary: String = ""
    var beforeJSON: Data?
    var afterJSON: Data?
    var undoneAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "instinct"
    var updatedBy: String = "instinct"
    var reason: String?
    init(id: UUID) { self.id = id }
}

extension ActivityItem: Synced {
    static var table: String { "activity" }
    func fields() -> [String: Any] {
        ["at": ISO.string(at), "batch_id": batchID.json, "actor": actor, "action": action, "entity": entityName.json,
         "entity_id": entityID.json, "summary": summary,
         "before": beforeJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull(),
         "after": afterJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull(),
         "undone_at": undoneAt.json]
    }
    func apply(_ r: Row) {
        at = r.date("at") ?? at
        batchID = r.uuid("batch_id")
        actor = r.str("actor") ?? actor
        action = r.str("action") ?? action
        entityName = r.str("entity")
        entityID = r.uuid("entity_id")
        summary = r.str("summary") ?? ""
        beforeJSON = r.json("before")
        afterJSON = r.json("after")
        undoneAt = r.date("undone_at")
    }
}

// MARK: - Flashcards

@Model final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String = ""
    var subjectID: UUID?
    var chapterID: UUID?
    var notes: String?
    var sort: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }
}

extension Deck: Synced {
    static var table: String { "decks" }
    func fields() -> [String: Any] {
        ["name": name, "subject_id": subjectID.json, "chapter_id": chapterID.json, "notes": notes.json, "sort": sort]
    }
    func apply(_ r: Row) {
        name = r.str("name") ?? name
        subjectID = r.uuid("subject_id")
        chapterID = r.uuid("chapter_id")
        notes = r.str("notes")
        sort = r.int("sort") ?? 0
    }
}

@Model final class Card {
    @Attribute(.unique) var id: UUID
    var deckID: UUID?
    var front: String = ""
    var back: String = ""
    var frontImage: String?
    var backImage: String?
    var state: String = "new"
    var dueAt: Date = Date()
    var stability: Double = 0
    var difficulty: Double = 0
    var reps: Int = 0
    var lapses: Int = 0
    var scheduledDays: Double = 0
    var lastReviewAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }

    var memory: FSRS.Memory {
        get {
            FSRS.Memory(state: state, stability: stability, difficulty: difficulty, reps: reps, lapses: lapses,
                        scheduledDays: scheduledDays, lastReview: lastReviewAt, due: dueAt)
        }
        set {
            state = newValue.state; stability = newValue.stability; difficulty = newValue.difficulty; reps = newValue.reps
            lapses = newValue.lapses; scheduledDays = newValue.scheduledDays; lastReviewAt = newValue.lastReview; dueAt = newValue.due
        }
    }
    var isNew: Bool { state == "new" }
}

extension Card: Synced {
    static var table: String { "cards" }
    func fields() -> [String: Any] {
        ["deck_id": deckID.json, "front": front, "back": back, "front_image": frontImage.json, "back_image": backImage.json,
         "state": state, "due_at": ISO.string(dueAt), "stability": stability, "difficulty": difficulty, "reps": reps,
         "lapses": lapses, "scheduled_days": scheduledDays, "last_review_at": lastReviewAt.json]
    }
    func apply(_ r: Row) {
        deckID = r.uuid("deck_id")
        front = r.str("front") ?? ""
        back = r.str("back") ?? ""
        frontImage = r.str("front_image")
        backImage = r.str("back_image")
        state = r.str("state") ?? state
        dueAt = r.date("due_at") ?? dueAt
        stability = r.double("stability") ?? 0
        difficulty = r.double("difficulty") ?? 0
        reps = r.int("reps") ?? 0
        lapses = r.int("lapses") ?? 0
        scheduledDays = r.double("scheduled_days") ?? 0
        lastReviewAt = r.date("last_review_at")
    }
}

@Model final class ReviewLog {
    @Attribute(.unique) var id: UUID
    var cardID: UUID?
    var deckID: UUID?
    var rating: Int = 3
    var reviewedAt: Date = Date()
    var state: String?
    var elapsedDays: Double = 0
    var scheduledDays: Double = 0
    var stability: Double = 0
    var difficulty: Double = 0
    var durationMs: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var trashed: Bool = false
    var dirty: Bool = false
    var createdBy: String = "me"
    var updatedBy: String = "me"
    var reason: String?
    init(id: UUID) { self.id = id }
}

extension ReviewLog: Synced {
    static var table: String { "review_logs" }
    func fields() -> [String: Any] {
        ["card_id": cardID.json, "deck_id": deckID.json, "rating": rating, "reviewed_at": ISO.string(reviewedAt), "state": state.json,
         "elapsed_days": elapsedDays, "scheduled_days": scheduledDays, "stability": stability, "difficulty": difficulty,
         "duration_ms": durationMs]
    }
    func apply(_ r: Row) {
        cardID = r.uuid("card_id")
        deckID = r.uuid("deck_id")
        rating = r.int("rating") ?? 3
        reviewedAt = r.date("reviewed_at") ?? reviewedAt
        state = r.str("state")
        elapsedDays = r.double("elapsed_days") ?? 0
        scheduledDays = r.double("scheduled_days") ?? 0
        stability = r.double("stability") ?? 0
        difficulty = r.double("difficulty") ?? 0
        durationMs = r.int("duration_ms") ?? 0
    }
}

/// "HH:mm" strings as minutes after midnight, and back.
enum Clock {
    static func minutes(_ s: String) -> Int {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count >= 2 else { return 0 }
        return min(24 * 60, max(0, p[0] * 60 + p[1]))
    }
    static func string(_ m: Int) -> String { String(format: "%02d:%02d", min(24, m / 60), m % 60) }
    static func date(_ s: String, on day: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(minutes(s) * 60))
    }
    static func components(_ s: String) -> DateComponents {
        let m = minutes(s)
        return DateComponents(hour: m / 60, minute: m % 60)
    }
}

enum Models {
    static let all: [any PersistentModel.Type] = [
        StudySubject.self, Chapter.self, Topic.self, Assignment.self, FileAttachment.self, StudyBlock.self, FocusSession.self,
        AvailabilityWindow.self, BusySlot.self, UserPrefs.self, Proposal.self, ActivityItem.self, Deck.self, Card.self, ReviewLog.self,
    ]
}
