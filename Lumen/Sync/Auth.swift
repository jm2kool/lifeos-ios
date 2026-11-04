import Foundation
import CryptoKit
import Security

/// Google sign-in through Supabase Auth. It runs in a secure browser sheet with PKCE, so there's no Google SDK
/// and no client secret in the app. The session lives in the Keychain and is refreshed before it expires.
@Observable @MainActor
final class Auth {
    static let shared = Auth()

    struct Session: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var email: String?
        var name: String?
        var avatar: URL?
    }

    private(set) var session: Session? { didSet { save() } }
    /// Using Lumen on this iPhone only, without an account.
    var offline: Bool { didSet { UserDefaults.standard.set(offline, forKey: "auth.offline") } }
    var busy = false
    var error: String?

    var signedIn: Bool { session != nil }
    var needsSignIn: Bool { session == nil && !offline }
    var userID: String? { session?.userID }

    static let callbackScheme = "lumen"
    static let redirect = "lumen://auth-callback"

    var serverURL: String {
        get { setting("server.url", plist: "LumenSupabaseURL") }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "server.url") }
    }
    var anonKey: String {
        get { setting("server.key", plist: "LumenSupabaseAnonKey") }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "server.key") }
    }
    var configured: Bool { URL(string: serverURL)?.host != nil && !anonKey.isEmpty }
    /// Typed in Settings rather than built into the app.
    var serverIsCustom: Bool { !(UserDefaults.standard.string(forKey: "server.url") ?? "").isEmpty }
    var base: String { serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL }
    /// The address Instinct calls.
    var agentURL: String { base + "/functions/v1/lumen-agent" }

    private init() {
        offline = UserDefaults.standard.bool(forKey: "auth.offline")
        if let data = Keychain.read("session"), let s = try? JSONDecoder().decode(Session.self, from: data) { session = s }
    }

    private func setting(_ key: String, plist: String) -> String {
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        if !saved.isEmpty { return saved }
        let baked = ((Bundle.main.object(forInfoDictionaryKey: plist) as? String) ?? "").trimmingCharacters(in: .whitespaces)
        return baked.hasPrefix("$(") ? "" : baked
    }

    private func save() {
        if let s = session, let data = try? JSONEncoder().encode(s) { Keychain.write("session", data) } else { Keychain.delete("session") }
    }

    // MARK: Google (OAuth with PKCE)

    struct PendingOAuth { let url: URL; let verifier: String }

    func beginGoogle() -> PendingOAuth? {
        guard configured else { error = "Add your Supabase project first (below)."; return nil }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        guard var c = URLComponents(string: base + "/auth/v1/authorize") else { error = "The server address doesn't look right."; return nil }
        c.queryItems = [
            .init(name: "provider", value: "google"),
            .init(name: "redirect_to", value: Self.redirect),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "s256"),
            .init(name: "prompt", value: "select_account"),
        ]
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
        busy = true
        defer { busy = false }
        await token(grant: "pkce", body: ["auth_code": code, "code_verifier": verifier])
    }

    // MARK: Session

    @ObservationIgnored private var refreshing: Task<Void, Never>?

    /// Swaps an expiring access token for a fresh one. Calls that arrive meanwhile wait, so the single-use
    /// refresh token is only spent once.
    func refreshIfNeeded() async {
        guard let s = session, s.expiresAt.timeIntervalSinceNow < 120 else { return }
        if let running = refreshing { await running.value; return }
        let t = Task { await refresh(s.refreshToken) }
        refreshing = t
        await t.value
        refreshing = nil
    }

    /// Only the server saying the refresh token is no good ends the session; being offline never signs you out.
    private func refresh(_ token: String) async {
        guard configured, let url = URL(string: base + "/auth/v1/token?grant_type=refresh_token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": token])
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let code = (resp as? HTTPURLResponse)?.statusCode else { return }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if (200..<300).contains(code), obj["access_token"] != nil {
            adopt(obj)
        } else if code == 400 || code == 401 || code == 403 {
            session = nil
        }
    }

    func useOffline() { offline = true; error = nil }

    func setServer(url: String, key: String) {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty && !u.lowercased().hasPrefix("http") { u = "https://" + u }
        if session != nil && u != serverURL { signOut() }
        serverURL = u
        anonKey = key
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
        offline = false
    }

    private func token(grant: String, body: [String: String]) async {
        guard configured, let url = URL(string: base + "/auth/v1/token?grant_type=\(grant)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
                error = (obj["error_description"] ?? obj["msg"] ?? obj["message"]) as? String ?? "Sign-in failed (\(h.statusCode))."
                return
            }
            adopt(obj)
        } catch {
            self.error = "Couldn't reach the server. Check your connection."
        }
    }

    private func adopt(_ r: [String: Any]) {
        guard let access = r["access_token"] as? String, let refresh = r["refresh_token"] as? String else {
            error = (r["error_description"] ?? r["msg"]) as? String ?? "Sign-in failed."
            return
        }
        let u = r["user"] as? [String: Any] ?? [:]
        let meta = u["user_metadata"] as? [String: Any] ?? [:]
        let expires = (r["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        session = Session(
            accessToken: access, refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expires),
            userID: ((u["id"] as? String) ?? session?.userID ?? "").lowercased(),
            email: (u["email"] as? String) ?? session?.email,
            name: (meta["full_name"] as? String) ?? (meta["name"] as? String) ?? session?.name,
            avatar: ((meta["avatar_url"] as? String) ?? (meta["picture"] as? String)).flatMap(URL.init(string:)) ?? session?.avatar)
        error = nil
        offline = false
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
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.jm2kool.lumen", kSecAttrAccount as String: key]
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
