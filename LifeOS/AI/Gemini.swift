import Foundation

/// Talks to Google's Gemini API with your key (from the Keychain), or through your own server if you set one up.
enum Gemini {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    static var hasKey: Bool { !(Keychain.get("geminiKey") ?? "").isEmpty }

    /// Returns the model's text. With `json`, Gemini is asked for a JSON object.
    static func generate(model: String, system: String, messages: [(role: String, text: String)], json: Bool, proxy: String?, proxyKey: String?) async throws -> String {
        let config: JSON = json
            ? ["temperature": 0.4, "maxOutputTokens": 4096, "responseMimeType": "application/json"]
            : ["temperature": 0.5, "maxOutputTokens": 2048]
        let contents: [JSON] = messages.map { m in
            let part: JSON = ["text": .string(m.text)]
            let role: JSON = .string(m.role == "assistant" ? "model" : "user")
            return ["role": role, "parts": .array([part])]
        }
        let sysPart: JSON = ["text": .string(system)]
        var body: JSON = [:]
        body["systemInstruction"] = ["parts": .array([sysPart])]
        body["contents"] = .array(contents)
        body["generationConfig"] = config
        func call(_ m: String) async throws -> (Int, JSON) {
            var req: URLRequest
            if let key = Keychain.get("geminiKey"), !key.isEmpty {
                req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):generateContent")!, timeoutInterval: 60)
                req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                req.httpBody = body.data()
            } else if let proxy, !proxy.isEmpty, let u = URL(string: proxy) {
                req = URLRequest(url: u, timeoutInterval: 60)
                if let proxyKey, !proxyKey.isEmpty { req.setValue("Bearer " + proxyKey, forHTTPHeaderField: "Authorization") }
                let wrapped: JSON = ["model": .string(m), "body": body]
                req.httpBody = wrapped.data()
            } else {
                throw Failure(message: "Add your Gemini API key in Settings.")
            }
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, res) = try await URLSession.shared.data(for: req)
            return ((res as? HTTPURLResponse)?.statusCode ?? 0, JSON.parse(data) ?? .null)
        }
        var (code, j) = try await call(model)
        if code == 404 && model != "gemini-flash-latest" { (code, j) = try await call("gemini-flash-latest") }
        if code >= 400 || code == 0 {
            let msg = j["error"]["message"].string ?? j["error"].string ?? "Gemini error \(code)"
            if code == 429 { throw Failure(message: "Gemini is rate limited. Try again in a minute.") }
            if code == 400 && msg.lowercased().contains("key") { throw Failure(message: "Gemini rejected the API key. Check it in Settings.") }
            throw Failure(message: msg)
        }
        let parts = j["candidates"][0]["content"]["parts"].array
        let text = parts.filter { !$0["thought"].bool }.compactMap { $0["text"].string }.joined()
        if text.isEmpty { throw Failure(message: "Gemini sent an empty reply.") }
        return text
    }

    /// Pulls the first JSON object out of a reply.
    static func object(from text: String) -> JSON? {
        if let j = JSON.parse(text), j.isObject { return j }
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else { return nil }
        return JSON.parse(String(text[a...b]))
    }
}
