import Foundation

/// Several Gemini keys on this iPhone, used in turn: a key that hits a rate limit or runs out of quota cools down and the next
/// one is tried. The values live only in the Keychain: never in the LifeOS document, never sent to your server, never shown
/// after they're saved. Cooldowns (no values) are kept in UserDefaults.
enum GeminiKeys {
    struct Key: Codable, Identifiable, Hashable {
        let id: String
        var label: String
        let value: String
    }
    struct Cooldown: Codable { let until: Date; let reason: String }

    private static let account = "geminiKeys", legacy = "geminiKey", coolKey = "gemini.cooldowns"

    /// Every key, oldest first. The single key from older versions is moved in the first time.
    static func all() -> [Key] {
        if let raw = Keychain.get(account), let keys = try? JSONDecoder().decode([Key].self, from: Data(raw.utf8)) { return keys }
        guard let old = Keychain.get(legacy)?.trimmingCharacters(in: .whitespacesAndNewlines), !old.isEmpty else { return [] }
        let keys = [Key(id: "k-" + UUID().uuidString.prefix(8).lowercased(), label: "Key 1", value: old)]
        save(keys); Keychain.set(legacy, nil)
        return keys
    }
    private static func save(_ keys: [Key]) {
        guard let d = try? JSONEncoder().encode(keys) else { return }
        Keychain.set(account, keys.isEmpty ? nil : String(decoding: d, as: UTF8.self))
    }

