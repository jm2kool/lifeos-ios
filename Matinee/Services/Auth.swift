import Foundation
import CryptoKit
import Security

/// Sign-in through Supabase Auth: Apple, Google and the other providers run in a secure browser sheet with
/// PKCE, so no SDK (and no client secret) lives in the app; email and password go straight to the server.
/// Without signing in, everything stays on the phone.
@Observable @MainActor
final class Auth {
    static let shared = Auth()

    enum Provider: String, CaseIterable, Identifiable {
        case apple, google, github, discord, twitter, facebook, azure, spotify
        var id: String { rawValue }
        var name: String {
            switch self {
            case .apple: return "Apple"
            case .google: return "Google"
            case .github: return "GitHub"
            case .discord: return "Discord"
            case .twitter: return "X"
            case .facebook: return "Facebook"
            case .azure: return "Microsoft"
            case .spotify: return "Spotify"
            }
        }
        /// A short mark drawn in the button (brand logos aren't bundled).
        var mark: String {
            switch self {
            case .apple: return ""
            case .google: return "G"
            case .github: return "GH"
            case .discord: return "D"
            case .twitter: return "𝕏"
            case .facebook: return "f"
            case .azure: return "M"
            case .spotify: return "S"
            }
        }
        var symbol: String? { self == .apple ? "apple.logo" : nil }
    }

