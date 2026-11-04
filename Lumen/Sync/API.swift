import Foundation

struct APIError: LocalizedError {
    var status: Int
    var message: String
    var code: String?
    var errorDescription: String? { message }

    /// The `lumen` schema isn't exposed in the Data API, or the migration hasn't been run.
    var needsSetup: Bool {
        code == "PGRST106" || code == "PGRST205" || code == "42P01" || code == "3F000"
            || message.contains("schema must be one of") || message.contains("Could not find the table")
    }
}

/// Talks to Supabase: the Data API (PostgREST) for the `lumen` schema, Storage for files and Edge Functions.
@MainActor
enum API {
    static var auth: Auth { Auth.shared }

    static func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Any? = nil,
                        headers: [String: String] = [:], profile: Bool = true, raw: Data? = nil,
                        timeout: TimeInterval = 30) async throws -> (Data, Int) {
        guard auth.configured, var c = URLComponents(string: auth.base + path) else {
            throw APIError(status: 0, message: "No server set up yet.")
        }
        if !query.isEmpty { c.queryItems = query }
        guard let url = c.url else { throw APIError(status: 0, message: "Bad address.") }
        await auth.refreshIfNeeded()
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue(auth.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(auth.session?.accessToken ?? auth.anonKey)", forHTTPHeaderField: "Authorization")
        if profile {
            req.setValue("lumen", forHTTPHeaderField: "Accept-Profile")
            req.setValue("lumen", forHTTPHeaderField: "Content-Profile")
        }
        if let raw {
            req.httpBody = raw
        } else if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch {
            throw APIError(status: 0, message: "You're offline.")
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let msg = (obj["message"] ?? obj["error_description"] ?? obj["error"] ?? obj["msg"]) as? String
            throw APIError(status: status, message: msg ?? "Server error \(status).", code: obj["code"] as? String)
        }
        return (data, status)
    }

    // MARK: Data API

    static func select(_ table: String, _ query: [(String, String)]) async throws -> [[String: Any]] {
        let (data, _) = try await request("GET", "/rest/v1/\(table)", query: query.map { URLQueryItem(name: $0.0, value: $0.1) })
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// Insert or update by id. The server skips any row older than what it has (last write wins).
    static func upsert(_ table: String, rows: [[String: Any]]) async throws {
        guard !rows.isEmpty else { return }
        _ = try await request("POST", "/rest/v1/\(table)", query: [URLQueryItem(name: "on_conflict", value: "id")], body: rows,
                              headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    static func insert(_ table: String, _ row: [String: Any]) async throws -> [String: Any]? {
        let (data, _) = try await request("POST", "/rest/v1/\(table)", body: row, headers: ["Prefer": "return=representation"])
        return ((try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]])?.first
    }

    static func patch(_ table: String, id: String, _ values: [String: Any]) async throws {
        _ = try await request("PATCH", "/rest/v1/\(table)", query: [URLQueryItem(name: "id", value: "eq.\(id)")], body: values,
                              headers: ["Prefer": "return=minimal"])
    }

    static func delete(_ table: String, id: String) async throws {
        _ = try await request("DELETE", "/rest/v1/\(table)", query: [URLQueryItem(name: "id", value: "eq.\(id)")])
    }

    @discardableResult
    static func rpc(_ name: String, _ params: [String: Any]) async throws -> Any? {
        let (data, _) = try await request("POST", "/rest/v1/rpc/\(name)", body: params)
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    // MARK: Edge Functions

    static func function(_ name: String, body: [String: Any], timeout: TimeInterval = 90) async throws -> [String: Any] {
        let (data, _) = try await request("POST", "/functions/v1/\(name)", body: body, profile: false, timeout: timeout)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: Storage (bucket lumen-files, one folder per person)

    static let bucket = "lumen-files"

    static func upload(_ path: String, data: Data, mime: String) async throws {
        _ = try await request("POST", "/storage/v1/object/\(bucket)/\(path)", headers: ["Content-Type": mime, "x-upsert": "true"],
                              profile: false, raw: data, timeout: 120)
    }

    static func download(_ path: String) async throws -> Data {
        let (data, _) = try await request("GET", "/storage/v1/object/authenticated/\(bucket)/\(path)", profile: false, timeout: 120)
        return data
    }

    static func removeFile(_ path: String) async {
        _ = try? await request("DELETE", "/storage/v1/object/\(bucket)/\(path)", profile: false)
    }
}