    /// What's left of a pasted key once spaces, line breaks, invisible characters (zero-width and non-breaking spaces,
    /// which copying from a web page often brings along) and wrapping quotes are taken out.
    static func clean(_ raw: String) -> String {
        let junk = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(.illegalCharacters)
            .union(CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}\u{00A0}\"'“”‘’`<>"))
        return String(String.UnicodeScalarView(raw.unicodeScalars.filter { !junk.contains($0) && $0.properties.generalCategory != .format }))
    }
    /// Only a rough check: any run of 20–200 ordinary characters. Whether Google accepts it is checked with Google (verify).
    static func plausible(_ value: String) -> Bool {
        (20...200).contains(value.count) && value.unicodeScalars.allSatisfy { $0.isASCII && $0.value > 32 && $0.value < 127 }
    }
    /// Asks Google whether a key works, without spending generate quota. Returns a problem, or nil if it works
    /// (or Google can't be reached right now; the key is then checked on first use).
    static func verify(_ raw: String) async -> String? {
        let value = clean(raw)
        guard plausible(value) else { return "That doesn't look like a Gemini API key. Copy it again from Google AI Studio." }
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!, timeoutInterval: 12)
        req.setValue(value, forHTTPHeaderField: "x-goog-api-key")
        guard let reply = try? await URLSession.shared.data(for: req), let code = (reply.1 as? HTTPURLResponse)?.statusCode else { return nil }
        if code == 200 || code == 429 { return nil }
        let msg = (JSON.parse(reply.0) ?? .null)["error"]["message"].string ?? "error \(code)"
        return "Google didn't accept this key: " + scrub(msg).replacingOccurrences(of: value, with: "[key]")
    }

    /// Adds a key; returns a problem to show instead, if any.
    @discardableResult static func add(_ raw: String, label: String = "") -> String? {
        let value = clean(raw)
        guard plausible(value) else { return "That doesn't look like a Gemini API key. Copy it again from Google AI Studio." }
        var keys = all()
        guard !keys.contains(where: { $0.value == value }) else { return "That key is already added." }
        let name = label.trimmingCharacters(in: .whitespaces)
        keys.append(Key(id: "k-" + UUID().uuidString.prefix(8).lowercased(), label: name.isEmpty ? "Key \(keys.count + 1)" : String(name.prefix(40)), value: value))
        save(keys)
        return nil
    }
    static func remove(_ id: String) {
        save(all().filter { $0.id != id })
        var c = cooldowns; c = c.filter { !$0.key.hasPrefix(id + "|") }; cooldowns = c
    }
    static func rename(_ id: String, to label: String) {
        save(all().map { $0.id == id ? Key(id: $0.id, label: label.isEmpty ? $0.label : String(label.prefix(40)), value: $0.value) : $0 })
    }

    // MARK: cooldowns
    private static var cooldowns: [String: Cooldown] {
        get { (UserDefaults.standard.data(forKey: coolKey)).flatMap { try? JSONDecoder().decode([String: Cooldown].self, from: $0) } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue.filter { $0.value.until > Date() }), forKey: coolKey) }
    }
    /// The active cooldown for a key and model, if any. Google's free quotas are per model; a rejected key is out for every model.
    static func cooldown(_ id: String, model: String) -> Cooldown? {
        let c = cooldowns, now = Date()
        return [c[id + "|*"], c[id + "|" + model]].compactMap { $0 }.filter { $0.until > now }.max { $0.until < $1.until }
    }
    /// The keys to try for this model, in order, skipping ones that are cooling down.
    static func usable(model: String) -> [Key] { all().filter { cooldown($0.id, model: model) == nil } }
    static func activeCount(model: String) -> Int { usable(model: model).count }
    static func reset(_ id: String) { cooldowns = cooldowns.filter { !$0.key.hasPrefix(id + "|") } }

    enum Problem { case quota(daily: Bool, wait: TimeInterval), rejected }

    /// What an error from Google means for the key that made the call.
    static func classify(_ code: Int, _ j: JSON) -> Problem? {
        let msg = j["error"]["message"].str, status = j["error"]["status"].str, details = j["error"]["details"].text()
        let all = (msg + " " + details).lowercased()
        if code == 429 || status == "RESOURCE_EXHAUSTED" || all.contains("quota") || all.contains("rate limit") || all.contains("resource has been exhausted") {
            let daily = all.contains("per day") || all.contains("perday") || all.contains("daily")
            var wait: TimeInterval = 60
            if let r = details.range(of: #""retryDelay":"(\d+(\.\d+)?)s""#, options: .regularExpression) {
                let digits = details[r].filter { $0.isNumber || $0 == "." }
                wait = Double(digits).map { ceil($0) } ?? 60
            }
            return .quota(daily: daily, wait: wait)
        }
        // Only errors about the key itself: a 403 about a model you can't use is not the key's fault.
        let keyWords = ["api_key_invalid", "api key not valid", "api key expired", "api key was reported as leaked", "requests from this api key are blocked"]
        if [400, 401, 403].contains(code) && (keyWords.contains { all.contains($0) } || status == "UNAUTHENTICATED") { return .rejected }
        return nil
    }

    static func cool(_ id: String, model: String, _ p: Problem) {
        var c = cooldowns
        switch p {
        case .rejected: c[id + "|*"] = Cooldown(until: Date().addingTimeInterval(6 * 3600), reason: "rejected")
        case .quota(let daily, let wait):
            c[id + "|" + model] = daily ? Cooldown(until: nextQuotaReset(), reason: "daily quota")
                                        : Cooldown(until: Date().addingTimeInterval(min(3600, max(15, wait))), reason: "rate limit")
        }
        cooldowns = c
    }

    /// Next midnight in Google's quota time zone (Pacific), when daily free quotas reset, plus a minute of slack.
    static func nextQuotaReset(from now: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let midnight = cal.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86400)
        return midnight.addingTimeInterval(60)
    }

    /// Takes every key value out of a message so an error from Google can never show one.
    static func scrub(_ text: String) -> String {
        var s = text
        for k in all() where k.value.count >= 8 { s = s.replacingOccurrences(of: k.value, with: "[key]") }
        return s.replacingOccurrences(of: #"AIza[0-9A-Za-z_\-]{20,}"#, with: "[key]", options: .regularExpression)
    }

    // MARK: the server's pool (only counts are kept here, never values)
    /// How many keys your server had active the last time it said, or nil if it hasn't yet.
    static var serverActive: Int? {
        get { UserDefaults.standard.object(forKey: "gemini.serverActive") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "gemini.serverActive") }
    }
    static var serverTotal: Int? {
        get { UserDefaults.standard.object(forKey: "gemini.serverTotal") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "gemini.serverTotal") }
    }
    /// Reads the server's "X-LifeOS-Keys: active/total" header.
    static func noteServer(header: String?) {
        guard let h = header else { return }
        let p = h.split(separator: "/").compactMap { Int($0) }
        if p.count == 2 { serverActive = p[0]; serverTotal = p[1] }
    }
}