    struct Session: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var email: String?
        var name: String?
        var avatar: URL?
        var provider: String?
    }

    private(set) var session: Session? { didSet { save() } }
    var isGuest: Bool { didSet { UserDefaults.standard.set(isGuest, forKey: "guest") } }
    var busy: String?
    var error: String?

    var needsOnboarding: Bool { session == nil && !isGuest }
    var signedIn: Bool { session != nil }

    var serverURL: String {
        get { setting("supabaseURL", plist: "MatineeSupabaseURL") }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "supabaseURL") }
    }
    var anonKey: String {
        get { setting("supabaseKey", plist: "MatineeSupabaseAnonKey") }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "supabaseKey") }
    }
    var configured: Bool { URL(string: serverURL)?.host != nil && !anonKey.isEmpty }
    /// The server was typed in Settings rather than built into the app.
    var serverIsCustom: Bool { !(UserDefaults.standard.string(forKey: "supabaseURL") ?? "").isEmpty }

    /// The sign-in methods switched on in the account server (nil until asked, or if it couldn't be reached).
    private(set) var enabledProviders: Set<String>?
    var emailEnabled: Bool { enabledProviders?.contains("email") ?? true }

    static let callbackScheme = "matinee"
    static let redirect = "matinee://auth-callback"

    private init() {
        isGuest = UserDefaults.standard.bool(forKey: "guest")
        if let data = Keychain.read("session"), let s = try? JSONDecoder().decode(Session.self, from: data) { session = s }
    }

    private func setting(_ key: String, plist: String) -> String {
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        if !saved.isEmpty { return saved }
        return ((Bundle.main.object(forInfoDictionaryKey: plist) as? String) ?? "").trimmingCharacters(in: .whitespaces)
    }

    private func save() {
        if let s = session, let data = try? JSONEncoder().encode(s) { Keychain.write("session", data) } else { Keychain.delete("session") }
    }

    private var base: String { serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL }

    // MARK: OAuth (PKCE)

    struct PendingOAuth { let url: URL; let verifier: String }

    func begin(_ p: Provider) -> PendingOAuth? {
        guard configured else { error = "Add your account server first: Settings → Account server."; return nil }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: base + "/auth/v1/authorize")!
        c.queryItems = [
            .init(name: "provider", value: p.rawValue),
            .init(name: "redirect_to", value: Self.redirect),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "s256"),
        ]
        if p == .google { c.queryItems?.append(.init(name: "prompt", value: "select_account")) }
        return c.url.map { PendingOAuth(url: $0, verifier: verifier) }
    }

    func finish(callback: URL, verifier: String) async {
        let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        var items = comps?.queryItems ?? []
        if let frag = comps?.fragment, let f = URLComponents(string: "?" + frag)?.queryItems { items += f }
        if let desc = items.first(where: { $0.name == "error_description" })?.value ?? items.first(where: { $0.name == "error" })?.value {
            error = desc.replacingOccurrences(of: "+", with: " ")
            return
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else { error = "Sign-in was cancelled."; return }
        await token(grant: "pkce", body: ["auth_code": code, "code_verifier": verifier])
    }

    // MARK: Email

    func email(_ email: String, password: String, create: Bool) async {
        guard configured else { error = "Add your account server in Settings first."; return }
        busy = "email"; defer { busy = nil }
        if create {
            guard let r = try? await post("/auth/v1/signup", ["email": email, "password": password]) else { return }
            if r["access_token"].str != nil { adopt(r) } else {
                error = "Check your inbox to confirm your email, then sign in."
            }
        } else {
            await token(grant: "password", body: ["email": email, "password": password])
        }
    }

    func resetPassword(_ email: String) async {
        guard configured else { return }
        _ = try? await post("/auth/v1/recover", ["email": email])
        error = "If that email has an account, a reset link is on its way."
    }

    // MARK: Session

    @ObservationIgnored private var refreshing: Task<Void, Never>?

    /// Swap an expiring access token for a fresh one. Calls that arrive while one is under way wait for it,
    /// so the single-use refresh token is only ever spent once.
    func refreshIfNeeded() async {
        guard let s = session, s.expiresAt.timeIntervalSinceNow < 120 else { return }
        if let running = refreshing { await running.value; return }
        let t = Task { await refresh(s.refreshToken) }
        refreshing = t
        await t.value
        refreshing = nil
    }

    /// Only a server that says the refresh token is no good ends the session. Being offline, or the server
    /// having a bad moment, never signs you out.
    private func refresh(_ token: String) async {
        guard configured, let url = URL(string: base + "/auth/v1/token?grant_type=refresh_token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": token])
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let code = (resp as? HTTPURLResponse)?.statusCode else { return }
        let j = J(try? JSONSerialization.jsonObject(with: data))
        if (200..<300).contains(code), j["access_token"].str != nil {
            let err = error
            adopt(j)
            error = err
        } else if code == 400 || code == 401 || code == 403 {
            session = nil
        }
    }

    func continueAsGuest() { isGuest = true }

    /// Which sign-in methods the account server has switched on, so the sign-in screen only offers those.
    func loadProviders() async {
        guard configured, let url = URL(string: base + "/auth/v1/settings") else { enabledProviders = nil; return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let external = obj["external"] as? [String: Any] else { return }
        enabledProviders = Set(external.compactMap { k, v in (v as? Bool) == true ? k : nil })
    }

    /// Point Matinee at a different account server (or back at the built-in one, with empty fields).
    func setServer(url: String, key: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty && !u.lowercased().hasPrefix("http") { u = "https://" + u }
        if session != nil && u != serverURL { signOut() }
        serverURL = u
        anonKey = key
        enabledProviders = nil
        error = nil
    }

    func signOut() {
        if let s = session, configured, let url = URL(string: base + "/auth/v1/logout") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req).resume()
        }
        session = nil
        isGuest = false
    }

    /// Deletes your account and everything synced to it. With the server's `delete_my_account` function (in the
    /// Friends setup SQL) the sign-in itself goes; without it, your library, profile, follows and shared diary are
    /// removed and you're signed out. Returns nil on success, or what went wrong.
    func deleteAccount() async -> String? {
        guard let s = session, configured else { return "You're not signed in." }
        await refreshIfNeeded()
        let me = s.userID
        guard let r = await rest("POST", "rpc/delete_my_account", body: [String: Any]()) else {
            return "Couldn't reach the account server. Check your connection and try again."
        }
        var full = (200..<300).contains(r.status)
        if !full {
            // An older server without the function: remove every row that's yours instead.
            var ok = true
            for (table, column) in [("libraries", "user_id"), ("profiles", "user_id"), ("activity", "user_id"), ("follows", "follower")] {
                guard let d = await rest("DELETE", table, query: [column: "eq.\(me)"]) else { ok = false; continue }
                if !(200..<300).contains(d.status) && !Supa.missingTable(d.status, d.data) { ok = false }
            }
            guard ok else { return "Couldn't delete everything. Try again in a moment." }
            full = false
        }
        session = nil
        isGuest = false
        lastProfilePush = nil
        return full ? nil : "Your library, profile and posts are deleted. Your sign-in can only be removed by whoever runs the account server — ask them, or run the updated setup SQL from Settings → Friends."
    }

    private func token(grant: String, body: [String: String]) async {
        busy = busy ?? grant
        defer { if busy == grant { busy = nil } }
        guard let r = try? await post("/auth/v1/token?grant_type=\(grant)", body) else { return }
        adopt(r)
    }

    private func adopt(_ r: J) {
        guard let access = r["access_token"].str, let refresh = r["refresh_token"].str else {
            error = r["error_description"].str ?? r["msg"].str ?? "Sign-in failed."
            return
        }
        let u = r["user"], meta = u["user_metadata"]
        session = Session(
            accessToken: access, refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(Double(r["expires_in"].int ?? 3600)),
            userID: u["id"].str ?? "", email: u["email"].str,
            name: meta["full_name"].str ?? meta["name"].str ?? meta["user_name"].str ?? meta["preferred_username"].str,
            avatar: (meta["avatar_url"].str ?? meta["picture"].str).flatMap(URL.init(string:)),
            provider: u["app_metadata"]["provider"].str)
        error = nil
        isGuest = false
    }

    @discardableResult
    func post(_ path: String, _ body: [String: String]) async throws -> J {
        guard let url = URL(string: base + path) else { error = "The account server address doesn't look right."; throw CatalogError.offline }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let j = J(try? JSONSerialization.jsonObject(with: data))
            if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                error = j["error_description"].str ?? j["msg"].str ?? j["message"].str ?? "Sign-in failed (\(h.statusCode))."
                throw CatalogError.http(h.statusCode)
            }
            return j
        } catch let e as CatalogError { throw e } catch {
            self.error = "Couldn't reach the account server."
            throw CatalogError.offline
        }
    }

    // MARK: Cloud sync of the library (optional table, see README)

    func pushLibrary(_ doc: Data) async {
        await refreshIfNeeded()
        guard let s = session, configured, let json = try? JSONSerialization.jsonObject(with: doc),
              let url = URL(string: base + "/rest/v1/libraries?on_conflict=user_id") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": s.userID, "doc": json, "updated_at": ISO8601DateFormatter().string(from: .now)])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// What the account holds: your library, nothing yet (a new account), or no answer.
    enum LibraryPull { case found(Data), empty, failed }

    func pullLibrary() async -> LibraryPull {
        await refreshIfNeeded()
        guard let s = session, configured,
              let url = URL(string: base + "/rest/v1/libraries?select=doc&user_id=eq.\(s.userID)") else { return .failed }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return .failed }
        guard let doc = rows.first?["doc"] else { return .empty }
        guard let out = try? JSONSerialization.data(withJSONObject: doc) else { return .failed }
        return .found(out)
    }

    // MARK: Public profiles (the profiles table, see README)

    enum ProfilePush { case ok, handleTaken, failed }

    /// Publish how you appear to others. Only sent when it changed since the last successful push.
    @discardableResult
    func pushProfile(_ profile: PublicProfile) async -> ProfilePush {
        guard let body = try? JSONEncoder().encode(profile) else { return .failed }
        if body == lastProfilePush { return .ok }
        await refreshIfNeeded()
        guard let s = session, configured, profile.userID == s.userID,
              let url = URL(string: base + "/rest/v1/profiles?on_conflict=user_id") else { return .failed }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = body
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let code = (resp as? HTTPURLResponse)?.statusCode else { return .failed }
        if (200..<300).contains(code) { lastProfilePush = body; return .ok }
        // A server set up before the watchlist and persona columns existed: publish without them.
        if code == 400, PublicProfile.sendsExtras {
            PublicProfile.sendsExtras = false
            return await pushProfile(profile)
        }
        return code == 409 ? .handleTaken : .failed
    }
    @ObservationIgnored private var lastProfilePush: Data?

    /// People by username or name. Readable without signing in.
    func searchProfiles(_ q: String) async -> [PublicProfile] {
        let term = q.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
            .filter { $0.isLetter || $0.isNumber || " _.-".contains($0) }
        guard !term.isEmpty else { return [] }
        let pattern = "*\(term)*"
        return await profiles(["or": "(handle.ilike.\(pattern),name.ilike.\(pattern))", "limit": "20",
                               "select": "user_id,handle,name,bio,avatar_url,avatar_data"])
    }

    func profile(handle: String) async -> PublicProfile? {
        guard let h = Handle.clean(handle) else { return nil }
        return await profiles(["handle": "eq.\(h)", "limit": "1"]).first
    }

    private func profiles(_ query: [String: String]) async -> [PublicProfile] {
        guard configured, var c = URLComponents(string: base + "/rest/v1/profiles") else { return [] }
        c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = c.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session?.accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode([PublicProfile].self, from: data)) ?? []
    }

    // MARK: Any other table (follows, activity, parties — see README)

    /// One request to the account server's REST API, as you when signed in. nil when it couldn't be reached.
    func rest(_ method: String = "GET", _ table: String, query: [String: String] = [:], body: Any? = nil,
              prefer: String? = nil) async -> (data: Data, status: Int)? {
        await refreshIfNeeded()
        guard configured, var c = URLComponents(string: base + "/rest/v1/" + table) else { return nil }
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session?.accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Public profiles by account id.
    func profiles(ids: [String]) async -> [PublicProfile] {
        let ids = Array(Set(ids)).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [] }
        return await profiles(["user_id": "in.(\(ids.joined(separator: ",")))", "select": "user_id,handle,name,bio,avatar_url,avatar_data"])
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.jm2kool.matinee", kSecAttrAccount as String: key]
    }
    static func read(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func write(_ key: String, _ data: Data) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}
