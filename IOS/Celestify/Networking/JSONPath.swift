//
//  JSONPath.swift
//  Celestify
//
//  Lenient dotted-path JSON reader, Base62-to-Hex GID converter, and compact
//  Protobuf wire reader ported from Myspoti (:api-spotify JsonPaths.kt, SpotifyContent.kt, SpotifyRecents.kt).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

// MARK: - Sendable Dynamic JSON Value

public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return parse(data)
    }

    public func serializedData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public func serializedString() -> String? {
        guard let d = serializedData() else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // MARK: - Lenient Dotted-Path Accessors

    public func at(_ path: String) -> JSONValue? {
        if path.isEmpty { return self == .null ? nil : self }
        var current: JSONValue = self
        for key in path.split(separator: ".") {
            guard case .object(let dict) = current,
                  let next = dict[String(key)],
                  next != .null else {
                return nil
            }
            current = next
        }
        return current == .null ? nil : current
    }

    public func obj(_ path: String = "") -> [String: JSONValue]? {
        guard let node = at(path), case .object(let dict) = node else { return nil }
        return dict
    }

    public func list(_ path: String = "") -> [JSONValue] {
        guard let node = at(path), case .array(let arr) = node else { return [] }
        return arr
    }

    public func str(_ path: String = "") -> String? {
        guard let node = at(path) else { return nil }
        if case .string(let s) = node { return s }
        return nil
    }

    public func int64(_ path: String = "") -> Int64? {
        guard let node = at(path) else { return nil }
        switch node {
        case .int(let i): return i
        case .double(let d): return Int64(d)
        case .string(let s): return Int64(s)
        default: return nil
        }
    }

    public func int(_ path: String = "") -> Int? {
        int64(path).map(Int.init)
    }

    public func double(_ path: String = "") -> Double? {
        guard let node = at(path) else { return nil }
        switch node {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public func bool(_ path: String = "") -> Bool? {
        guard let node = at(path) else { return nil }
        switch node {
        case .bool(let b): return b
        case .string(let s):
            if s.lowercased() == "true" { return true }
            if s.lowercased() == "false" { return false }
            return nil
        default: return nil
        }
    }

    public func typename() -> String? {
        str("__typename")
    }
}

// MARK: - Spotify Base62 ID -> 32-Char Hex GID Converter

public enum SpotifyBase62 {
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let lookup: [Character: UInt64] = {
        var map: [Character: UInt64] = [:]
        for (idx, ch) in alphabet.enumerated() {
            map[ch] = UInt64(idx)
        }
        return map
    }()

    /// Converts a 22-char Spotify Base62 ID into the 32-char lowercase hex GID used by `spclient` metadata/4 & canvas.
    public static func toHex32(_ base62ID: String) -> String? {
        guard !base62ID.isEmpty else { return nil }
        // 128-bit big-endian byte accumulator (16 bytes -> 32 hex chars)
        var bytes = [UInt8](repeating: 0, count: 16)
        for ch in base62ID {
            guard let digit = lookup[ch] else { return nil }
            var carry = digit
            for idx in stride(from: 15, through: 0, by: -1) {
                let prod = UInt64(bytes[idx]) * 62 + carry
                bytes[idx] = UInt8(prod & 0xFF)
                carry = prod >> 8
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Compact Protobuf Readers (Recents group_metadata & Socialgraph block status)

public enum SpotifyMiniProtobuf {
    public struct RecentsGroupMeta: Sendable, Equatable {
        public let contentType: String?
        public let count: Int?
    }

    /// Decodes `group_metadata` Base64 protobuf (`1: index, 4: {1: contentType, 2: plays}`).
    public static func decodeRecentsGroupMetadata(base64: String?) -> RecentsGroupMeta? {
        guard let base64, !base64.isEmpty, let data = Data(base64Encoded: base64) else {
            return nil
        }
        let bytes = [UInt8](data)
        var i = 0
        var contentType: String?
        var count: Int?

        while i < bytes.count {
            let tag = Int(bytes[i])
            i += 1
            let wireType = tag & 0x07
            let fieldNumber = tag >> 3
            switch wireType {
            case 0:
                while i < bytes.count && (bytes[i] & 0x80) != 0 { i += 1 }
                i += 1
            case 2:
                guard i < bytes.count else { return RecentsGroupMeta(contentType: contentType, count: count) }
                let len = Int(bytes[i])
                i += 1
                guard i + len <= bytes.count else { return RecentsGroupMeta(contentType: contentType, count: count) }
                if fieldNumber == 4 {
                    let inner = Array(bytes[i..<(i + len)])
                    contentType = readInnerString(inner)
                    count = readInnerVarint(inner, targetField: 2)
                }
                i += len
            default:
                return RecentsGroupMeta(contentType: contentType, count: count)
            }
        }
        return RecentsGroupMeta(contentType: contentType, count: count)
    }

    /// Decodes `socialgraph/v4/{me}/is-blocking/{target}` protobuf (`field 1 == 1` means blocked).
    public static func decodeIsBlocking(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        return bytes.count >= 2 && bytes[0] == 0x08 && bytes[1] == 0x01
    }

    private static func readInnerString(_ inner: [UInt8]) -> String? {
        var i = 0
        while i < inner.count {
            let tag = Int(inner[i])
            i += 1
            switch tag & 7 {
            case 0:
                while i < inner.count && (inner[i] & 0x80) != 0 { i += 1 }
                i += 1
            case 2:
                guard i < inner.count else { return nil }
                let len = Int(inner[i])
                i += 1
                guard i + len <= inner.count else { return nil }
                if (tag >> 3) == 1 {
                    return String(bytes: inner[i..<(i + len)], encoding: .utf8)
                }
                i += len
            default:
                return nil
            }
        }
        return nil
    }

    private static func readInnerVarint(_ inner: [UInt8], targetField: Int) -> Int? {
        var i = 0
        while i < inner.count {
            let tag = Int(inner[i])
            i += 1
            switch tag & 7 {
            case 0:
                var value = 0
                var shift = 0
                while i < inner.count {
                    let b = Int(inner[i])
                    i += 1
                    value |= (b & 0x7F) << shift
                    shift += 7
                    if (b & 0x80) == 0 { break }
                }
                if (tag >> 3) == targetField { return value }
            case 2:
                guard i < inner.count else { return nil }
                let len = Int(inner[i])
                i += 1
                i += len
            default:
                return nil
            }
        }
        return nil
    }
}
