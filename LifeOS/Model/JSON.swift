import Foundation

/// A loosely typed JSON value. LifeOS keeps all data as one JSON document so the
/// same document works in the app, on the sync server and for AI assistants.
enum JSON: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSON].self) { self = .array(a); return }
        self = .object(try c.decode([String: JSON].self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n.rounded() == n && abs(n) < 9e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // MARK: access
    subscript(key: String) -> JSON {
        get { if case .object(let o) = self { return o[key] ?? .null }; return .null }
        set {
            if case .object(var o) = self {
                if case .null = newValue { o.removeValue(forKey: key) } else { o[key] = newValue }
                self = .object(o)
            } else if !newValue.isNull {
                self = .object([key: newValue])
            }
        }
    }
    subscript(index: Int) -> JSON {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.rounded() == n && abs(n) < 9e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    var str: String { string ?? "" }
    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    var int: Int? { double.map { Int($0) } }
    var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return s == "true"
        default: return false
        }
    }
    var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    var object: [String: JSON] { if case .object(let o) = self { return o }; return [:] }
    var isNull: Bool { if case .null = self { return true }; return false }
    var isObject: Bool { if case .object = self { return true }; return false }
    var isArray: Bool { if case .array = self { return true }; return false }

    /// Value at a dotted path like "study.note".
    func at(_ path: String) -> JSON {
        path.split(separator: ".").reduce(self) { $0[String($1)] }
    }

    // MARK: conversion
    static func parse(_ data: Data) -> JSON? { try? JSONDecoder().decode(JSON.self, from: data) }
    static func parse(_ text: String) -> JSON? { parse(Data(text.utf8)) }
    func data(pretty: Bool = false) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        return (try? e.encode(self)) ?? Data("null".utf8)
    }
    func text(pretty: Bool = false) -> String { String(decoding: data(pretty: pretty), as: UTF8.self) }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
                ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: JSON...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSON)...) {
        var o: [String: JSON] = [:]
        for (k, v) in elements where !v.isNull { o[k] = v }
        self = .object(o)
    }
    init(nilLiteral: ()) { self = .null }
}

extension JSON {
    init(_ s: String?) { self = s.map { .string($0) } ?? .null }
    init(_ n: Int) { self = .number(Double(n)) }
    init(_ n: Double) { self = .number(n) }
    init(_ b: Bool) { self = .bool(b) }
    /// Milliseconds since 1970, the timestamp format the document uses.
    static var now: JSON { .number((Date().timeIntervalSince1970 * 1000).rounded()) }
}
