//
//  SpicyCatalogueService.swift
//  Celestify
//
//  Spicy Lyrics hosted TTML catalogue client (`api.spicylyrics.org/v1/lyrics/{id}`)
//  and atomic per-track local `.ttml` import library (`SpicyImportsStore`).
//  Adapted from Celestify (SpicyCatalogue.kt & SpicyDocument.kt), AGPL-3.0 / GPL-3.0.
//

import CryptoKit
import Foundation

public actor SpicyCatalogueService {
    public static let shared = SpicyCatalogueService()

    private let http: HTTPClient
    private var cache: [String: Lyrics] = [:]
    private var misses: Set<String> = []
    private var rateLimitedUntil: Date = .distantPast

    public init(http: HTTPClient = .shared) {
        self.http = http
    }

    public nonisolated static func isValidKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return trimmed.hasPrefix("sl_pk_") && trimmed.count >= 12 && trimmed.count <= 160
    }

    public func lookup(trackID: String, apiKey: String, forceReload: Bool = false) async -> Lyrics? {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty,
              Self.isValidKey(cleanKey),
              trackID.count == 22,
              Date() >= rateLimitedUntil else {
            return nil
        }

        if !forceReload {
            if let hit = cache[trackID] { return hit }
            if misses.contains(trackID) { return nil }
        }

        guard let url = URL(string: "https://api.spicylyrics.org/v1/lyrics/\(trackID)") else {
            return nil
        }

        do {
            let res = try await http.send(
                method: "GET",
                url: url,
                headers: [
                    "X-API-Key": cleanKey,
                    "Accept": "application/json, application/xml, text/xml"
                ],
                maxBytes: TtmlLyricsParser.maxBytes
            )
            if res.statusCode == 429 {
                let wait = TimeInterval(res.retryAfterSeconds ?? 60)
                rateLimitedUntil = Date().addingTimeInterval(min(max(wait, 10), 600))
                return nil
            }
            if res.statusCode == 404 {
                misses.insert(trackID)
                return nil
            }
            guard (200...299).contains(res.statusCode) else { return nil }

            // Payload may be raw TTML XML or JSON wrapping `{ "ttml": "<tt ...>" }` / `{ "content": "..." }`
            let xmlText: String
            if let json = JSONValue.parse(res.data),
               let inner = json.str("ttml") ?? json.str("lyrics") ?? json.str("content") {
                xmlText = inner
            } else {
                xmlText = res.text
            }

            let parsed = try TtmlLyricsParser.parse(xmlText)
            let tagged = Lyrics(
                lines: parsed.lines,
                synced: parsed.synced,
                wordSynced: parsed.wordSynced,
                provider: "Spicy Lyrics",
                colors: parsed.colors,
                isRTL: parsed.isRTL,
                songwriters: parsed.songwriters
            )
            cache[trackID] = tagged
            return tagged
        } catch {
            DiagnosticLogbook.shared.log("spicy", "Catalogue lookup failed for \(trackID): \(error.localizedDescription)")
            return nil
        }
    }

    public func clearCache(trackID: String? = nil) {
        if let trackID {
            cache.removeValue(forKey: trackID)
            misses.remove(trackID)
        } else {
            cache.removeAll()
            misses.removeAll()
        }
    }
}

// MARK: - Local Per-Track TTML Imports Store

public struct ImportedTtmlEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: String { trackID }
    public let trackID: String
    public let trackDisplayTitle: String
    public let fileName: String
    public let importedAt: Date
}

public actor SpicyImportsStore {
    public static let shared = SpicyImportsStore()

    private let directoryURL: URL
    private let indexFileURL: URL

    public init(baseDirectory: URL? = nil) {
        let root = baseDirectory ?? (
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SpicyImports", isDirectory: true)
        )
        self.directoryURL = root
        self.indexFileURL = root.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func readImportedLyrics(forTrackID trackID: String) -> Lyrics? {
        guard !trackID.isEmpty else { return nil }
        let fileURL = directoryURL.appendingPathComponent("\(Self.sha256Hex(trackID)).ttml")
        guard let data = try? Data(contentsOf: fileURL),
              let parsed = try? TtmlLyricsParser.parse(data: data) else {
            return nil
        }
        return Lyrics(
            lines: parsed.lines,
            synced: parsed.synced,
            wordSynced: parsed.wordSynced,
            provider: "Imported TTML",
            colors: parsed.colors,
            isRTL: parsed.isRTL,
            songwriters: parsed.songwriters,
            isLocalImport: true
        )
    }

    public func importFile(from externalURL: URL, forTrackID trackID: String, trackDisplayTitle: String) throws -> Lyrics {
        let scoped = externalURL.startAccessingSecurityScopedResource()
        defer { if scoped { externalURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: externalURL)
        let parsed = try TtmlLyricsParser.parse(data: data)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileName = "\(Self.sha256Hex(trackID)).ttml"
        let destURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: destURL, options: .atomic)

        var entries = listEntries()
        entries.removeAll { $0.trackID == trackID }
        entries.append(
            ImportedTtmlEntry(
                trackID: trackID,
                trackDisplayTitle: trackDisplayTitle,
                fileName: fileName,
                importedAt: Date()
            )
        )
        saveIndex(entries)

        return Lyrics(
            lines: parsed.lines,
            synced: parsed.synced,
            wordSynced: parsed.wordSynced,
            provider: "Imported TTML",
            colors: parsed.colors,
            isRTL: parsed.isRTL,
            songwriters: parsed.songwriters,
            isLocalImport: true
        )
    }

    public func listEntries() -> [ImportedTtmlEntry] {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([ImportedTtmlEntry].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.trackDisplayTitle.localizedCaseInsensitiveCompare($1.trackDisplayTitle) == .orderedAscending }
    }

    public func removeImport(forTrackID trackID: String) {
        let fileURL = directoryURL.appendingPathComponent("\(Self.sha256Hex(trackID)).ttml")
        try? FileManager.default.removeItem(at: fileURL)
        var entries = listEntries()
        entries.removeAll { $0.trackID == trackID }
        saveIndex(entries)
    }

    private func saveIndex(_ entries: [ImportedTtmlEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: indexFileURL, options: .atomic)
        }
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
