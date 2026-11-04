import Foundation
import SwiftUI

enum AppTab: String, Hashable {
    case today, planner, focus, cards, syllabus
}

/// The sheets Lumen shows over the tabs.
enum SheetRoute: Identifiable, Hashable {
    case settings
    case newAssignment
    case assignment(UUID)
    case block(UUID)
    case newBlock(Date)
    case proposal(UUID)
    case generateCards(UUID?)
    case subject(UUID?)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .newAssignment: return "newAssignment"
        case .assignment(let id): return "a-\(id)"
        case .block(let id): return "b-\(id)"
        case .newBlock(let d): return "nb-\(d.timeIntervalSince1970)"
        case .proposal(let id): return "p-\(id)"
        case .generateCards(let id): return "g-\(id?.uuidString ?? "")"
        case .subject(let id): return "s-\(id?.uuidString ?? "new")"
        }
    }
}

/// A review session: one deck or everything due.
struct ReviewTarget: Identifiable, Hashable {
    var id = UUID()
    var deck: UUID?
}

/// Where you are in the app, and the links that move you around (notifications, widgets, shortcuts).
@Observable @MainActor
final class Router {
    static let shared = Router()

    var tab: AppTab = .today
    var sheet: SheetRoute?
    var review: ReviewTarget?
    var plannerMode: PlannerView.Mode = .schedule
    var focusQuickAdd = false

    func openFocus(block id: UUID) {
        if let b = Store.shared.find(StudyBlock.self, id) { FocusTimer.shared.prepare(block: b) }
        sheet = nil
        review = nil
        tab = .focus
    }

    func openAssignment(_ id: UUID) { sheet = .assignment(id) }

    func openReview(deck: UUID? = nil) {
        sheet = nil
        tab = .cards
        review = ReviewTarget(deck: deck)
    }

    /// lumen://focus?block=<id>, lumen://review, lumen://add, lumen://block/<id>, lumen://planner
    func handle(_ url: URL) {
        guard url.scheme == "lumen" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let id = items.first(where: { $0.name == "block" || $0.name == "id" })?.value.flatMap(UUID.init(uuidString:))
            ?? UUID(uuidString: url.lastPathComponent)
        switch url.host ?? "" {
        case "focus":
            if let id { openFocus(block: id) } else { sheet = nil; tab = .focus }
        case "review": openReview()
        case "add": sheet = nil; tab = .today; focusQuickAdd = true
        case "block": if let id { sheet = .block(id) }
        case "planner": sheet = nil; tab = .planner
        case "assignment": if let id { sheet = .assignment(id) }
        default: break
        }
    }

    func handleShortcut(_ type: String) {
        switch type {
        case "focus":
            if let b = Store.shared.nextBlock, b.startAt < Date().addingTimeInterval(3600) { openFocus(block: b.id) } else { tab = .focus }
        case "add": tab = .today; focusQuickAdd = true
        case "review": openReview()
        default: break
        }
    }
}
