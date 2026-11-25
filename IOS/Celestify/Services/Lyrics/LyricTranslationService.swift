//
//  LyricTranslationService.swift
//  Celestify
//
//  Batch lyric line translator powered by Google Translate GTX JSON endpoint,
//  matching Android LyricTranslate.kt with bounded LRU caching.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public struct TranslationLanguageOption: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public var id: String { code }

    public static let supported: [TranslationLanguageOption] = [
        TranslationLanguageOption(code: "", name: "Off"),
        TranslationLanguageOption(code: "en", name: "English"),
        TranslationLanguageOption(code: "pt", name: "Português"),
        TranslationLanguageOption(code: "es", name: "Español"),
        TranslationLanguageOption(code: "fr", name: "Français"),
        TranslationLanguageOption(code: "de", name: "Deutsch"),
        TranslationLanguageOption(code: "it", name: "Italiano"),
        TranslationLanguageOption(code: "ja", name: "日本語"),
        TranslationLanguageOption(code: "ko", name: "한국어"),
        TranslationLanguageOption(code: "zh-CN", name: "简体中文"),
        TranslationLanguageOption(code: "ru", name: "Русский"),
        TranslationLanguageOption(code: "ar", name: "العربية"),
        TranslationLanguageOption(code: "hi", name: "हिन्दी")
    ]
}

public actor LyricTranslationService {
    public static let shared = LyricTranslationService()

    private let http: HTTPClient
    private var cache: [String: [String]] = [:]
    private var cacheOrder: [String] = []
    private let maxEntries = 80

    public init(http: HTTPClient = .shared) {
        self.http = http
    }

    public func translateLyrics(_ lyrics: Lyrics, targetLanguage: String) async throws -> Lyrics {
        let lang = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lang.isEmpty else { return lyrics }

        // Lines that already carry native TTML translations for the same language can keep them,
        // otherwise batch-translate all non-instrumental lines in one round trip.
        let sourceLines = lyrics.lines.map(\.words)
        let key = "\(lang)|\(sourceLines.joined(separator: "\u{001F}").hashValue)"

        let translatedStrings: [String]
        if let hit = cache[key] {
            translatedStrings = hit
        } else {
            translatedStrings = try await translateBatch(lines: sourceLines, targetLanguage: lang)
            storeCache(key: key, value: translatedStrings)
        }

        let mergedLines: [LyricLine] = lyrics.lines.enumerated().map { idx, line in
            guard idx < translatedStrings.count else { return line }
            let candidate = translatedStrings[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isInstrumental || candidate.isEmpty || candidate.caseInsensitiveCompare(line.words) == .orderedSame {
                return line
            }
            return line.withAnnotations(translation: candidate)
        }

        return Lyrics(
            lines: mergedLines,
            synced: lyrics.synced,
            wordSynced: lyrics.wordSynced,
            provider: lyrics.provider,
            colors: lyrics.colors,
            isRTL: lyrics.isRTL,
            songwriters: lyrics.songwriters,
            isLocalImport: lyrics.isLocalImport
        )
    }

    public func translateParagraph(_ text: String, targetLanguage: String) async throws -> String {
        let lang = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lang.isEmpty, !text.isEmpty else { return text }
        let res = try await translateBatch(lines: [text], targetLanguage: lang)
        return res.first ?? text
    }

    private func translateBatch(lines: [String], targetLanguage: String) async throws -> [String] {
        guard !lines.isEmpty else { return [] }
        // Chunk into batches of up to 45 lines so URL query length stays well under HTTP limits
        var results: [String] = []
        results.reserveCapacity(lines.count)

        let chunkSize = 45
        for start in stride(from: 0, to: lines.count, by: chunkSize) {
            let slice = Array(lines[start..<min(start + chunkSize, lines.count)])
            let joined = slice.joined(separator: "\n")
            var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
            comps.queryItems = [
                URLQueryItem(name: "client", value: "gtx"),
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: targetLanguage),
                URLQueryItem(name: "dt", value: "t"),
                URLQueryItem(name: "q", value: joined)
            ]
            guard let url = comps.url else {
                results.append(contentsOf: slice)
                continue
            }
            let json = try await http.getJSON(url: url)
            // GTX response format: [[[translatedChunk, sourceChunk, ...], ...], null, detectedLang]
            let segments = json.list().first?.list() ?? []
            let combined = segments.compactMap { $0.list().first?.str() }.joined()
            let splitLines = combined.components(separatedBy: "\n")
            if splitLines.count == slice.count {
                results.append(contentsOf: splitLines)
            } else {
                for i in 0..<slice.count {
                    results.append(i < splitLines.count ? splitLines[i] : slice[i])
                }
            }
        }
        return results
    }

    private func storeCache(key: String, value: [String]) {
        cache[key] = value
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        if cacheOrder.count > maxEntries, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
