import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// One row from the server, with forgiving readers for each column type.
struct Row {
    let raw: [String: Any]
    init(_ raw: [String: Any]) { self.raw = raw }

    func has(_ k: String) -> Bool { raw[k] != nil }
    func str(_ k: String) -> String? { raw[k] as? String }
    func int(_ k: String) -> Int? {
        if let n = raw[k] as? NSNumber { return n.intValue }
        return (raw[k] as? String).flatMap { Int($0) ?? Double($0).map { Int($0) } }
    }
    func double(_ k: String) -> Double? {
        if let n = raw[k] as? NSNumber { return n.doubleValue }
        return (raw[k] as? String).flatMap(Double.init)
    }
    func bool(_ k: String) -> Bool? {
        if let b = raw[k] as? Bool { return b }
        return (raw[k] as? NSNumber)?.boolValue
    }
    func date(_ k: String) -> Date? { (raw[k] as? String).flatMap(ISO.parse) }
    func uuid(_ k: String) -> UUID? { (raw[k] as? String).flatMap { UUID(uuidString: $0) } }
    func uuids(_ k: String) -> [String] {
        ((raw[k] as? [Any]) ?? []).compactMap { ($0 as? String)?.lowercased() }
    }
    func ints(_ k: String) -> [Int] {
        ((raw[k] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? String).flatMap(Int.init) }
    }
    func json(_ k: String) -> Data? {
        guard let v = raw[k], !(v is NSNull), JSONSerialization.isValidJSONObject(v) || v is [Any] || v is [String: Any] else { return nil }
        return try? JSONSerialization.data(withJSONObject: v)
    }
}

/// ISO 8601 dates as Postgres writes them (with or without fractions, any number of fraction digits).
enum ISO {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ d: Date) -> String { withFraction.string(from: d) }

    static func parse(_ s: String) -> Date? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { t += "T00:00:00Z" }
        if t.count > 10, t[t.index(t.startIndex, offsetBy: 10)] == " " {
            t.replaceSubrange(t.index(t.startIndex, offsetBy: 10)...t.index(t.startIndex, offsetBy: 10), with: "T")
        }
        // Postgres gives up to six fraction digits and offsets like +00; trim to three and normalise.
        if let dot = t.firstIndex(of: ".") {
            var end = t.index(after: dot)
            while end < t.endIndex, t[end].isNumber { end = t.index(after: end) }
            let digits = t[t.index(after: dot)..<end]
            let three = String((digits + "000").prefix(3))
            t.replaceSubrange(t.index(after: dot)..<end, with: three)
        }
        if let r = t.range(of: #"[+-]\d{2}$"#, options: .regularExpression) { t.replaceSubrange(r, with: t[r] + ":00") }
        if let r = t.range(of: #"[+-]\d{4}$"#, options: .regularExpression) {
            let off = String(t[r]); t.replaceSubrange(r, with: off.prefix(3) + ":" + off.suffix(2))
        }
        return withFraction.date(from: t) ?? plain.date(from: t)
    }
}

extension UUID {
    /// How Postgres writes ids.
    var lower: String { uuidString.lowercased() }

    /// A stable id made from text, so the same calendar event always maps to the same busy slot.
    static func stable(_ text: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        #if canImport(CryptoKit)
        bytes = Array(SHA256.hash(data: Data(text.utf8))).prefix(16).map { $0 }
        #else
        var h1: UInt64 = 0xcbf29ce484222325, h2: UInt64 = 0x84222325cbf29ce4
        for b in text.utf8 {
            h1 = (h1 ^ UInt64(b)) &* 0x100000001b3
            h2 = (h2 ^ UInt64(b)) &* 0x1000193 &+ 0x9e3779b97f4a7c15
        }
        for i in 0..<8 { bytes[i] = UInt8((h1 >> (UInt64(i) * 8)) & 0xff); bytes[i + 8] = UInt8((h2 >> (UInt64(i) * 8)) & 0xff) }
        #endif
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

extension Optional where Wrapped == UUID {
    var json: Any { self.map { $0.lower as Any } ?? NSNull() }
}
extension Optional where Wrapped == String {
    var json: Any { self.map { $0 as Any } ?? NSNull() }
}
extension Optional where Wrapped == Date {
    var json: Any { self.map { ISO.string($0) as Any } ?? NSNull() }
}
