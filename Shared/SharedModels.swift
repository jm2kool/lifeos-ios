import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Code shared by the app and its widgets: the Live Activity for a film in progress, and the
/// watchlist snapshot the home-screen widget picks from.

enum SharedStore {
    static let appGroup = "group.com.jm2kool.matinee"
    static let widgetKind = "RandomWatchlistWidget"

    struct Film: Codable, Hashable {
        var id: String
        var title: String
        var year: Int?
        var poster: URL?
    }

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("watchlist.json")
    }

    static func saveWatchlist(_ films: [Film]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(films) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadWatchlist() -> [Film] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Film].self, from: data)) ?? []
    }

    /// Whether iOS gave this process the folder it shares with the app. Re-signing tools (Sideloadly
    /// with a free Apple ID) often drop that permission, so there's a second route through the server.
    static var hasSharedFolder: Bool { fileURL != nil }

    // MARK: Fallback: the watchlist via your account server

    struct Server { var base: String; var key: String }

    /// The account server baked into the app. The widget reads the app's own Info.plist, since
    /// it lives inside the app at Matinee.app/PlugIns/MatineeWidgets.appex.
    static func bakedServer() -> Server? {
        var bundle = Bundle.main
        if bundle.bundleURL.pathExtension == "appex",
           let app = Bundle(url: bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) { bundle = app }
        let url = (bundle.object(forInfoDictionaryKey: "MatineeSupabaseURL") as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (bundle.object(forInfoDictionaryKey: "MatineeSupabaseAnonKey") as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard URL(string: url)?.host != nil, !key.isEmpty else { return nil }
        return Server(base: url.hasSuffix("/") ? String(url.dropLast()) : url, key: key)
    }

    /// The same for the app and its widget on this iPhone (iOS gives one id per developer), so
    /// both can find the same row on the server without sharing anything else.
    @MainActor static var deviceKey: String? { UIDevice.current.identifierForVendor?.uuidString.lowercased() }

    private static func rpc(_ name: String, _ body: [String: Any], _ server: Server) async -> (Data, Int)? {
        guard let url = URL(string: server.base + "/rest/v1/rpc/" + name),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(server.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(server.key)", forHTTPHeaderField: "Authorization")
        req.httpBody = data
        guard let (out, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        return (out, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    enum PushResult { case ok, needsSetup, offline }

    static func pushRemote(_ films: [Film], device: String, server: Server) async -> PushResult {
        let list = films.prefix(300).map { f -> [String: Any] in
            var d: [String: Any] = ["id": f.id, "title": f.title]
            if let y = f.year { d["year"] = y }
            if let p = f.poster { d["poster"] = p.absoluteString }
            return d
        }
        guard let (_, code) = await rpc("widget_put", ["p_device": device, "p_films": list], server) else { return .offline }
        if (200..<300).contains(code) { return .ok }
        return code == 404 || code == 400 ? .needsSetup : .offline
    }

    static func fetchRemote(device: String, server: Server) async -> [Film]? {
        guard let (data, code) = await rpc("widget_get", ["p_device": device], server), (200..<300).contains(code) else { return nil }
        return (try? JSONDecoder().decode([Film].self, from: data)) ?? []
    }

    /// Run once in Supabase → SQL editor. Only these two functions can touch the table, and each
    /// phone only ever reads its own row (by its private device id).
    static let setupSQL = """
    create table if not exists public.widget_feeds (
      device text primary key,
      films jsonb not null default '[]',
      updated_at timestamptz not null default now()
    );
    alter table public.widget_feeds enable row level security;

    create or replace function public.widget_put(p_device text, p_films jsonb) returns void
    language sql security definer set search_path = public as $$
      insert into widget_feeds (device, films, updated_at)
      select p_device, p_films, now() where length(p_device) >= 32
      on conflict (device) do update set films = excluded.films, updated_at = now();
    $$;

    create or replace function public.widget_get(p_device text) returns jsonb
    language sql stable security definer set search_path = public as $$
      select coalesce((select films from widget_feeds where device = p_device), '[]'::jsonb);
    $$;

    grant execute on function public.widget_put(text, jsonb) to anon, authenticated;
    grant execute on function public.widget_get(text) to anon, authenticated;
    """

    /// Opens the film's page in the app.
    static func filmURL(_ f: Film) -> URL {
        var c = URLComponents()
        c.scheme = "matinee"
        c.host = "film"
        c.path = "/" + f.id
        c.queryItems = [URLQueryItem(name: "title", value: f.title)] + (f.year.map { [URLQueryItem(name: "year", value: String($0))] } ?? [])
            + (f.poster.map { [URLQueryItem(name: "poster", value: $0.absoluteString)] } ?? [])
        return c.url!
    }
}

#if canImport(ActivityKit)
/// "Now watching" on the Lock Screen and in the Dynamic Island.
struct WatchActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var runStartedAt: Date?          // nil while on intermission
        var banked: TimeInterval         // position reached before the current run
        var runtime: TimeInterval?
        var mood: String?
        var note: String?

        var running: Bool { runStartedAt != nil }
        /// When the film would have started if you'd watched without stopping — drives the live timer.
        var virtualStart: Date { (runStartedAt ?? .now).addingTimeInterval(-banked) }
    }
    var filmID: String
    var title: String
    var year: Int?
}
#endif
