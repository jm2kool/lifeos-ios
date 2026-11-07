import Foundation

/// Turns play-count snapshots and the in-app play log into plays per item per day (SPEC §6.12):
/// - plays in a period = count deltas inside it; a delta spanning several days is spread over them by time
/// - completed in-app plays are timed exactly and taken out of the matching delta so nothing counts twice
/// - mixtape plays come only from the play log
struct PlayHistory: Sendable {
    struct Info: Sendable { var title: String; var artist: String; var album: String; var albumKey: String; var genre: String; var duration: Double; var albumID: UInt64? }

    /// Plays by day (start of day) and item ID ("lib-…" / "loc-…").
    var days: [Date: [String: Double]] = [:]
    var info: [String: Info] = [:]
    /// The first day each item was played since recording began.
    var firstPlayed: [String: Date] = [:]
    var baseline: Date?

    struct Snap: Sendable { let pid: UInt64; let date: Date; let count: Int }
    struct Event: Sendable { let itemID: String; let pid: UInt64?; let date: Date; let completed: Bool; let info: Info }

    static func build(snaps: [Snap], events: [Event], songs: LibrarySnapshot, baseline: Date?) -> PlayHistory {
        var h = PlayHistory()
        h.baseline = baseline
        let cal = Calendar.current
        func add(_ id: String, _ plays: Double, on day: Date) {
            guard plays > 0 else { return }
            let d = cal.startOfDay(for: day)
            h.days[d, default: [:]][id, default: 0] += plays
            if h.firstPlayed[id].map({ d < $0 }) ?? true { h.firstPlayed[id] = d }
        }

        // In-app plays: exact.
        var completedByPID: [UInt64: [Date]] = [:]
        for e in events where e.completed {
            h.info[e.itemID] = h.info[e.itemID] ?? e.info
            add(e.itemID, 1, on: e.date)
            if let pid = e.pid { completedByPID[pid, default: []].append(e.date) }
        }

        // Snapshot deltas.
        let bySong = Dictionary(grouping: snaps, by: \.pid)
        for (pid, rows) in bySong {
            let sorted = rows.sorted { $0.date < $1.date }
            let id = "lib-\(pid)"
            if let s = songs.songs([pid]).first {
                h.info[id] = Info(title: s.title, artist: s.albumArtist, album: s.albumTitle, albumKey: "album-\(s.albumID)",
                                  genre: s.genre, duration: s.duration, albumID: s.albumID)
            }
            var previous: Snap?
            for row in sorted {
                defer { previous = row }
                guard let prev = previous else {
                    // A song first seen after the baseline was added later: all its plays are new.
                    if let b = baseline, row.date > b.addingTimeInterval(60), let s = songs.songs([pid]).first, s.dateAdded > b {
                        spread(id, Double(row.count) - inApp(completedByPID[pid], from: s.dateAdded, to: row.date), from: s.dateAdded, to: row.date, add: add)
                    }
                    continue
                }
                let delta = Double(row.count - prev.count) - inApp(completedByPID[pid], from: prev.date, to: row.date)
                spread(id, delta, from: prev.date, to: row.date, add: add)
            }
        }
        return h
    }

    private static func inApp(_ dates: [Date]?, from: Date, to: Date) -> Double {
        Double(dates?.filter { $0 > from && $0 <= to }.count ?? 0)
    }

    /// Spreads plays over the days between two snapshots, in proportion to time.
    private static func spread(_ id: String, _ plays: Double, from: Date, to: Date, add: (String, Double, Date) -> Void) {
        guard plays > 0 else { return }
        let total = to.timeIntervalSince(from)
        guard total > 3600 else { add(id, plays, to); return }
        let cal = Calendar.current
        var cursor = from
        while cursor < to {
            let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: cursor)) ?? to
            let end = min(nextDay, to)
            add(id, plays * end.timeIntervalSince(cursor) / total, cursor)
            cursor = end
        }
    }

    func plays(in range: Range<Date>) -> [String: Double] {
        var out: [String: Double] = [:]
        for (day, items) in days where range.contains(day) {
            for (id, n) in items { out[id, default: 0] += n }
        }
        return out
    }
}

/// A recap period: a week (Mon–Sun), a month or a year.
struct RecapPeriod: Hashable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable { case week = "Week", month = "Month", year = "Year" }
    let kind: Kind
    let range: Range<Date>
    var id: String { "\(kind.rawValue)-\(range.lowerBound.timeIntervalSince1970)" }

    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        c.locale = .current
        return c
    }

    static func containing(_ date: Date, kind: Kind) -> RecapPeriod {
        let cal = calendar
        let component: Calendar.Component = kind == .week ? .weekOfYear : (kind == .month ? .month : .year)
        let interval = cal.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 86_400 * 7)
        return RecapPeriod(kind: kind, range: interval.start..<interval.end)
    }

    var previous: RecapPeriod { .containing(range.lowerBound.addingTimeInterval(-3600), kind: kind) }

    /// Every period from the baseline to now, newest first.
    static func all(_ kind: Kind, since baseline: Date) -> [RecapPeriod] {
        var list: [RecapPeriod] = []
        var p = containing(.now, kind: kind)
        while p.range.upperBound > baseline && list.count < 400 {
            list.append(p)
            p = p.previous
        }
        return list
    }

    var title: String {
        let start = range.lowerBound
        switch kind {
        case .week:
            let end = range.upperBound.addingTimeInterval(-1)
            return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        case .month: return start.formatted(.dateTime.month(.wide).year())
        case .year: return start.formatted(.dateTime.year())
        }
    }

    var isCurrent: Bool { range.contains(.now) }
}
