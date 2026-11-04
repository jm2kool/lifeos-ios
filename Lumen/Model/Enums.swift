import Foundation

/// Who made or last changed something. Anything from Instinct gets the sparkle badge.
enum Actor: String, Codable, CaseIterable {
    case me, instinct, auto, system
    var label: String {
        switch self {
        case .me: return "You"
        case .instinct: return "Instinct"
        case .auto: return "Auto-planner"
        case .system: return "Lumen"
        }
    }
}

enum AssignmentKind: String, CaseIterable, Identifiable, Codable {
    case homework, project, test, exam, revision
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .homework: return "doc.text"
        case .project: return "hammer"
        case .test: return "checklist"
        case .exam: return "graduationcap"
        case .revision: return "arrow.triangle.2.circlepath"
        }
    }
}

enum Priority: String, CaseIterable, Identifiable, Codable {
    case low, medium, high, urgent
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var rank: Int { Priority.allCases.firstIndex(of: self) ?? 1 }
    var symbol: String {
        switch self {
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "exclamationmark"
        case .urgent: return "exclamationmark.2"
        }
    }
}

enum TaskStatus: String, CaseIterable, Identifiable, Codable {
    case todo, inProgress = "in_progress", done
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todo: return "To do"
        case .inProgress: return "In progress"
        case .done: return "Done"
        }
    }
    var symbol: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }
}

enum BlockKind: String, CaseIterable, Identifiable, Codable {
    case study, revision, review, practice
    var id: String { rawValue }
    var label: String {
        switch self {
        case .study: return "Study"
        case .revision: return "Revision"
        case .review: return "Card review"
        case .practice: return "Practice"
        }
    }
    var symbol: String {
        switch self {
        case .study: return "book"
        case .revision: return "arrow.triangle.2.circlepath"
        case .review: return "rectangle.on.rectangle.angled"
        case .practice: return "pencil.and.list.clipboard"
        }
    }
}

enum BlockStatus: String, CaseIterable, Identifiable, Codable {
    case planned, done, partial, missed, skipped
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .planned: return "clock"
        case .done: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .missed: return "xmark.circle"
        case .skipped: return "forward.end"
        }
    }
}

enum TopicStatus: String, CaseIterable, Identifiable, Codable {
    case notStarted = "not_started", learning, revised, mastered
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .learning: return "Learning"
        case .revised: return "Revised"
        case .mastered: return "Mastered"
        }
    }
    var progress: Double {
        switch self {
        case .notStarted: return 0
        case .learning: return 1.0 / 3
        case .revised: return 2.0 / 3
        case .mastered: return 1
        }
    }
    var symbol: String {
        switch self {
        case .notStarted: return "circle.dotted"
        case .learning: return "circle.bottomhalf.filled"
        case .revised: return "circle.inset.filled"
        case .mastered: return "checkmark.seal.fill"
        }
    }
    var next: TopicStatus {
        let all = TopicStatus.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

enum Outcome: String, CaseIterable, Identifiable, Codable {
    case done, partial, notDone = "not_done"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .done: return "Done"
        case .partial: return "Partly"
        case .notDone: return "Not done"
        }
    }
    var symbol: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .notDone: return "xmark.circle"
        }
    }
    var blockStatus: BlockStatus {
        switch self {
        case .done: return .done
        case .partial: return .partial
        case .notDone: return .missed
        }
    }
}

enum PlanMode: String, CaseIterable, Identifiable, Codable {
    case auto, ask
    var id: String { rawValue }
    var label: String { self == .auto ? "Auto-apply" : "Ask me first" }
}
