import Foundation

/// Someone at a watch party.
struct PartyMember: Codable, Hashable, Identifiable {
    var userID: String
    var name: String
    var handle: String?
    var id: String { userID }
    enum CodingKeys: String, CodingKey { case userID = "user_id", name, handle }
}

/// A watch party as the account server keeps it: one shared timer everyone follows.
struct PartyRow: Codable, Hashable {
    var code: String
    var host: String
    var film: FilmRef
    var runtimeMinutes: Int?
    var season: Int?
    var episode: Int?
    var episodeTitle: String?
    var runStartedAt: Date?
    var banked: Double
    var members: [PartyMember]
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case code, host, film, season, episode, banked, members
        case runtimeMinutes = "runtime_minutes", episodeTitle = "episode_title", runStartedAt = "run_started_at", updatedAt = "updated_at"
    }

    var running: Bool { runStartedAt != nil }
    func elapsed(at now: Date = .now) -> TimeInterval { banked + (runStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0) }
    var title: String { (season.flatMap { s in episode.map { "\(film.title) · \(EpisodeKey.code(s, $0))" } }) ?? film.title }
}

/// Watch parties: start one from a film you're watching, share the link, and everyone's timer (and Live
/// Activity) stays in step. Anyone can pause or play for the room. Kept in step by checking every few seconds.
@Observable @MainActor
final class Party {
    static let shared = Party()
    private(set) var rows: [String: PartyRow] = [:]
    var error: String?

    private var me: PartyMember? {
        guard let s = Auth.shared.session else { return nil }
        let p = Library.shared.doc.profile
        return PartyMember(userID: s.userID, name: p.name.isEmpty ? (s.name ?? "Film fan") : p.name, handle: Handle.clean(p.handle))
    }

    static func link(_ code: String) -> URL { URL(string: "matinee://party/\(code)")! }

    /// Turn a film you're watching into a party. Returns its code.
    func host(_ s: WatchSession) async -> String? {
        guard let me else { error = "Sign in to host a watch party."; return nil }
        let code = String((0..<6).map { _ in Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789").randomElement()! })
        let film: Any = (try? JSONSerialization.jsonObject(with: Library.encoder.encode(s.film))) ?? [String: Any]()
        var row: [String: Any] = [
            "code": code, "host": me.userID, "film": film, "banked": s.elapsed(),
            "members": [["user_id": me.userID, "name": me.name, "handle": (me.handle as Any?) ?? NSNull()]],
            "updated_at": Supa.string(.now),
        ]
        row["runtime_minutes"] = (s.runtimeMinutes as Any?) ?? NSNull()
        row["season"] = (s.season as Any?) ?? NSNull()
        row["episode"] = (s.episode as Any?) ?? NSNull()
        row["episode_title"] = (s.episodeTitle as Any?) ?? NSNull()
        row["run_started_at"] = s.running ? Supa.string(.now) : NSNull()
        if s.running { row["banked"] = s.elapsed() }
        guard let r = await Auth.shared.rest("POST", "parties", body: row, prefer: "return=representation") else {
            error = "Couldn't reach your account server."
            return nil
        }
        guard (200..<300).contains(r.status), let created = (try? Supa.decoder.decode([PartyRow].self, from: r.data))?.first else {
            error = Supa.missingTable(r.status, r.data) ? "Watch parties need a one-time setup: Settings → Friends → Copy setup SQL." : "Couldn't start the party."
            return nil
        }
        rows[code] = created
        // The session now counts from the moment the party started.
        Watching.shared.applyParty(created)
        return code
    }

    /// Join from a link or a typed code: the film starts (or pauses) wherever the room is.
    func join(_ code: String) async -> Bool {
        let code = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count == 6 else { error = "Party codes are six letters and numbers."; return false }
        guard let me else { error = "Sign in to join a watch party."; return false }
        guard var row = await fetch(code) else {
            if error == nil { error = "No party with the code \(code). It may have ended." }
            return false
        }
        if !row.members.contains(where: { $0.userID == me.userID }) {
            row.members.append(me)
            let members = row.members.map { m -> [String: Any] in ["user_id": m.userID, "name": m.name, "handle": (m.handle as Any?) ?? NSNull()] }
            _ = await Auth.shared.rest("PATCH", "parties", query: ["code": "eq.\(code)"], body: ["members": members], prefer: "return=minimal")
        }
        rows[code] = row
        Watching.shared.applyParty(row)
        return true
    }

    /// Leave the party (the host ends it for everyone). Your own timer carries on.
    func leave(_ code: String) async {
        guard let me else { return }
        if let s = Watching.shared.sessions.first(where: { $0.party == code }) { Watching.shared.setParty(s.id, nil) }
        if let row = rows[code] {
            if row.host == me.userID {
                _ = await Auth.shared.rest("DELETE", "parties", query: ["code": "eq.\(code)"])
            } else {
                let members = row.members.filter { $0.userID != me.userID }
                    .map { m -> [String: Any] in ["user_id": m.userID, "name": m.name, "handle": (m.handle as Any?) ?? NSNull()] }
                _ = await Auth.shared.rest("PATCH", "parties", query: ["code": "eq.\(code)"], body: ["members": members], prefer: "return=minimal")
            }
        }
        rows[code] = nil
    }

    /// You played or paused: tell the room.
    func push(_ s: WatchSession) async {
        guard let code = s.party else { return }
        let body: [String: Any] = [
            "run_started_at": s.runStartedAt.map { Supa.string($0) as Any } ?? NSNull(),
            "banked": s.banked,
            "updated_at": Supa.string(.now),
        ]
        guard let r = await Auth.shared.rest("PATCH", "parties", query: ["code": "eq.\(code)"], body: body, prefer: "return=representation"),
              (200..<300).contains(r.status), let row = (try? Supa.decoder.decode([PartyRow].self, from: r.data))?.first else { return }
        rows[code] = row
    }

    private func fetch(_ code: String) async -> PartyRow? {
        guard let r = await Auth.shared.rest("GET", "parties", query: ["code": "eq.\(code)", "limit": "1"]) else {
            error = "Couldn't reach your account server."
            return nil
        }
        if Supa.missingTable(r.status, r.data) { error = "Watch parties aren't set up on this account server yet."; return nil }
        return (try? Supa.decoder.decode([PartyRow].self, from: r.data))?.first
    }

    /// Keep every party you're in up to date. Runs for as long as the app is open.
    func run() async {
        while !Task.isCancelled {
            let codes = Set(Watching.shared.sessions.compactMap(\.party))
            for code in codes {
                if let row = await fetch(code) {
                    let old = rows[code]
                    rows[code] = row
                    if old?.updatedAt != row.updatedAt || old == nil {
                        if let s = Watching.shared.sessions.first(where: { $0.party == code }),
                           s.runStartedAt != row.runStartedAt || abs(s.banked - row.banked) > 1 {
                            Watching.shared.applyParty(row)
                        }
                    }
                } else if error == nil, let s = Watching.shared.sessions.first(where: { $0.party == code }) {
                    // The host ended it.
                    Watching.shared.setParty(s.id, nil)
                    rows[code] = nil
                    Library.shared.toast = Toast(text: "The watch party ended", symbol: "person.3")
                }
                error = nil
            }
            try? await Task.sleep(for: .seconds(codes.isEmpty ? 15 : 5))
        }
    }
}
