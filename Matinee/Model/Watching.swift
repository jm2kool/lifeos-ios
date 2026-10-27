import Foundation
import SwiftUI

/// A pause mid-film: where you stopped, how it felt, and a note to jog your memory.
struct Intermission: Codable, Hashable, Identifiable {
    var id = UUID()
    var at: TimeInterval          // position in the film, seconds
    var when = Date.now
    var mood: String              // emoji
    var note: String
}

/// A film you're partway through.
struct WatchSession: Codable, Hashable, Identifiable {
    var id = UUID()
    var film: FilmRef
    var runtimeMinutes: Int?
    var runStartedAt: Date? = .now        // nil while on intermission
    var banked: TimeInterval = 0          // position reached before the current run
    var stops: [Intermission] = []
    var started = Date.now
    // When it's an episode of a show.
    var season: Int?
    var episode: Int?
    var episodeTitle: String?
    /// The watch party's code, when you're watching together.
    var party: String?

    var episodeCode: String? {
        guard let s = season, let e = episode else { return nil }
        return EpisodeKey.code(s, e)
    }
    /// "Breaking Bad · S1 E3" for an episode, the film's title otherwise.
    var title: String { episodeCode.map { "\(film.title) · \($0)" } ?? film.title }

    /// What finishing it opens: the log sheet for the film, or for the episode.
    var logRoute: SheetRoute {
        guard let s = season, let e = episode else { return .log(film, nil) }
        return .logEpisode(LogEntry(film: film, season: s, episode: e, episodeTitle: episodeTitle))
    }

    /// Finishing it. A comfort watch is logged straight away, with no rating asked; anything else
    /// returns the log sheet to open.
    @MainActor func finish(in library: Library) -> SheetRoute? {
        guard library.isComfort(film.id) else { return logRoute }
        var e = LogEntry(film: film, season: season, episode: episode, episodeTitle: episodeTitle)
        e.rewatch = library.entries(for: film.id).contains { $0.season == season && $0.episode == episode }
        library.log(e)
        return nil
    }

    var running: Bool { runStartedAt != nil }
    func elapsed(at now: Date = .now) -> TimeInterval { banked + (runStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0) }
    var runtime: TimeInterval? { runtimeMinutes.flatMap { $0 > 0 ? TimeInterval($0 * 60) : nil } }
    func progress(at now: Date = .now) -> Double? { runtime.map { min(1, elapsed(at: now) / $0) } }
    func isProbablyOver(at now: Date = .now) -> Bool { runtime.map { elapsed(at: now) >= $0 } ?? false }
    var lastStop: Intermission? { stops.last }
}

enum Mood {
    static let all: [(emoji: String, label: String)] = [
        ("😍", "Loving it"), ("🤯", "Mind-blown"), ("😱", "Tense"), ("😂", "Fun"),
        ("🥲", "Moved"), ("🤔", "Unsure"), ("😴", "Slow")]
    static func label(_ e: String) -> String { all.first { $0.emoji == e }?.label ?? "" }
}

/// "1h 12m", "34m", "0m".
func filmClock(_ t: TimeInterval) -> String {
    let m = Int(t / 60), h = m / 60
    return h > 0 ? "\(h)h \(m % 60)m" : "\(m)m"
}

