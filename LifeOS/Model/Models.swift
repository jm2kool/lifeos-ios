import Foundation
import SwiftUI

// Typed, read-only views over the JSON document. Views read these; all writes go through ops.

struct TaskItem: Identifiable, Hashable {
    let id: String, title: String, note: String, src: String, due: String?, changedBy: String
    init(_ j: JSON) { id = j["id"].str; title = j["title"].str; note = j["note"].str; src = j["src"].str; due = j["due"].string.flatMap { $0.isEmpty ? nil : $0 }; changedBy = j["changedBy"].str }
}

struct Card: Identifiable, Hashable {
    let id: String, title: String, column: Int, due: String?, note: String, unfiled: Bool, changedBy: String
    init(_ j: JSON) { id = j["id"].str; title = j["t"].str; column = j["c"].int ?? 0; due = j["due"].string.flatMap { $0.isEmpty ? nil : $0 }; note = j["note"].str; unfiled = j["filed"] == .bool(false); changedBy = j["changedBy"].str }
}

struct SavedItem: Identifiable, Hashable {
    let id: String, title: String, url: String, note: String, source: String, changedBy: String
    init(_ j: JSON) { id = j["id"].str; title = j["t"].str; url = j["url"].str; note = j["n"].str; source = j["s"].str; changedBy = j["changedBy"].str }
    var link: URL? { url.lowercased().hasPrefix("http") ? URL(string: url) : nil }
}

struct Event: Identifiable, Hashable {
    let id: String, title: String, start: String, end: String?, note: String, url: String, source: String, checkedAt: String, status: String, changedBy: String
    init(_ j: JSON) {
        changedBy = j["changedBy"].str
        title = j["title"].str; start = j["start"].str; id = j["id"].string ?? (title + start)
        end = j["end"].string.flatMap { $0.isEmpty ? nil : $0 }; note = j["note"].str; url = j["url"].str
        source = j["source"].string ?? "Calendar"; checkedAt = j["checkedAt"].str; status = j["status"].str
    }
    var timed: Bool { start.count > 10 }
    var active: Bool {
        status != "superseded" && !["Paused", "Superseded", "Removed from live calendar"].contains { note.hasPrefix($0) }
    }
}

struct Mail: Identifiable, Hashable {
    let id: String, account: String, sender: String, title: String, gist: String, body: String, priority: String, url: String, checkedAt: String, key: String, changedBy: String
    init(_ j: JSON) {
        changedBy = j["changedBy"].str
        id = j["id"].str; account = j["f"].string ?? "Mail"; sender = j["sender"].str; title = j["t"].str; gist = j["gist"].str
        body = j["b"].str; priority = j["priority"].string ?? "Normal"; url = j["url"].str; checkedAt = j["checkedAt"].str; key = j["key"].str
    }
    var senderName: String { sender.components(separatedBy: "@").first ?? sender }
}

struct FeedItem: Identifiable, Hashable {
    let id: String, category: String, colorToken: String, icon: String, when: String, title: String, desc: String, chips: [String], url: String, pinned: Bool, importance: Double?, lane: String, publishedAt: String
    init(_ j: JSON, index: Int) {
        id = j["id"].string ?? "feed-\(index + 1)"; category = j["cat"].string ?? "Feed"; colorToken = j["c"].str; icon = j["ic"].str; when = j["t"].str
        title = j["title"].str; desc = j["desc"].str; chips = j["chips"].array.map { $0[1].str }; url = j["url"].str
        pinned = j["pinned"].bool; importance = j["importance"].double; lane = j["lane"].str; publishedAt = j["publishedAt"].string ?? j["date"].string ?? j["checkedAt"].str
    }
    var isMusic: Bool { lane == "music" || category.localizedCaseInsensitiveContains("music") || category.localizedCaseInsensitiveContains("release") }
}

