//
//  DiagnosticLogbook.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import OSLog

public struct DiagnosticEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let category: String
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), category: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
    }
}

/// Thread-safe bounded ring-buffer logbook for Auth, Liquid Glass, WebPlayer Bridge, GraphQL, and Lyrics.
/// Automatically redacts bearer tokens, cookies, and Spicy keys before storing or exporting.
public final class DiagnosticLogbook: @unchecked Sendable {
    public static let shared = DiagnosticLogbook()

    private let lock = NSLock()
    private var entries: [DiagnosticEntry] = []
    private let capacity = 600
    private let logger = Logger(subsystem: "app.celestify.ios", category: "Diagnostics")

    private init() {}

    public func log(_ category: String, _ message: String) {
        let sanitized = Self.redact(message)
        logger.debug("[\(category, privacy: .public)] \(sanitized, privacy: .public)")
        let entry = DiagnosticEntry(category: category, message: sanitized)
        lock.lock()
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        lock.unlock()
    }

    public func snapshot() -> [DiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    public func exportReportURL(appVersion: String = "2.4.4") throws -> URL {
        let items = snapshot()
        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            "Celestify for iOS Diagnostic Report",
            "Version: \(appVersion)",
            "Generated: \(formatter.string(from: Date()))",
            "Entries: \(items.count)",
            String(repeating: "-", count: 60)
        ]
        for item in items {
            lines.append("\(formatter.string(from: item.timestamp)) [\(item.category)] \(item.message)")
        }
        let content = lines.joined(separator: "\n")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("celestify-diagnostics-\(Int(Date().timeIntervalSince1970)).log")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    public static func redact(_ raw: String) -> String {
        var result = raw
        let patterns: [(String, String)] = [
            ("(?i)(Bearer\\s+)[A-Za-z0-9._\\-~+/]+=*", "$1<REDACTED_TOKEN>"),
            ("(?i)(sp_dc|sp_t|sp_key)=([^;\\s\"']+)", "$1=<REDACTED_COOKIE>"),
            ("sl_pk_[A-Za-z0-9_\\-]+", "sl_pk_<REDACTED>")
        ]
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }
        return result
    }
}