/// Films you're in the middle of. Kept on the phone in their own file, and synced with your library.
@Observable @MainActor
final class Watching {
    static let shared = Watching()
    private(set) var sessions: [WatchSession] = []

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Matinee", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("watching.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL), let s = try? Library.decoder.decode([WatchSession].self, from: data) { sessions = s }
        else if let s = Library.shared.doc.watching { sessions = s }
        // Sessions saved before they synced: send them up once.
        if Library.shared.doc.watching == nil && !sessions.isEmpty { Library.shared.storeWatching(sessions) }
    }

    /// Sessions from your account (another phone was used more recently). Running timers carry on,
    /// since they count from when they started.
    func adopt(_ s: [WatchSession]) {
        guard s != sessions else { return }
        withAnimation(.smooth) { sessions = s }
        save()
        NowWatchingActivity.sync(sessions)
    }

    private func save() {
        if let data = try? Library.encoder.encode(sessions) { try? data.write(to: Self.fileURL, options: .atomic) }
    }

    /// The session to show in the Now Watching bar: the running one, else the most recent intermission.
    var current: WatchSession? {
        sessions.first(where: \.running) ?? sessions.max { ($0.lastStop?.when ?? $0.started) < ($1.lastStop?.when ?? $1.started) }
    }
    var paused: [WatchSession] {
        sessions.filter { !$0.running }.sorted { ($0.lastStop?.when ?? $0.started) > ($1.lastStop?.when ?? $1.started) }
    }
    func session(for filmID: String) -> WatchSession? { sessions.first { $0.film.id == filmID } }

    func start(_ film: FilmRef, runtime: Int?) {
        update { s in
            // Only one film runs at a time; quietly bank whatever else was playing.
            for i in s.indices where s[i].running { s[i].banked = s[i].elapsed(); s[i].runStartedAt = nil }
            if let i = s.firstIndex(where: { $0.film.id == film.id }) {
                s[i].runStartedAt = .now
                if s[i].runtimeMinutes == nil { s[i].runtimeMinutes = runtime }
            } else {
                s.append(WatchSession(film: film, runtimeMinutes: runtime))
            }
        }
    }

    /// Start an episode. A show has one session at a time, so a different episode replaces the old one.
    func start(_ show: FilmRef, episode ep: Episode, runtime: Int?) {
        update { s in
            for i in s.indices where s[i].running { s[i].banked = s[i].elapsed(); s[i].runStartedAt = nil }
            if let i = s.firstIndex(where: { $0.film.id == show.id }) {
                if s[i].season == ep.season && s[i].episode == ep.number { s[i].runStartedAt = .now; return }
                s.remove(at: i)
            }
            var session = WatchSession(film: show, runtimeMinutes: ep.runtime ?? runtime)
            session.season = ep.season; session.episode = ep.number; session.episodeTitle = ep.name
            s.append(session)
        }
    }

    func intermission(_ id: UUID, at position: TimeInterval, mood: String, note: String) {
        update { s in
            guard let i = s.firstIndex(where: { $0.id == id }) else { return }
            s[i].banked = position
            s[i].runStartedAt = nil
            s[i].stops.append(Intermission(at: position, mood: mood, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        tellParty(id)
    }

    // MARK: Watch parties

    private func tellParty(_ id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }), s.party != nil else { return }
        Task { await Party.shared.push(s) }
    }

    func setParty(_ id: UUID, _ code: String?) {
        update { s in if let i = s.firstIndex(where: { $0.id == id }) { s[i].party = code } }
    }

    /// Someone in the party played or paused: follow along. Joining starts a session if there isn't one.
    func applyParty(_ row: PartyRow) {
        update { s in
            let i: Int
            if let found = s.firstIndex(where: { $0.film.id == row.film.id }) {
                i = found
            } else {
                var n = WatchSession(film: row.film, runtimeMinutes: row.runtimeMinutes, runStartedAt: nil)
                n.season = row.season; n.episode = row.episode; n.episodeTitle = row.episodeTitle
                s.append(n)
                i = s.count - 1
            }
            // Only one film runs at a time.
            if row.runStartedAt != nil {
                for j in s.indices where j != i && s[j].running { s[j].banked = s[j].elapsed(); s[j].runStartedAt = nil }
            }
            s[i].party = row.code
            s[i].runStartedAt = row.runStartedAt
            s[i].banked = row.banked
            if s[i].runtimeMinutes == nil { s[i].runtimeMinutes = row.runtimeMinutes }
        }
    }

    func resume(_ id: UUID) {
        guard let film = sessions.first(where: { $0.id == id })?.film else { return }
        start(film, runtime: nil)   // matches by id, so an episode session just carries on
        tellParty(id)
    }

    @discardableResult
    func end(_ id: UUID) -> WatchSession? {
        let s = sessions.first { $0.id == id }
        update { $0.removeAll { $0.id == id } }
        return s
    }

    private func update(_ change: (inout [WatchSession]) -> Void) {
        var s = sessions
        change(&s)
        withAnimation(.smooth) { sessions = s }
        save()
        NowWatchingActivity.sync(sessions)
        Library.shared.storeWatching(sessions)
    }

    func seedDemo(_ film: FilmRef) {
        var s = WatchSession(film: film, runtimeMinutes: 132, runStartedAt: nil, banked: 72 * 60)
        s.stops = [Intermission(at: 72 * 60, when: .now.addingTimeInterval(-2 * 86_400), mood: "😱", note: "right after the basement reveal")]
        s.started = .now.addingTimeInterval(-2 * 86_400 - 4_400)
        sessions = [s]
    }
}
