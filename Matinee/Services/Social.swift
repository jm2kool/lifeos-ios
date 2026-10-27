import Foundation

/// Dates as the account server sends them: ISO 8601, with or without fractions of a second.
enum Supa {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = precise.date(from: s) ?? plain.date(from: s) ?? day.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    static func string(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    /// The server answered "no such table", so the SQL in Settings hasn't been run yet.
    static func missingTable(_ status: Int, _ data: Data) -> Bool {
        status == 404 || (status == 400 && String(decoding: data, as: UTF8.self).contains("PGRST205"))
            || String(decoding: data, as: UTF8.self).contains("42P01")
    }
}

/// One diary entry someone shared with the people who follow them.
struct FeedItem: Codable, Identifiable, Hashable {
    var id: UUID
    var userID: String
    var film: FilmRef
    var rating: Double?
    var liked: Bool
    var rewatch: Bool
    var review: String
    var episode: String?
    var watchedOn: Date
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userID = "user_id", film, rating, liked, rewatch, review, episode, watchedOn = "watched_on", createdAt = "created_at"
    }
}

/// Following people, and the feed of what they've watched. Your own diary is shared only if you
/// switch it on (Settings → Friends); until then nothing leaves your private library.
@Observable @MainActor
final class Social {
    static let shared = Social()
    static let shareActivityKey = "shareActivity"
    static let shareWatchlistKey = "shareWatchlist"

    private(set) var following: Set<String> = []
    private(set) var feed: [FeedItem] = []
    private(set) var people: [String: PublicProfile] = [:]
    private(set) var loadingFeed = false
    /// The follows and activity tables aren't on the account server yet.
    private(set) var needsSetup = false
    @ObservationIgnored private var loadedFollowing = false

    var shareActivity: Bool { UserDefaults.standard.bool(forKey: Self.shareActivityKey) }

    private var me: String? { Auth.shared.session?.userID }

    // MARK: Following

    func refreshFollowing() async {
        guard let me, let r = await Auth.shared.rest("GET", "follows", query: ["follower": "eq.\(me)", "select": "followee"]) else { return }
        if Supa.missingTable(r.status, r.data) { needsSetup = true; return }
        guard r.status == 200, let rows = try? JSONSerialization.jsonObject(with: r.data) as? [[String: Any]] else { return }
        needsSetup = false
        following = Set(rows.compactMap { $0["followee"] as? String })
        loadedFollowing = true
    }

    func isFollowing(_ userID: String) -> Bool { following.contains(userID) }

    func toggleFollow(_ p: PublicProfile) async {
        guard let me, p.userID != me else { return }
        let on = !isFollowing(p.userID)
        // Show it straight away; put it back if the server says no.
        if on { following.insert(p.userID) } else { following.remove(p.userID) }
        let r: (data: Data, status: Int)?
        if on {
            r = await Auth.shared.rest("POST", "follows", body: ["follower": me, "followee": p.userID],
                                       prefer: "resolution=ignore-duplicates,return=minimal")
        } else {
            r = await Auth.shared.rest("DELETE", "follows", query: ["follower": "eq.\(me)", "followee": "eq.\(p.userID)"])
        }
        guard let r, (200..<300).contains(r.status) else {
            if on { following.remove(p.userID) } else { following.insert(p.userID) }
            if let r, Supa.missingTable(r.status, r.data) { needsSetup = true }
            Library.shared.toast = Toast(text: "Couldn't \(on ? "follow" : "unfollow") right now", symbol: "exclamationmark.triangle")
            return
        }
        people[p.userID] = p
        Library.shared.toast = Toast(text: on ? "Following \(p.handle.map { "@\($0)" } ?? p.name)" : "Unfollowed", symbol: on ? "person.badge.plus" : "person.badge.minus")
        if on { await loadFeed() } else { feed.removeAll { $0.userID == p.userID } }
    }

    /// Followers and following for a profile.
    func counts(_ userID: String) async -> (followers: Int, following: Int)? {
        async let a = count(["followee": "eq.\(userID)"])
        async let b = count(["follower": "eq.\(userID)"])
        guard let x = await a, let y = await b else { return nil }
        return (x, y)
    }

    private func count(_ q: [String: String]) async -> Int? {
        var q = q
        q["select"] = "follower"
        q["limit"] = "5000"
        guard let r = await Auth.shared.rest("GET", "follows", query: q),
              r.status == 200, let rows = try? JSONSerialization.jsonObject(with: r.data) as? [Any] else { return nil }
        return rows.count
    }

    /// Who follows someone, or who they follow.
    func list(_ userID: String, followers: Bool) async -> [PublicProfile] {
        let key = followers ? "followee" : "follower", other = followers ? "follower" : "followee"
        guard let r = await Auth.shared.rest("GET", "follows", query: [key: "eq.\(userID)", "select": other, "limit": "200"]),
              r.status == 200, let rows = try? JSONSerialization.jsonObject(with: r.data) as? [[String: Any]] else { return [] }
        let ids = rows.compactMap { $0[other] as? String }
        return await Auth.shared.profiles(ids: ids)
    }

    // MARK: Feed

    func loadFeed() async {
        guard Auth.shared.signedIn else { return }
        if !loadedFollowing { await refreshFollowing() }
        guard !following.isEmpty else { feed = []; return }
        loadingFeed = true
        defer { loadingFeed = false }
        let ids = following.sorted().joined(separator: ",")
        let items = await activity(["user_id": "in.(\(ids))", "order": "created_at.desc", "limit": "80"])
        let missing = Set(items.map(\.userID)).filter { people[$0] == nil }
        for p in await Auth.shared.profiles(ids: Array(missing)) { people[p.userID] = p }
        feed = items
    }

