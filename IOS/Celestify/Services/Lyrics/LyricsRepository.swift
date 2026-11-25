//
//  LyricsRepository.swift
//  Celestify
//
//  Multi-provider progressive lyrics resolution engine porting Android LyricsApi.kt:
//    1. Local TTML Imports (`SpicyImportsStore`)
//    2. Spicy Lyrics Hosted Catalogue (`api.spicylyrics.org`)
//    3. Spotify `color-lyrics/v2` (with progressive early emission + ARGB palette)
//    4. LyricsPlus (`lyricsplus.binimum.org` & `lyricsplus.prjktla.my.id` syllable & duet API)
//    5. Apple Music via `lrc.red` (`/search.json` -> `/s/{isrc}.ttml`)
//    6. Kugou KRC (`lyrics.kugou.com` encrypted word-by-word karaoke)
//    7. LRCLIB (`lrclib.net/api/get` & `/api/search` synced LRC / ELRC)
//    8. Opt-in Extra Sources: NetEase Cloud Music & Genius balanced HTML lyrics scraper
//    9. Installed JavaScriptCore Lyrics Extensions (`ExtensionManager`)
//
//  Includes 100-entry LRU memory cache (2-min miss TTL) + 300-file SHA-256 14-day disk cache,
//  and median-delta Spotify audio intro alignment (`LyricTiming.alignToSpotifyAudio`).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import CryptoKit
import Foundation