struct DraftWeek: Identifiable, Hashable { let id: String, title: String, days: [DraftDay] }
struct DraftDay: Identifiable, Hashable { let id = UUID(); let title: String, subtitle: String, lines: [String] }
struct DraftVersion: Hashable {
    let version: Int, createdAt: String, intro: String, scope: String, questions: [String], weeks: [DraftWeek]
    let from: String, to: String, cc: String, subject: String, body: String, by: String
    /// The draft's free text, whichever field it came in (body, markdown, text, content or notes).
    let text: String
    init(_ j: JSON) {
        func flat(_ v: JSON) -> String {
            if let s = v.string { return s }
            return v.array.map { $0.string ?? $0["text"].string ?? $0.text(pretty: true) }.joined(separator: "\n\n")
        }
        text = [j["body"], j["markdown"], j["text"], j["content"], j["notes"]].map(flat).filter { !$0.isEmpty }.joined(separator: "\n\n")
        version = j["version"].int ?? 1; createdAt = j["createdAt"].str; intro = j["intro"].str; scope = j["scope"].str
        questions = j["questions"].array.map(\.str)
        weeks = j["weeks"].array.map { w in DraftWeek(id: w["id"].str, title: w["title"].str, days: w["days"].array.map { DraftDay(title: $0["title"].str, subtitle: $0["subtitle"].str, lines: $0["lines"].array.map(\.str)) }) }
        from = j["from"].str; to = j["to"].str; cc = j["cc"].str; subject = j["subject"].str; body = j["body"].str; by = j["by"].str
    }
}
struct Draft: Identifiable, Hashable {
    let id: String, title: String, isEmail: Bool, hidden: Bool, inboxId: String, versions: [DraftVersion]
    init(_ j: JSON) {
        id = j["id"].str; title = j["title"].str; isEmail = j["type"].str == "email"; hidden = j["hidden"].bool; inboxId = j["inboxId"].str
        versions = j["versions"].array.map(DraftVersion.init).sorted { $0.version < $1.version }
    }
    var latest: DraftVersion? { versions.last }
    /// What gets reviewed: each week of a plan, or the whole draft when it has no weeks.
    var parts: [DraftWeek] {
        if isEmail { return [DraftWeek(id: "email-draft", title: "Email draft", days: [])] }
        let w = latest?.weeks ?? []
        return w.isEmpty ? [DraftWeek(id: "whole-draft", title: "Whole draft", days: [])] : w
    }
}

enum BlockKind { case timetable, study, calendar, rest }
struct Block: Identifiable, Hashable {
    let id: String, day: String, title: String, start: Date, end: Date, kind: BlockKind, detail: String
}

struct CoverageItem: Identifiable, Hashable { let id: String, text: String }
struct CoverageSet: Identifiable { var id: String { group + name }; let group: String, name: String, items: [CoverageItem] }

// MARK: colours (category tokens used in the data)
extension Color {
    static func token(_ t: String) -> Color {
        switch t.replacingOccurrences(of: "--", with: "") {
        case "violet", "accent", "indigo": return .indigo
        case "ok", "mint", "green": return .green
        case "warn", "amber", "orange": return .orange
        case "danger", "coral", "red": return .red
        case "sky", "blue": return .blue
        case "rose", "pink": return .pink
        case "teal": return .teal
        default: return .secondary
        }
    }
}

/// SF Symbol for the icon names the data uses.
func symbol(_ name: String) -> String {
    switch name {
    case "play": return "play.fill"
    case "zap": return "bolt.fill"
    case "study": return "book.closed.fill"
    case "inbox": return "tray.fill"
    case "music": return "music.note"
    case "clock": return "clock.fill"
    case "flame": return "flame.fill"
    case "tag": return "tag.fill"
    case "calendar": return "calendar"
    case "bookmark": return "bookmark.fill"
    case "wrench": return "wrench.fill"
    case "down": return "chart.line.downtrend.xyaxis"
    case "up": return "chart.line.uptrend.xyaxis"
    case "check": return "checkmark"
    case "msg": return "bubble.left.fill"
    default: return "sparkles"
    }
}