    func activity(of userID: String) async -> [FeedItem] {
        await activity(["user_id": "eq.\(userID)", "order": "created_at.desc", "limit": "30"])
    }

    private func activity(_ q: [String: String]) async -> [FeedItem] {
        guard let r = await Auth.shared.rest("GET", "activity", query: q) else { return [] }
        if Supa.missingTable(r.status, r.data) { needsSetup = true; return [] }
        guard r.status == 200 else { return [] }
        return (try? Supa.decoder.decode([FeedItem].self, from: r.data)) ?? []
    }

    // MARK: Sharing your own diary

    /// Share a diary entry with your followers (only when you've switched that on). Logging the same
    /// entry again after editing it updates the shared copy.
    func post(_ e: LogEntry) async {
        guard shareActivity, let me else { return }
        let film: Any = (try? JSONSerialization.jsonObject(with: Library.encoder.encode(e.film))) ?? [String: Any]()
        var row: [String: Any] = [
            "id": e.id.uuidString.lowercased(), "user_id": me, "film": film, "liked": e.liked, "rewatch": e.rewatch,
            "review": e.review, "watched_on": Supa.string(e.watchedOn), "created_at": Supa.string(e.createdAt),
        ]
        row["rating"] = (e.rating as Any?) ?? NSNull()
        row["episode"] = (e.episodeLabel as Any?) ?? NSNull()
        if let r = await Auth.shared.rest("POST", "activity", query: ["on_conflict": "id"], body: row,
                                          prefer: "resolution=merge-duplicates,return=minimal"),
           Supa.missingTable(r.status, r.data) { needsSetup = true }
    }

    func unpost(_ e: LogEntry) async {
        guard Auth.shared.signedIn else { return }
        _ = await Auth.shared.rest("DELETE", "activity", query: ["id": "eq.\(e.id.uuidString.lowercased())"])
    }

    /// Share what's already in your diary (the latest 50 entries) when you first switch sharing on.
    func backfill(_ library: Library) async {
        for e in library.entries.prefix(50) { await post(e) }
    }

    // MARK: Setup

    /// Run once in Supabase → SQL Editor: follows, the activity feed, watch parties, and the profile
    /// columns for a shared watchlist and film character.
    static let setupSQL = """
    -- Matinee: friends, feed and watch parties. Safe to run more than once.
    create table if not exists public.follows (
      follower uuid not null references auth.users on delete cascade default auth.uid(),
      followee uuid not null references auth.users on delete cascade,
      created_at timestamptz not null default now(),
      primary key (follower, followee)
    );
    alter table public.follows enable row level security;
    drop policy if exists "follows are public" on public.follows;
    create policy "follows are public" on public.follows for select to anon, authenticated using (true);
    drop policy if exists "follow as yourself" on public.follows;
    create policy "follow as yourself" on public.follows for insert to authenticated with check ((select auth.uid()) = follower);
    drop policy if exists "unfollow as yourself" on public.follows;
    create policy "unfollow as yourself" on public.follows for delete to authenticated using ((select auth.uid()) = follower);

    create table if not exists public.activity (
      id uuid primary key,
      user_id uuid not null references auth.users on delete cascade default auth.uid(),
      film jsonb not null,
      rating double precision,
      liked boolean not null default false,
      rewatch boolean not null default false,
      review text not null default '',
      episode text,
      watched_on timestamptz not null default now(),
      created_at timestamptz not null default now()
    );
    create index if not exists activity_user_time on public.activity (user_id, created_at desc);
    alter table public.activity enable row level security;
    drop policy if exists "activity is public" on public.activity;
    create policy "activity is public" on public.activity for select to anon, authenticated using (true);
    drop policy if exists "share own activity" on public.activity;
    create policy "share own activity" on public.activity for insert to authenticated with check ((select auth.uid()) = user_id);
    drop policy if exists "edit own activity" on public.activity;
    create policy "edit own activity" on public.activity for update to authenticated
      using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
    drop policy if exists "delete own activity" on public.activity;
    create policy "delete own activity" on public.activity for delete to authenticated using ((select auth.uid()) = user_id);

    create table if not exists public.parties (
      code text primary key check (code ~ '^[A-Z0-9]{6}$'),
      host uuid not null references auth.users on delete cascade default auth.uid(),
      film jsonb not null,
      runtime_minutes int,
      season int,
      episode int,
      episode_title text,
      run_started_at timestamptz,
      banked double precision not null default 0,
      members jsonb not null default '[]',
      updated_at timestamptz not null default now()
    );
    alter table public.parties enable row level security;
    drop policy if exists "parties by code" on public.parties;
    create policy "parties by code" on public.parties for select to authenticated using (true);
    drop policy if exists "host a party" on public.parties;
    create policy "host a party" on public.parties for insert to authenticated with check ((select auth.uid()) = host);
    drop policy if exists "guests play and pause" on public.parties;
    create policy "guests play and pause" on public.parties for update to authenticated using (true) with check (true);
    drop policy if exists "host ends the party" on public.parties;
    create policy "host ends the party" on public.parties for delete to authenticated using ((select auth.uid()) = host);

    alter table public.profiles add column if not exists watchlist jsonb;
    alter table public.profiles add column if not exists persona jsonb;
    notify pgrst, 'reload schema';
    """
}
