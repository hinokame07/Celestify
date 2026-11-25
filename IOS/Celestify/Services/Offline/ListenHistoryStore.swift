//
//  ListenHistoryStore.swift
//  Celestify
//
//  Private on-device JSONL listening history (`>= 30s` play threshold) powering
//  Celestify's Weekly Minutes chart and Top Tracks / Top Artists / Top Albums Recap.
//  Ported 1:1 from Android ListenHistory.kt.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public enum ListenSource: String, Codable, Sendable, CaseIterable {
    case spotify = "SPOTIFY"
    case download = "DOWNLOAD"
    case local = "LOCAL"
}

public struct ListenRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(atMs):\(key)" }
    public let atMs: Int64
    public let key: String
    public let title: String
    public let artist: String
    public let album: String
    public let coverURL: String
    public let playedMs: Int64
    public let source: ListenSource

    public init(
        atMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        key: String,
        title: String,
        artist: String,
        album: String,
        coverURL: String,
        playedMs: Int64,
        source: ListenSource
    ) {
        self.atMs = atMs
        self.key = key
        self.title = title
        self.artist = artist
        self.album = album
        self.coverURL = coverURL
        self.playedMs = playedMs
        self.source = source
    }
}

public struct RankedListenEntity: Sendable, Identifiable, Hashable {
    public var id: String { "\(name)|\(subtitle)" }
    public let name: String
    public let subtitle: String
    public let coverURL: String
    public let playCount: Int
    public let minutes: Int64
}

public struct WeeklyListeningBucket: Sendable, Identifiable, Hashable {
    public var id: Int64 { weekStartMs }
    public let weekStartMs: Int64
    public let minutes: Int64

    public var weekStartDate: Date {
        Date(timeIntervalSince1970: Double(weekStartMs) / 1000.0)
    }
}

public struct ListeningRecap: Sendable, Hashable {
    public let totalListens: Int
    public let totalMinutes: Int64
    public let minutesBySource: [ListenSource: Int64]
    public let topTracks: [RankedListenEntity]
    public let topArtists: [RankedListenEntity]
    public let topAlbums: [RankedListenEntity]
}

public final class ListenHistoryStore: @unchecked Sendable {
    public static let shared = ListenHistoryStore()
    public static let minimumCountedPlayMs: Int64 = 30_000

    private let lock = NSLock()
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            self.fileURL = support.appendingPathComponent("listen_history.jsonl")
        }
    }

    public func record(_ listen: ListenRecord) {
        guard listen.playedMs >= Self.minimumCountedPlayMs,
              !listen.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let lineData = try? encoder.encode(listen),
              var lineStr = String(data: lineData, encoding: .utf8) else {
            return
        }
        lineStr.append("\n")
        guard let outBytes = lineStr.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: outBytes)
            try? handle.close()
        } else {
            try? outBytes.write(to: fileURL, options: .atomic)
        }
    }

    public func allRecords() -> [ListenRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        return content.components(separatedBy: .newlines).compactMap { line in
            guard !line.isEmpty, let d = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ListenRecord.self, from: d)
        }
    }

    public func clear() {
        lock.lock()
        try? FileManager.default.removeItem(at: fileURL)
        lock.unlock()
    }

    public func weeklyBreakdown(
        weeks: Int = 8,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeeklyListeningBucket] {
        let listens = allRecords()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        let startOfCurrentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        var weekStartsMs: [Int64] = []
        for step in (0..<max(1, weeks)).reversed() {
            if let d = calendar.date(byAdding: .weekOfYear, value: -step, to: startOfCurrentWeek) {
                weekStartsMs.append(Int64(d.timeIntervalSince1970 * 1000))
            }
        }
        let weekEndsMs = Array(weekStartsMs.dropFirst()) + [Int64.max]

        return weekStartsMs.indices.map { idx in
            let s = weekStartsMs[idx]
            let e = weekEndsMs[idx]
            let sumMs = listens
                .filter { $0.atMs >= s && $0.atMs < e && $0.atMs <= nowMs }
                .reduce(Int64(0)) { $0 + $1.playedMs }
            return WeeklyListeningBucket(weekStartMs: s, minutes: sumMs / 60_000)
        }
    }

    public func recap(sinceMs: Int64 = 0) -> ListeningRecap {
        let filtered = allRecords().filter { $0.atMs >= sinceMs }

        func rank(groupKey: (ListenRecord) -> String, subtitle: (ListenRecord) -> String, cleanName: (String) -> String = { $0 }) -> [RankedListenEntity] {
            let grouped = Dictionary(grouping: filtered, by: groupKey)
            return grouped.compactMap { key, items -> RankedListenEntity? in
                guard !key.trimmingCharacters(in: .whitespaces).isEmpty, let first = items.first else { return nil }
                let mins = items.reduce(Int64(0)) { $0 + $1.playedMs } / 60_000
                return RankedListenEntity(
                    name: cleanName(key),
                    subtitle: subtitle(first),
                    coverURL: first.coverURL,
                    playCount: items.count,
                    minutes: mins
                )
            }
            .sorted { a, b in
                if a.playCount != b.playCount { return a.playCount > b.playCount }
                return a.minutes > b.minutes
            }
            .prefix(10)
            .map { $0 }
        }

        let bySrc = Dictionary(grouping: filtered, by: \.source)
            .mapValues { items in items.reduce(Int64(0)) { $0 + $1.playedMs } / 60_000 }

        return ListeningRecap(
            totalListens: filtered.count,
            totalMinutes: filtered.reduce(Int64(0)) { $0 + $1.playedMs } / 60_000,
            minutesBySource: bySrc,
            topTracks: rank(
                groupKey: { "\($0.title)\u{0000}\($0.artist)" },
                subtitle: { $0.artist },
                cleanName: { $0.components(separatedBy: "\u{0000}").first ?? $0 }
            ),
            topArtists: rank(
                groupKey: { $0.artist.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? $0.artist },
                subtitle: { _ in "" }
            ),
            topAlbums: rank(
                groupKey: \.album,
                subtitle: \.artist
            )
        )
    }
}
