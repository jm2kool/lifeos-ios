import Foundation

/// Talks to Google's Gemini API with your keys (from the Keychain), or through your own server if you set one up.
/// With several keys, one that is rate limited or out of quota cools down and the next is used (see GeminiKeys).
/// When your server has keys of its own, it goes first and the keys on this iPhone are the fallback.
enum Gemini {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    static var hasKey: Bool { !GeminiKeys.all().isEmpty }

    /// Returns the model's text. With `json`, Gemini is asked for a JSON object.
    static func generate(model: String, system: String, messages: [(role: String, text: String)], json: Bool, proxy: String?, proxyKey: String?) async throws -> String {
        let contents: [JSON] = messages.map { m in
            let part: JSON = ["text": .string(m.text)]
            let role: JSON = .string(m.role == "assistant" ? "model" : "user")
            return ["role": role, "parts": .array([part])]
        }
        let sysPart: JSON = ["text": .string(system)]

        func body(for m: String) -> JSON {
            var config: JSON = json
                ? ["temperature": 0.4, "maxOutputTokens": 4096, "responseMimeType": "application/json"]
                : ["temperature": 0.5, "maxOutputTokens": 2048]
            // Keep replies quick: newer models think a lot by default.
            if m.hasPrefix("gemini-3") {
                let thinking: JSON = ["thinkingLevel": "low"]
                config["thinkingConfig"] = thinking
            } else if m.hasPrefix("gemini-2.5") {
                let thinking: JSON = ["thinkingBudget": 0]
                config["thinkingConfig"] = thinking
            }
            var b: JSON = [:]
            b["systemInstruction"] = ["parts": .array([sysPart])]
            b["contents"] = .array(contents)
            b["generationConfig"] = config
            return b
        }

        func send(_ req: URLRequest) async throws -> (Int, JSON, HTTPURLResponse?) {
            var req = req
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, res) = try await URLSession.shared.data(for: req)
            let http = res as? HTTPURLResponse
            return (http?.statusCode ?? 0, JSON.parse(data) ?? .null, http)
        }
        let server: URL? = proxy.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        func viaServer(_ m: String, wait: TimeInterval) async throws -> (Int, JSON) {
            guard let server else { throw Failure(message: "No server") }
            var req = URLRequest(url: server, timeoutInterval: wait)
            if let proxyKey, !proxyKey.isEmpty { req.setValue("Bearer " + proxyKey, forHTTPHeaderField: "Authorization") }
            let wrapped: JSON = ["model": .string(m), "body": body(for: m)]
            req.httpBody = wrapped.data()
            let (code, j, http) = try await send(req)
            GeminiKeys.noteServer(header: http?.value(forHTTPHeaderField: "X-LifeOS-Keys"))
            return (code, j)
        }
        func direct(_ m: String, key: GeminiKeys.Key, wait: TimeInterval) async throws -> (Int, JSON) {
            var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):generateContent")!, timeoutInterval: wait)
            req.setValue(key.value, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = body(for: m).data()
            let (code, j, _) = try await send(req)
            return (code, j)
        }

        /// One model: the server first when it has keys (or there are none here), then each usable key on this iPhone.
        /// A key that is rate limited, out of quota or rejected cools down and the next one is tried.
        var rejectedKeys = 0
        func call(_ m: String, wait: TimeInterval) async throws -> (Int, JSON) {
            let local = GeminiKeys.all()
            guard server != nil || !local.isEmpty else { throw Failure(message: "Add your Gemini API key in Settings.") }
            var last: (Int, JSON)?
            let serverFirst = server != nil && (local.isEmpty || (GeminiKeys.serverActive ?? 0) > 0)
            if serverFirst {
                do {
                    let r = try await viaServer(m, wait: wait)
                    // The server rotates its own keys; only fall back here when it has none left (429) or none at all (503).
                    if ![429, 503].contains(r.0) || local.isEmpty { return r }
                    last = r
                } catch {
                    if local.isEmpty { throw error }
                }
            }
            let keys = GeminiKeys.usable(model: m)
            if keys.isEmpty, !local.isEmpty, last == nil {
                let allRejected = local.allSatisfy { GeminiKeys.cooldown($0.id, model: m)?.reason == "rejected" }
                let note: JSON = ["message": .string(allRejected ? "Google rejected the API key earlier" : "All \(local.count) Gemini keys on this iPhone are cooling down for \(m)")]
                last = (allRejected ? 400 : 429, ["error": note])
            }
            for k in keys {
                let r = try await direct(m, key: k, wait: wait)
                guard let problem = GeminiKeys.classify(r.0, r.1) else { return r }
                GeminiKeys.cool(k.id, model: m, problem)
                if case .rejected = problem { rejectedKeys += 1 }
                last = r
            }
            // Every key here is used up: your server may still have some.
            if !serverFirst, server != nil, let r = try? await viaServer(m, wait: wait), r.0 == 200 { return r }
            if let last { return last }
            return try await viaServer(m, wait: wait)
        }

