import Foundation
import EventKit

/// Reads your iPhone calendars so study blocks never land on class, practice or plans. Each event becomes a busy
/// slot (start and end only; titles too if you allow it), synced so Instinct sees them as well.
@Observable @MainActor
final class CalendarSync {
    static let shared = CalendarSync()

    private let store = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var lastRun: Date?
    private(set) var lastCount = 0

    var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "calendar.enabled"); if enabled { Task { await run() } } } }
    var includeAllDay: Bool { didSet { UserDefaults.standard.set(includeAllDay, forKey: "calendar.allDay") } }
    /// Calendars to leave out (by identifier), e.g. a shared family calendar.
    var excluded: Set<String> { didSet { UserDefaults.standard.set(Array(excluded), forKey: "calendar.excluded") } }

    var authorized: Bool { status == .fullAccess }
    var calendars: [EKCalendar] { authorized ? store.calendars(for: .event).sorted { $0.title < $1.title } : [] }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "calendar.enabled")
        includeAllDay = UserDefaults.standard.bool(forKey: "calendar.allDay")
        excluded = Set(UserDefaults.standard.stringArray(forKey: "calendar.excluded") ?? [])
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            Task { @MainActor in await CalendarSync.shared.run() }
        }
    }

    func requestAccess() async -> Bool {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        status = EKEventStore.authorizationStatus(for: .event)
        if ok { enabled = true }
        return ok
    }

    /// Mirrors the next three weeks of events into busy slots.
    func run() async {
        status = EKEventStore.authorizationStatus(for: .event)
        guard enabled, authorized else { return }
        let app = Store.shared
        let now = Date()
        let from = Calendar.current.startOfDay(for: now)
        let to = from.addingTimeInterval(21 * 86400)
        let cals = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return }
        let events = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: cals))
        let shareTitles = app.prefs.shareCalendarTitles

        var existing: [UUID: BusySlot] = [:]
        for s in app.all(BusySlot.self) where s.source == "calendar" { existing[s.id] = s }
        var seen = Set<UUID>()
        var changed = false
        for e in events {
            guard let start = e.startDate, let end = e.endDate, end > start else { continue }
            if e.availability == .free { continue }
            if e.isAllDay && !includeAllDay { continue }
            let key = "cal:" + (e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? UUID().uuidString) + ":" + ISO.string(start)
            let id = UUID.stable(key)
            seen.insert(id)
            let title = shareTitles ? e.title : nil
            if let s = existing[id] {
                if s.trashed || s.startAt != start || s.endAt != end || s.title != title || s.allDay != e.isAllDay {
                    s.trashed = false; s.startAt = start; s.endAt = end; s.title = title; s.allDay = e.isAllDay
                    s.touch(); changed = true
                }
            } else {
                let s = BusySlot(id: id)
                s.source = "calendar"; s.startAt = start; s.endAt = end; s.title = title; s.allDay = e.isAllDay
                app.insert(s); changed = true
            }
        }
        // Events that were moved away or deleted.
        for (id, s) in existing where !seen.contains(id) && !s.trashed && s.endAt > from && s.startAt < to {
            s.trashed = true; s.touch(); changed = true
        }
        lastRun = now
        lastCount = seen.count
        if changed { app.save() }
    }

    /// Removes every calendar busy slot (when you turn this off).
    func clear() {
        let app = Store.shared
        for s in app.live(BusySlot.self) where s.source == "calendar" { s.trashed = true; s.touch() }
        app.save()
    }
}