public actor LyricsRepository {
    private let api: SpotifyAPIClient
    private let http: HTTPClient
    private let spicyCatalogue: SpicyCatalogueService
    private let spicyImports: SpicyImportsStore
    private let extensions: ExtensionManager

    private struct CachedRecord: Codable {
        let savedAt: Date
        let lyrics: Lyrics
    }

    private var memoryCache: [String: Lyrics] = [:]
    private var memoryOrder: [String] = []
    private var missCache: [String: Date] = [:]
    private var inFlight: [String: Task<Lyrics?, Never>] = [:]
    private let diskDirectory: URL

    private static let memoryLimit = 100
    private static let diskLimit = 300
    private static let diskTTLSeconds: TimeInterval = 14 * 24 * 3600
    private static let missTTLSeconds: TimeInterval = 120

    public init(
        api: SpotifyAPIClient,
        http: HTTPClient = .shared,
        spicyCatalogue: SpicyCatalogueService = .shared,
        spicyImports: SpicyImportsStore = .shared,
        extensions: ExtensionManager = .shared
    ) {
        self.api = api
        self.http = http
        self.spicyCatalogue = spicyCatalogue
        self.spicyImports = spicyImports
        self.extensions = extensions

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskDirectory = caches.appendingPathComponent("LyricsCacheV2", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Resolution API

    public func resolve(
        track: LyricsTrackQuery,
        wordSyncPreferred: Bool,
        extraSourcesEnabled: Bool,
        spicyKey: String = "",
        providerFirst: Bool = false,
        forceRefresh: Bool = false,
        onEarlySpotifyLineSync: (@Sendable (Lyrics) async -> Void)? = nil
    ) async -> Lyrics? {
        let cacheKey = Self.makeCacheKey(for: track, wordSync: wordSyncPreferred)

        // 1. Always honor local custom .ttml imports first
        if !track.id.isEmpty, let local = await spicyImports.readImportedLyrics(forTrackID: track.id) {
            return local
        }

        if !forceRefresh {
            if let mem = memoryCache[cacheKey] { return mem }
            if let missedAt = missCache[cacheKey], Date().timeIntervalSince(missedAt) < Self.missTTLSeconds {
                return nil
            }
            if let disk = readDiskCache(forKey: cacheKey) {
                storeMemoryCache(key: cacheKey, lyrics: disk)
                return disk
            }
        } else {
            forget(track: track)
        }

        if let running = inFlight[cacheKey] {
            return await running.value
        }

        let task = Task<Lyrics?, Never> {
            await performResolution(
                track: track,
                wordSyncPreferred: wordSyncPreferred,
                extraSourcesEnabled: extraSourcesEnabled,
                spicyKey: spicyKey,
                providerFirst: providerFirst,
                forceRefresh: forceRefresh,
                onEarlySpotifyLineSync: onEarlySpotifyLineSync
            )
        }
        inFlight[cacheKey] = task
        let resolved = await task.value
        inFlight.removeValue(forKey: cacheKey)

        if let resolved {
            storeMemoryCache(key: cacheKey, lyrics: resolved)
            if resolved.synced {
                writeDiskCache(key: cacheKey, lyrics: resolved)
            }
        } else {
            missCache[cacheKey] = Date()
        }
        return resolved
    }

    public func forget(track: LyricsTrackQuery) {
        for flag in [true, false] {
            let k = Self.makeCacheKey(for: track, wordSync: flag)
            memoryCache.removeValue(forKey: k)
            memoryOrder.removeAll { $0 == k }
            missCache.removeValue(forKey: k)
            let file = diskDirectory.appendingPathComponent("\(Self.sha256Hex(k)).json")
            try? FileManager.default.removeItem(at: file)
        }
    }

    public func forgetAll() {
        memoryCache.removeAll()
        memoryOrder.removeAll()
        missCache.removeAll()
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Core Multi-Provider Pipeline

    private func performResolution(
        track: LyricsTrackQuery,
        wordSyncPreferred: Bool,
        extraSourcesEnabled: Bool,
        spicyKey: String,
        providerFirst: Bool,
        forceRefresh: Bool,
        onEarlySpotifyLineSync: (@Sendable (Lyrics) async -> Void)?
    ) async -> Lyrics? {
        let askedTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = Self.cleanSearchTitle(askedTitle)
        let primaryArtist = track.artist.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? track.artist
        let durationMs = track.durationMs

        // Check Spicy hosted catalogue when key is configured and !providerFirst
        if !providerFirst, !spicyKey.isEmpty, !track.id.isEmpty {
            if let spicy = await spicyCatalogue.lookup(trackID: track.id, apiKey: spicyKey, forceReload: forceRefresh) {
                return spicy
            }
        }

        // Check installed lyrics extensions
        let extTask = Task { await extensions.queryLyricsExtensions(track: track) }

        if wordSyncPreferred {
            async let spotifyTask = fetchFromSpotify(trackID: track.id)
            async let plusTask = fetchFromLyricsPlus(askedTitle: askedTitle, cleanTitle: cleanTitle, artist: primaryArtist, durationMs: durationMs)
            async let lrcRedTask = fetchFromLrcRed(askedTitle: askedTitle, cleanTitle: cleanTitle, artist: primaryArtist, durationMs: durationMs, knownISRC: track.isrc)
            async let kugouTask = fetchFromKugou(title: cleanTitle, artist: primaryArtist, durationMs: durationMs)

            let sp = await spotifyTask
            if let sp, sp.wordSynced {
                return sp
            }
            // Progressive early emission: show Spotify's line-synced lyrics immediately while word-sync finishes
            if let sp, let onEarlySpotifyLineSync {
                await onEarlySpotifyLineSync(sp)
            }

            let plus = await plusTask
            let red = await lrcRedTask
            let kugou = await kugouTask
            let extLyrics = await extTask.value

            let wordCandidate: Lyrics? = [extLyrics, plus, red, kugou]
                .compactMap { $0 }
                .first(where: \.wordSynced)

            if let wordCandidate {
                return LyricTiming.alignToSpotifyAudio(wordCandidate, spotifyReference: sp)
                    .withColors(sp?.colors)
            }

            if let plus, plus.synced, plus.hasDuets {
                return LyricTiming.alignToSpotifyAudio(plus, spotifyReference: sp)
                    .withColors(sp?.colors)
            }

            if let sp, sp.synced { return sp }
            if let plus, plus.synced { return plus }

            let fallback = await resolveLineAndPlainFallbacks(
                cleanTitle: cleanTitle,
                artist: primaryArtist,
                album: track.album,
                durationMs: durationMs,
                extraSourcesEnabled: extraSourcesEnabled
            )
            return Self.preferSynced(fallback, over: sp ?? plus ?? extLyrics)
                .map { $0.withColors(sp?.colors) }
        } else {
            // Line-sync mode: Spotify first, then LRCLIB, then opt-in NetEase/Genius/Kugou
            let sp = await fetchFromSpotify(trackID: track.id)
            if let sp, sp.synced { return sp }

            let extLyrics = await extTask.value
            if let extLyrics, extLyrics.synced { return extLyrics.withColors(sp?.colors) }

            let fallback = await resolveLineAndPlainFallbacks(
                cleanTitle: cleanTitle,
                artist: primaryArtist,
                album: track.album,
                durationMs: durationMs,
                extraSourcesEnabled: extraSourcesEnabled
            )
            return Self.preferSynced(fallback, over: sp ?? extLyrics)
                .map { $0.withColors(sp?.colors) }
        }
    }

    private func resolveLineAndPlainFallbacks(
        cleanTitle: String,
        artist: String,
        album: String,
        durationMs: Int64,
        extraSourcesEnabled: Bool
    ) async -> Lyrics? {
        let durationSec = Int(durationMs / 1000)
        async let exactLrc = fetchFromLRCLIBExact(title: cleanTitle, artist: artist, album: album, durationSec: durationSec)
        async let searchLrc = fetchFromLRCLIBSearch(title: cleanTitle, artist: artist, durationSec: durationSec)
        async let netEaseTask: Lyrics? = extraSourcesEnabled ? fetchFromNetEase(title: cleanTitle, artist: artist, durationSec: durationSec) : nil
        async let geniusTask: Lyrics? = extraSourcesEnabled ? fetchFromGenius(title: cleanTitle, artist: artist) : nil

        let lrcBest = Self.preferSynced(await exactLrc, over: await searchLrc)
        if let lrcBest, lrcBest.synced { return lrcBest }

        let netEase = await netEaseTask
        if let netEase, netEase.synced { return netEase }

        if let kugou = await fetchFromKugou(title: cleanTitle, artist: artist, durationMs: durationMs), kugou.synced {
            return kugou
        }

        if let lrcBest { return lrcBest }
        if let netEase { return netEase }
        return await geniusTask
    }

    // MARK: - Provider 1: Spotify Color-Lyrics v2

    private func fetchFromSpotify(trackID: String) async -> Lyrics? {
        guard !trackID.isEmpty, !trackID.hasPrefix("local:") else { return nil }
        return try? await api.spotifyColorLyrics(trackID: trackID)
    }

    // MARK: - Provider 2: LyricsPlus (Syllable + Duet Relay)

    private func fetchFromLyricsPlus(askedTitle: String, cleanTitle: String, artist: String, durationMs: Int64) async -> Lyrics? {
        let mirrors = [
            "https://lyricsplus.binimum.org",
            "https://lyricsplus.prjktla.my.id"
        ]
        for base in mirrors {
            var comps = URLComponents(string: "\(base)/v2/lyrics/get")!
            var items = [
                URLQueryItem(name: "title", value: cleanTitle),
                URLQueryItem(name: "artist", value: artist),
                URLQueryItem(name: "source", value: "apple,lyricsplus,musixmatch-word,musixmatch,spotify")
            ]
            if durationMs > 0 {
                items.append(URLQueryItem(name: "duration", value: String(durationMs / 1000)))
            }
            comps.queryItems = items
            guard let url = comps.url,
                  let json = try? await http.getJSON(url: url) else { continue }

            let rawLyrics = json.list("lyrics")
            guard !rawLyrics.isEmpty else { continue }

            let typeStr = (json.str("type") ?? "").lowercased()
            let isSyllable = typeStr == "word" || typeStr == "syllable"

            // Detect primary singer for duet alignment
            var singerOrder: [String] = []
            for item in rawLyrics {
                if let s = item.str("element.singer"), !s.isEmpty, !singerOrder.contains(s) {
                    singerOrder.append(s)
                }
            }
            let duetSingers = singerOrder.count > 1 ? Set(singerOrder.dropFirst()) : []

            var lines: [LyricLine] = []
            var sawWords = false
            for item in rawLyrics {
                let startMs = item.int64("time") ?? 0
                let durMs = item.int64("duration") ?? 0
                let text = (item.str("text") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                let singer = item.str("element.singer") ?? ""
                let speaker: LyricSpeaker = duetSingers.contains(singer) ? .duet : .main

                let syllabus = item.list("syllabus")
                var wordTimings: [LyricWord] = []
                if isSyllable && !syllabus.isEmpty {
                    for (idx, syl) in syllabus.enumerated() {
                        let rawSylText = syl.str("text") ?? ""
                        let isBg = syl.bool("isBackground") ?? false
                        if isBg { continue }
                        let hasSpace = rawSylText.hasSuffix(" ")
                        let trimmedSyl = rawSylText.trimmingCharacters(in: .whitespaces)
                        guard !trimmedSyl.isEmpty else { continue }
                        let wStart = syl.int64("time") ?? startMs
                        let wDur = syl.int64("duration") ?? 220
                        wordTimings.append(
                            LyricWord(
                                text: trimmedSyl,
                                startMs: wStart,
                                endMs: wStart + max(0, wDur),
                                isPartOfWord: !hasSpace && (idx + 1 < syllabus.count)
                            )
                        )
                    }
                    if let lastIdx = wordTimings.indices.last {
                        let last = wordTimings[lastIdx]
                        wordTimings[lastIdx] = LyricWord(text: last.text, startMs: last.startMs, endMs: last.endMs, isPartOfWord: false)
                    }
                }
                if !wordTimings.isEmpty { sawWords = true }

                lines.append(
                    LyricLine(
                        startMs: startMs,
                        endMs: durMs > 0 ? startMs + durMs : nil,
                        words: text,
                        speaker: speaker,
                        wordTimings: wordTimings,
                        romanized: item.str("transliteration")
                    )
                )
            }

            guard !lines.isEmpty else { continue }
            let srcName = json.str("metadata.source") ?? "LyricsPlus"
            return Lyrics(
                lines: lines,
                synced: typeStr != "none" && lines.contains(where: { $0.startMs > 0 }),
                wordSynced: sawWords,
                provider: srcName,
                isRTL: lines.contains { LyricTiming.containsRTLCharacters($0.words) }
            )
        }
        return nil
    }

    // MARK: - Provider 3: lrc.red (Apple Music TTML by ISRC / Search)

    private func fetchFromLrcRed(
        askedTitle: String,
        cleanTitle: String,
        artist: String,
        durationMs: Int64,
        knownISRC: String?
    ) async -> Lyrics? {
        var isrc = knownISRC
        if isrc == nil || isrc?.isEmpty == true {
            var comps = URLComponents(string: "https://lrc.red/search.json")!
            comps.queryItems = [URLQueryItem(name: "q", value: "\(cleanTitle) \(artist)")]
            if let searchURL = comps.url,
               let arr = try? await http.getJSON(url: searchURL) {
                for cand in arr.list() {
                    let cTitle = cand.str("title") ?? cand.str("name") ?? ""
                    let cArtist = cand.str("artist") ?? ""
                    let cDurMs = (cand.int64("duration") ?? 0) * (cand.int64("duration") ?? 0 < 2000 ? 1000 : 1)
                    if Self.isSameSong(candTitle: cTitle, candArtist: cArtist, candDurationMs: cDurMs, title: cleanTitle, artist: artist, durationMs: durationMs),
                       let foundISRC = cand.str("isrc"), !foundISRC.isEmpty {
                        isrc = foundISRC
                        break
                    }
                }
            }
        }

        guard let validISRC = isrc, !validISRC.isEmpty,
              let ttmlURL = URL(string: "https://lrc.red/s/\(validISRC).ttml"),
              let res = try? await http.send(url: ttmlURL, maxBytes: TtmlLyricsParser.maxBytes),
              res.statusCode == 200,
              let parsed = try? TtmlLyricsParser.parse(data: res.data) else {
            return nil
        }

        return Lyrics(
            lines: parsed.lines,
            synced: parsed.synced,
            wordSynced: parsed.wordSynced,
            provider: "Apple Music · lrc.red",
            isRTL: parsed.isRTL,
            songwriters: parsed.songwriters
        )
    }

    // MARK: - Provider 4: Kugou KRC

    private func fetchFromKugou(title: String, artist: String, durationMs: Int64) async -> Lyrics? {
        var comps = URLComponents(string: "https://lyrics.kugou.com/search")!
        var items = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "keyword", value: "\(artist) - \(title)")
        ]
        if durationMs > 0 {
            items.append(URLQueryItem(name: "duration", value: String(durationMs)))
        }
        comps.queryItems = items
        guard let searchURL = comps.url,
              let searchJSON = try? await http.getJSON(url: searchURL) else { return nil }

        let candidates = searchJSON.list("candidates")
        guard let matched = candidates.first(where: { cand in
            Self.isSameSong(
                candTitle: cand.str("song") ?? "",
                candArtist: cand.str("singer") ?? "",
                candDurationMs: cand.int64("duration") ?? 0,
                title: title,
                artist: artist,
                durationMs: durationMs
            )
        }),
              let id = matched.str("id"),
              let accessKey = matched.str("accesskey") else {
            return nil
        }

        var dlComps = URLComponents(string: "https://lyrics.kugou.com/download")!
        dlComps.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "accesskey", value: accessKey),
            URLQueryItem(name: "fmt", value: "krc"),
            URLQueryItem(name: "charset", value: "utf8")
        ]
        guard let dlURL = dlComps.url,
              let dlJSON = try? await http.getJSON(url: dlURL),
              let contentB64 = dlJSON.str("content"),
              let decodedText = KrcParser.decryptBase64(contentB64) else {
            return nil
        }

        let lines = KrcParser.parseDecodedText(decodedText)
        guard lines.count >= 3 else { return nil }
        return Lyrics(
            lines: lines,
            synced: true,
            wordSynced: lines.contains { !$0.wordTimings.isEmpty },
            provider: "Kugou",
            isRTL: lines.contains { LyricTiming.containsRTLCharacters($0.words) }
        )
    }

    // MARK: - Provider 5: LRCLIB

    private func fetchFromLRCLIBExact(title: String, artist: String, album: String, durationSec: Int) async -> Lyrics? {
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if durationSec > 0 { items.append(URLQueryItem(name: "duration", value: String(durationSec))) }
        comps.queryItems = items
        guard let url = comps.url,
              let json = try? await http.getJSON(url: url) else { return nil }
        return parseLRCLIBItem(json)
    }

    private func fetchFromLRCLIBSearch(title: String, artist: String, durationSec: Int) async -> Lyrics? {
        guard !title.isEmpty else { return nil }
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = comps.url,
              let arr = try? await http.getJSON(url: url) else { return nil }

        for item in arr.list() {
            let cTitle = item.str("trackName") ?? ""
            let cArtist = item.str("artistName") ?? ""
            let cDurSec = Int(item.double("duration") ?? 0)
            if Self.isPlausibleFallbackMatch(candTitle: cTitle, candArtist: cArtist, candDurationSec: cDurSec, title: title, artist: artist, durationSec: durationSec),
               let parsed = parseLRCLIBItem(item) {
                return parsed
            }
        }
        return nil
    }

    private func parseLRCLIBItem(_ item: JSONValue) -> Lyrics? {
        if item.bool("instrumental") == true {
            return Lyrics(
                lines: [LyricLine(startMs: 0, words: "♪ Instrumental")],
                synced: false,
                provider: "LRCLIB"
            )
        }
        if let syncedLrc = item.str("syncedLyrics"), !syncedLrc.isEmpty {
            let doc = LrcParser.parseDocument(syncedLrc)
            if !doc.lines.isEmpty {
                return Lyrics(
                    lines: doc.lines,
                    synced: doc.isSynced,
                    wordSynced: doc.isWordSynced,
                    provider: "LRCLIB",
                    isRTL: doc.lines.contains { LyricTiming.containsRTLCharacters($0.words) }
                )
            }
        }
        if let plain = item.str("plainLyrics"), !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { LyricLine(startMs: 0, words: $0) }
            if !lines.isEmpty {
                return Lyrics(lines: lines, synced: false, provider: "LRCLIB")
            }
        }
        return nil
    }

    // MARK: - Provider 6 & 7 (Opt-In): NetEase Cloud Music & Genius

    private func fetchFromNetEase(title: String, artist: String, durationSec: Int) async -> Lyrics? {
        var searchComps = URLComponents(string: "https://music.163.com/api/search/get")!
        searchComps.queryItems = [
            URLQueryItem(name: "s", value: "\(title) \(artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "6")
        ]
        guard let searchURL = searchComps.url,
              let searchJSON = try? await http.getJSON(url: searchURL) else { return nil }

        for song in searchJSON.list("result.songs") {
            let songTitle = song.str("name") ?? ""
            let songArtist = song.list("artists").first?.str("name") ?? ""
            let songDurSec = Int((song.int64("duration") ?? 0) / 1000)
            guard Self.isPlausibleFallbackMatch(candTitle: songTitle, candArtist: songArtist, candDurationSec: songDurSec, title: title, artist: artist, durationSec: durationSec),
                  let songID = song.int64("id"),
                  let lyricURL = URL(string: "https://music.163.com/api/song/lyric?id=\(songID)&lv=1&kv=1&tv=-1"),
                  let lyricJSON = try? await http.getJSON(url: lyricURL),
                  let rawLrc = lyricJSON.str("lrc.lyric"), !rawLrc.isEmpty else {
                continue
            }
            let doc = LrcParser.parseDocument(rawLrc)
            let filtered = doc.lines.filter { !$0.words.isEmpty && !$0.words.contains(" : ") }
            if !filtered.isEmpty {
                return Lyrics(
                    lines: filtered,
                    synced: doc.isSynced,
                    wordSynced: doc.isWordSynced,
                    provider: "NetEase Cloud Music"
                )
            }
        }
        return nil
    }

    private func fetchFromGenius(title: String, artist: String) async -> Lyrics? {
        var searchComps = URLComponents(string: "https://genius.com/api/search/song")!
        searchComps.queryItems = [
            URLQueryItem(name: "per_page", value: "5"),
            URLQueryItem(name: "q", value: "\(title) \(artist)")
        ]
        guard let searchURL = searchComps.url,
              let searchJSON = try? await http.getJSON(url: searchURL) else { return nil }

        let hits = searchJSON.list("response.sections").first?.list("hits") ?? []
        for hit in hits {
            guard let res = hit.at("result") else { continue }
            let cTitle = res.str("title") ?? ""
            let cArtist = res.str("primary_artist.name") ?? ""
            guard Self.isPlausibleFallbackMatch(candTitle: cTitle, candArtist: cArtist, candDurationSec: 0, title: title, artist: artist, durationSec: 0),
                  let pageURLStr = res.str("url"),
                  let pageURL = URL(string: pageURLStr),
                  let htmlRes = try? await http.send(url: pageURL, maxBytes: 2 * 1024 * 1024),
                  htmlRes.statusCode == 200 else {
                continue
            }
            let extracted = Self.extractGeniusLyricsHTML(htmlRes.text)
            if !extracted.isEmpty {
                return Lyrics(
                    lines: extracted.map { LyricLine(startMs: 0, words: $0) },
                    synced: false,
                    provider: "Genius"
                )
            }
        }
        return nil
    }

    /// Balanced `<div data-lyrics-container="true">` HTML extractor matching `LyricsApi.kt`.
    public nonisolated static func extractGeniusLyricsHTML(_ html: String) -> [String] {
        var chunks: [String] = []
        var searchRange = html.startIndex..<html.endIndex
        let marker = "data-lyrics-container=\"true\""

        while let markerRange = html.range(of: marker, range: searchRange) {
            guard let openTagEnd = html.range(of: ">", range: markerRange.upperBound..<html.endIndex) else { break }
            var depth = 1
            var cursor = openTagEnd.upperBound
            var endIdx = cursor

            while cursor < html.endIndex && depth > 0 {
                let nextOpen = html.range(of: "<div", options: .caseInsensitive, range: cursor..<html.endIndex)
                let nextClose = html.range(of: "</div", options: .caseInsensitive, range: cursor..<html.endIndex)
                guard let close = nextClose else { break }
                if let open = nextOpen, open.lowerBound < close.lowerBound {
                    depth += 1
                    cursor = open.upperBound
                } else {
                    depth -= 1
                    if depth == 0 {
                        endIdx = close.lowerBound
                    }
                    cursor = close.upperBound
                }
            }

            let inner = String(html[openTagEnd.upperBound..<endIdx])
                .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&#39;", with: "'")
            chunks.append(inner)
            searchRange = cursor..<html.endIndex
        }

        return chunks.joined(separator: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Title Normalization & Matching Helpers

    private static let featRegex = try! NSRegularExpression(
        pattern: #"\s*[(\[][^)\]]*(feat\.?|ft\.?|with\s)[^)\]]*[)\]]"#,
        options: [.caseInsensitive]
    )
    private static let editionRegex = try! NSRegularExpression(
        pattern: #"\s*[(\[][^)\]]*(remaster|remastered|live|version|edit|mono|stereo|deluxe|bonus)[^)\]]*[)\]]"#,
        options: [.caseInsensitive]
    )

    public nonisolated static func cleanSearchTitle(_ raw: String) -> String {
        let base = raw.components(separatedBy: " - ").first ?? raw
        let r1 = NSRange(base.startIndex..<base.endIndex, in: base)
        let withoutFeat = featRegex.stringByReplacingMatches(in: base, range: r1, withTemplate: "")
        let r2 = NSRange(withoutFeat.startIndex..<withoutFeat.endIndex, in: withoutFeat)
        return editionRegex
            .stringByReplacingMatches(in: withoutFeat, range: r2, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public nonisolated static func isSameSong(
        candTitle: String,
        candArtist: String,
        candDurationMs: Int64,
        title: String,
        artist: String,
        durationMs: Int64
    ) -> Bool {
        let targetArtist = LyricTiming.normalizedMatchKey(artist)
        let artistParts = candArtist.components(separatedBy: CharacterSet(charactersIn: ",&、/"))
        guard !targetArtist.isEmpty,
              artistParts.contains(where: { LyricTiming.normalizedMatchKey($0) == targetArtist }) else {
            return false
        }
        let t = LyricTiming.normalizedMatchKey(title)
        let ct = LyricTiming.normalizedMatchKey(cleanSearchTitle(candTitle))
        guard !t.isEmpty, (ct == t || ct.hasPrefix(t) || t.hasPrefix(ct)) else {
            return false
        }
        return durationMs <= 0 || candDurationMs <= 0 || abs(candDurationMs - durationMs) <= 4_000
    }

    public nonisolated static func isPlausibleFallbackMatch(
        candTitle: String,
        candArtist: String,
        candDurationSec: Int,
        title: String,
        artist: String,
        durationSec: Int
    ) -> Bool {
        let a1 = LyricTiming.normalizedMatchKey(candArtist)
        let a2 = LyricTiming.normalizedMatchKey(artist)
        let t1 = LyricTiming.normalizedMatchKey(cleanSearchTitle(candTitle))
        let t2 = LyricTiming.normalizedMatchKey(title)
        guard !a1.isEmpty && a1 == a2 && !t1.isEmpty && t1 == t2 else {
            return false
        }
        return durationSec <= 0 || candDurationSec <= 0 || abs(candDurationSec - durationSec) <= 3
    }

    private static func preferSynced(_ first: Lyrics?, over second: Lyrics?) -> Lyrics? {
        if first?.synced == true { return first }
        if second?.synced == true { return second }
        return first ?? second
    }

    // MARK: - Memory & Disk Cache Management

    private static func makeCacheKey(for track: LyricsTrackQuery, wordSync: Bool) -> String {
        let base = track.id.isEmpty ? "\(track.title)|\(track.artist)|\(track.durationMs)" : track.id
        return "\(base)#ws=\(wordSync ? 1 : 0)"
    }

    private func storeMemoryCache(key: String, lyrics: Lyrics) {
        memoryCache[key] = lyrics
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
        if memoryOrder.count > Self.memoryLimit, let oldest = memoryOrder.first {
            memoryOrder.removeFirst()
            memoryCache.removeValue(forKey: oldest)
        }
    }

    private func readDiskCache(forKey key: String) -> Lyrics? {
        let url = diskDirectory.appendingPathComponent("\(Self.sha256Hex(key)).json")
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(CachedRecord.self, from: data) else {
            return nil
        }
        if Date().timeIntervalSince(record.savedAt) > Self.diskTTLSeconds {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return record.lyrics
    }

    private func writeDiskCache(key: String, lyrics: Lyrics) {
        let url = diskDirectory.appendingPathComponent("\(Self.sha256Hex(key)).json")
        let record = CachedRecord(savedAt: Date(), lyrics: lyrics)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
        pruneDiskCacheIfNeeded()
    }

    private func pruneDiskCacheIfNeeded() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: diskDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), urls.count > Self.diskLimit else {
            return
        }
        let sorted = urls.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        for file in sorted.prefix(urls.count - Self.diskLimit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func sha256Hex(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