        // Try the chosen model, then fallbacks if it is gone, slow, busy or answers with nothing.
        var models: [String] = [model]
        for m in fallbacks where !models.contains(m) && !gone.contains(m) { models.append(m) }
        var tried: [String] = []
        var rateLimited = false
        for (i, m) in models.enumerated() {
            let result: (Int, JSON)
            do {
                result = try await call(m, wait: i == 0 ? 40 : 25)
            } catch {
                if error is Failure { throw error }
                tried.append("\(m): did not respond"); continue
            }
            let (code, j) = result
            let msg = GeminiKeys.scrub(j["error"]["message"].string ?? j["error"].string ?? "error \(code)")
            if code == 200 {
                let parts = j["candidates"][0]["content"]["parts"].array
                let text = parts.filter { !$0["thought"].bool }.compactMap { $0["text"].string }.joined()
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tried.append("\(m): empty reply"); continue }
                if m != model { note(model: model, used: m, why: tried.first ?? "") }
                return text
            }
            tried.append("\(m): \(msg)")
            let lower = msg.lowercased()
            if rejectedKeys > 0 && rejectedKeys >= GeminiKeys.all().count && server == nil {
                throw Failure(message: rejectedKeys > 1 ? "Gemini rejected all your API keys. Check them in Settings." : "Gemini rejected the API key. Check it in Settings.")
            }
            if code == 404 || ([400, 403].contains(code) && ["no longer", "not found", "not available", "not supported", "deprecated", "unknown model"].contains { lower.contains($0) }) {
                gone.insert(m); continue
            }
            if code == 429 { rateLimited = true; continue }
            if [500, 502, 503, 504].contains(code) { continue }
            if code == 400 && lower.contains("key") { throw Failure(message: "Gemini rejected the API key. Check it in Settings.") }
            throw Failure(message: msg)
        }
        if rateLimited && tried.allSatisfy({ $0.contains("429") || $0.lowercased().contains("quota") || $0.lowercased().contains("rate") || $0.lowercased().contains("cooling") }) {
            let n = GeminiKeys.all().count
            throw Failure(message: n > 1 ? "All \(n) Gemini keys are rate limited. Try again in a minute, or add another key in Settings." : "Gemini is rate limited. Try again in a minute.")
        }
        throw Failure(message: "Gemini couldn't answer, so nothing was changed. Tried " + tried.joined(separator: "; "))
    }

    static let fallbacks = ["gemini-3.5-flash", "gemini-2.5-flash", "gemini-flash-latest"]
    /// Models Google said are gone, skipped until the app restarts.
    nonisolated(unsafe) private static var gone: Set<String> = []
    /// Tells you once when your chosen model failed and another answered, so it isn't silent.
    @MainActor private static var noted: Set<String> = []
    private static func note(model: String, used: String, why: String) {
        Task { @MainActor in
            guard !noted.contains(model) else { return }
            noted.insert(model)
            Store.shared.show("\(model) isn't working (\(why.replacingOccurrences(of: model + ": ", with: ""))). Using \(used); change the model in Settings.")
        }
    }

    /// Pulls the first JSON object out of a reply.
    static func object(from text: String) -> JSON? {
        if let j = JSON.parse(text), j.isObject { return j }
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else { return nil }
        return JSON.parse(String(text[a...b]))
    }
}
