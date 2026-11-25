//
//  LrcParser.swift
//  Celestify
//
//  Full LRC & Enhanced LRC (ELRC) parser supporting standard [mm:ss.xx]/[mm:ss.xxx]
//  timestamps, multi-timestamp chorus lines, [offset:+/-ms] tags, inline <mm:ss.xx>
//  word/syllable timestamps, UTF-8 BOM/CRLF normalization, and malformed tag resilience.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public struct LrcMetadata: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var author: String?
    public var offsetMs: Int64 = 0

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        author: String? = nil,
        offsetMs: Int64 = 0
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.author = author
        self.offsetMs = offsetMs
    }
}

public struct ParsedLrcDocument: Sendable, Equatable {
    public let metadata: LrcMetadata
    public let lines: [LyricLine]
    public let isSynced: Bool
    public let isWordSynced: Bool
}

public enum LrcParser {
    private static let lineTagRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    )
    private static let enhancedWordRegex = try! NSRegularExpression(
        pattern: #"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#
    )
    private static let metaTagRegex = try! NSRegularExpression(
        pattern: #"^\s*\[(ti|ar|al|by|au|offset)\s*:\s*([^\]]*)\]\s*$"#,
        options: [.caseInsensitive]
    )

    /// Parses raw LRC, Enhanced LRC, or plain unsynced text into `ParsedLrcDocument`.
    public static func parseDocument(_ rawInput: String) -> ParsedLrcDocument {
        let normalized = normalizeText(rawInput)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ParsedLrcDocument(metadata: LrcMetadata(), lines: [], isSynced: false, isWordSynced: false)
        }

        var metadata = LrcMetadata()
        var timedLines: [LyricLine] = []
        var plainFallbackLines: [String] = []
        var sawAnyTimestamp = false

        let rawLines = normalized.components(separatedBy: "\n")
        for rawLine in rawLines {
            let lineRange = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)

            // 1. Check metadata header tag ([offset:+200], [ti:...], etc.)
            if let metaMatch = metaTagRegex.firstMatch(in: rawLine, range: lineRange),
               let keyRange = Range(metaMatch.range(at: 1), in: rawLine),
               let valRange = Range(metaMatch.range(at: 2), in: rawLine) {
                let key = rawLine[keyRange].lowercased()
                let value = rawLine[valRange].trimmingCharacters(in: .whitespaces)
                switch key {
                case "ti": metadata.title = value
                case "ar": metadata.artist = value
                case "al": metadata.album = value
                case "by", "au": metadata.author = value
                case "offset":
                    if let parsedOffset = Int64(value.replacingOccurrences(of: "+", with: "")) {
                        metadata.offsetMs = parsedOffset
                    }
                default: break
                }
                continue
            }

            // 2. Match all valid [mm:ss.xx] line tags (ignoring malformed seconds >= 60)
            let tagMatches = lineTagRegex.matches(in: rawLine, range: lineRange)
            var validTimestamps: [Int64] = []
            var lastTagUpperBound = rawLine.startIndex

            for match in tagMatches {
                if let r = Range(match.range, in: rawLine) {
                    if r.upperBound > lastTagUpperBound {
                        lastTagUpperBound = r.upperBound
                    }
                }
                if let ms = parseTimestamp(match: match, in: rawLine) {
                    validTimestamps.append(ms)
                }
            }

            guard !validTimestamps.isEmpty else {
                // Skip unknown bracket-only metadata tags like [length:03:45] or malformed [ab:cd.ef]
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !(trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && !trimmed.dropFirst().contains("[")) {
                    plainFallbackLines.append(trimmed)
                }
                continue
            }

            sawAnyTimestamp = true
            let body = String(rawLine[lastTagUpperBound...])
            let bodyRange = NSRange(body.startIndex..<body.endIndex, in: body)
            let wordMatches = enhancedWordRegex.matches(in: body, range: bodyRange)

            let cleanText = enhancedWordRegex
                .stringByReplacingMatches(in: body, range: bodyRange, withTemplate: "")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let finalLineText = cleanText.isEmpty ? "♪" : cleanText

            // Enhanced word tags are kept when the line has a single unambiguous line timestamp
            var parsedWords: [LyricWord] = []
            if validTimestamps.count == 1 && !wordMatches.isEmpty {
                for (index, stamp) in wordMatches.enumerated() {
                    guard let startMs = parseTimestamp(match: stamp, in: body),
                          let stampRange = Range(stamp.range, in: body) else { continue }
                    let segmentEnd: String.Index = {
                        if index + 1 < wordMatches.count,
                           let nextRange = Range(wordMatches[index + 1].range, in: body) {
                            return nextRange.lowerBound
                        }
                        return body.endIndex
                    }()
                    let rawSlice = String(body[stampRange.upperBound..<segmentEnd])
                    let hasTrailingSpace = rawSlice.hasSuffix(" ")
                    let token = rawSlice.trimmingCharacters(in: .whitespaces)
                    guard !token.isEmpty else { continue }

                    let nextWordStart: Int64 = {
                        if index + 1 < wordMatches.count,
                           let nextMs = parseTimestamp(match: wordMatches[index + 1], in: body) {
                            return max(startMs, nextMs)
                        }
                        return startMs + 350
                    }()
                    let isPartOfWord = !hasTrailingSpace && (index + 1 < wordMatches.count)
                    parsedWords.append(
                        LyricWord(
                            text: token,
                            startMs: applyOffset(startMs, offsetMs: metadata.offsetMs),
                            endMs: applyOffset(nextWordStart, offsetMs: metadata.offsetMs),
                            isPartOfWord: isPartOfWord
                        )
                    )
                }
            }

            // Optional duet marker ("v2:" / "[Duet]") recognition
            var speaker: LyricSpeaker = .main
            var displayWords = finalLineText
            if displayWords.hasPrefix("v2:") || displayWords.hasPrefix("V2:") {
                speaker = .duet
                displayWords = String(displayWords.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }

            for rawTs in validTimestamps {
                let adjustedStart = applyOffset(rawTs, offsetMs: metadata.offsetMs)
                timedLines.append(
                    LyricLine(
                        startMs: adjustedStart,
                        endMs: parsedWords.last?.endMs,
                        words: displayWords.isEmpty ? "♪" : displayWords,
                        speaker: speaker,
                        wordTimings: parsedWords
                    )
                )
            }
        }

        if !sawAnyTimestamp {
            let plain = plainFallbackLines.map {
                LyricLine(startMs: 0, words: $0, speaker: .main)
            }
            return ParsedLrcDocument(metadata: metadata, lines: plain, isSynced: false, isWordSynced: false)
        }

        // Stable sort by startMs, collapse consecutive instrumental "♪" rows, and infer line endMs
        let sorted = timedLines.enumerated()
            .sorted { a, b in
                if a.element.startMs != b.element.startMs {
                    return a.element.startMs < b.element.startMs
                }
                return a.offset < b.offset
            }
            .map(\.element)

        var collapsed: [LyricLine] = []
        for line in sorted {
            if line.words == "♪", collapsed.last?.words == "♪" {
                continue
            }
            collapsed.append(line)
        }

        // Trim trailing standalone "♪" if it's the very last marker with nothing after
        var finalized: [LyricLine] = []
        for (idx, line) in collapsed.enumerated() {
            let nextStart: Int64? = idx + 1 < collapsed.count ? collapsed[idx + 1].startMs : nil
            let resolvedEnd = line.endMs ?? nextStart
            var updatedWords = line.wordTimings
            if let lastIdx = updatedWords.indices.last,
               let nextStart,
               updatedWords[lastIdx].endMs > nextStart {
                let w = updatedWords[lastIdx]
                updatedWords[lastIdx] = LyricWord(
                    text: w.text,
                    startMs: w.startMs,
                    endMs: max(w.startMs, nextStart),
                    isPartOfWord: w.isPartOfWord
                )
            }
            finalized.append(
                LyricLine(
                    startMs: line.startMs,
                    endMs: resolvedEnd,
                    words: line.words,
                    speaker: line.speaker,
                    wordTimings: updatedWords
                )
            )
        }

        let hasWordSync = finalized.contains { !$0.wordTimings.isEmpty }
        let hasLineSync = finalized.contains { $0.startMs > 0 } || finalized.count > 1
        return ParsedLrcDocument(
            metadata: metadata,
            lines: finalized,
            isSynced: hasLineSync,
            isWordSynced: hasWordSync
        )
    }

    public static func parseLines(_ rawInput: String) -> [LyricLine] {
        parseDocument(rawInput).lines
    }

    // MARK: - Helpers

    /// In standard LRC, positive `[offset:+500]` shifts timestamps earlier (`raw - offset`),
    /// negative `[offset:-500]` delays them (`raw - (-500) = raw + 500`), clamped at `0`.
    private static func applyOffset(_ rawMs: Int64, offsetMs: Int64) -> Int64 {
        max(0, rawMs - offsetMs)
    }

    private static func parseTimestamp(match: NSTextCheckingResult, in text: String) -> Int64? {
        guard let minRange = Range(match.range(at: 1), in: text),
              let secRange = Range(match.range(at: 2), in: text),
              let minutes = Int64(text[minRange]),
              let seconds = Int64(text[secRange]),
              seconds < 60 else {
            return nil
        }

        var millis: Int64 = 0
        if match.range(at: 3).location != NSNotFound,
           let fracRange = Range(match.range(at: 3), in: text) {
            let fracStr = String(text[fracRange])
            switch fracStr.count {
            case 1: millis = (Int64(fracStr) ?? 0) * 100
            case 2: millis = (Int64(fracStr) ?? 0) * 10
            default: millis = Int64(fracStr.prefix(3)) ?? 0
            }
        }
        return minutes * 60_000 + seconds * 1_000 + millis
    }

    private static func normalizeText(_ raw: String) -> String {
        var cleaned = raw
        if cleaned.hasPrefix("\u{FEFF}") {
            cleaned.removeFirst()
        }
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")
        return cleaned
    }
}
