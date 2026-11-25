//
//  LyricsModels.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//  Spicy Lyrics TTML & syllable document extensions adapted under AGPL-3.0.
//

import Foundation
import SwiftUI

// MARK: - Core Lyrics Models

public enum LyricSpeaker: String, Codable, Sendable, Hashable {
    case main = "MAIN"
    case duet = "DUET"
    case background = "BACKGROUND"
}

public struct LyricWord: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(startMs)-\(endMs)-\(text)" }
    public let text: String
    public let startMs: Int64
    public let endMs: Int64
    /// True when this syllable continues immediately into the next syllable without a trailing space.
    public let isPartOfWord: Bool

    public init(text: String, startMs: Int64, endMs: Int64, isPartOfWord: Bool = false) {
        self.text = text
        self.startMs = startMs
        self.endMs = max(startMs, endMs)
        self.isPartOfWord = isPartOfWord
    }

    public var durationMs: Int64 { max(0, endMs - startMs) }
}

public struct LyricLine: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(startMs)-\(endMs ?? -1)-\(speaker.rawValue)-\(words)" }
    public let startMs: Int64
    public let endMs: Int64?
    public let words: String
    public let speaker: LyricSpeaker
    public let wordTimings: [LyricWord]
    public let wordsEstimated: Bool
    public let backgroundText: String?
    public let backgroundWords: [LyricWord]
    public let romanized: String?
    public let translation: String?

    public init(
        startMs: Int64,
        endMs: Int64? = nil,
        words: String,
        speaker: LyricSpeaker = .main,
        wordTimings: [LyricWord] = [],
        wordsEstimated: Bool = false,
        backgroundText: String? = nil,
        backgroundWords: [LyricWord] = [],
        romanized: String? = nil,
        translation: String? = nil
    ) {
        let normalizedStartMs = max(0, startMs)
        self.startMs = normalizedStartMs
        self.endMs = endMs.map { max(normalizedStartMs, $0) }
        self.words = words
        self.speaker = speaker
        self.wordTimings = wordTimings
        self.wordsEstimated = wordsEstimated
        self.backgroundText = backgroundText
        self.backgroundWords = backgroundWords
        self.romanized = romanized
        self.translation = translation
    }

    public var isInstrumental: Bool {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "♪" || trimmed == "♫" || trimmed == "..."
    }

    public func shifted(by deltaMs: Int64) -> LyricLine {
        LyricLine(
            startMs: max(0, startMs + deltaMs),
            endMs: endMs.map { max(0, $0 + deltaMs) },
            words: words,
            speaker: speaker,
            wordTimings: wordTimings.map {
                LyricWord(
                    text: $0.text,
                    startMs: max(0, $0.startMs + deltaMs),
                    endMs: max(0, $0.endMs + deltaMs),
                    isPartOfWord: $0.isPartOfWord
                )
            },
            wordsEstimated: wordsEstimated,
            backgroundText: backgroundText,
            backgroundWords: backgroundWords.map {
                LyricWord(
                    text: $0.text,
                    startMs: max(0, $0.startMs + deltaMs),
                    endMs: max(0, $0.endMs + deltaMs),
                    isPartOfWord: $0.isPartOfWord
                )
            },
            romanized: romanized,
            translation: translation
        )
    }

    public func withAnnotations(romanized: String? = nil, translation: String? = nil) -> LyricLine {
        LyricLine(
            startMs: startMs,
            endMs: endMs,
            words: words,
            speaker: speaker,
            wordTimings: wordTimings,
            wordsEstimated: wordsEstimated,
            backgroundText: backgroundText,
            backgroundWords: backgroundWords,
            romanized: romanized ?? self.romanized,
            translation: translation ?? self.translation
        )
    }
}

public struct LyricsColors: Codable, Sendable, Hashable {
    /// Signed 32-bit ARGB integers matching Spotify's `color-lyrics/v2` payload.
    public let background: Int32
    public let text: Int32
    public let highlightText: Int32

    public init(background: Int32, text: Int32, highlightText: Int32) {
        self.background = background
        self.text = text
        self.highlightText = highlightText
    }

    public var backgroundColor: Color { Self.color(fromARGB: background) }
    public var textColor: Color { Self.color(fromARGB: text) }
    public var highlightColor: Color { Self.color(fromARGB: highlightText) }

    public static func color(fromARGB argb: Int32) -> Color {
        let u = UInt32(bitPattern: argb)
        let r = Double((u >> 16) & 0xFF) / 255.0
        let g = Double((u >> 8) & 0xFF) / 255.0
        let b = Double(u & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

public enum LyricsSyncKind: String, Codable, Sendable, Hashable {
    case unsynced = "UNSYNCED"
    case lineSynced = "LINE_SYNCED"
    case syllableSynced = "SYLLABLE_SYNCED"
}

public struct Lyrics: Codable, Sendable, Hashable {
    public let lines: [LyricLine]
    public let synced: Bool
    public let wordSynced: Bool
    public let provider: String
    public let colors: LyricsColors?
    public let isRTL: Bool
    public let songwriters: [String]
    public let isLocalImport: Bool

    public init(
        lines: [LyricLine],
        synced: Bool,
        wordSynced: Bool = false,
        provider: String,
        colors: LyricsColors? = nil,
        isRTL: Bool = false,
        songwriters: [String] = [],
        isLocalImport: Bool = false
    ) {
        self.lines = lines
        self.synced = synced
        self.wordSynced = wordSynced
        self.provider = provider
        self.colors = colors
        self.isRTL = isRTL
        self.songwriters = songwriters
        self.isLocalImport = isLocalImport
    }

    public var syncKind: LyricsSyncKind {
        if wordSynced { return .syllableSynced }
        if synced { return .lineSynced }
        return .unsynced
    }

    public var hasDuets: Bool {
        lines.contains { $0.speaker == .duet }
    }

    public var hasBackingVocals: Bool {
        lines.contains { ($0.backgroundText?.isEmpty == false) || !$0.backgroundWords.isEmpty }
    }

    public func withColors(_ newColors: LyricsColors?) -> Lyrics {
        guard let newColors, self.colors == nil else { return self }
        return Lyrics(
            lines: lines,
            synced: synced,
            wordSynced: wordSynced,
            provider: provider,
            colors: newColors,
            isRTL: isRTL,
            songwriters: songwriters,
            isLocalImport: isLocalImport
        )
    }

    public func shifted(by deltaMs: Int64) -> Lyrics {
        guard deltaMs != 0 else { return self }
        return Lyrics(
            lines: lines.map { $0.shifted(by: deltaMs) },
            synced: synced,
            wordSynced: wordSynced,
            provider: provider,
            colors: colors,
            isRTL: isRTL,
            songwriters: songwriters,
            isLocalImport: isLocalImport
        )
    }
}

// MARK: - Lyrics Track Lookup Query

public struct LyricsTrackQuery: Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let durationMs: Int64
    public let isrc: String?

    public init(
        id: String,
        title: String,
        artist: String,
        album: String = "",
        durationMs: Int64 = 0,
        isrc: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.isrc = isrc
    }
}

// MARK: - Genius Song Meanings & Line Referents

public struct GeniusReferentAnnotation: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let fragment: String
    public let normalizedFragment: String
    public let annotationText: String
    public var translatedText: String?
    public let votesTotal: Int
    public let verified: Bool

    public init(
        id: Int,
        fragment: String,
        normalizedFragment: String,
        annotationText: String,
        translatedText: String? = nil,
        votesTotal: Int = 0,
        verified: Bool = false
    ) {
        self.id = id
        self.fragment = fragment
        self.normalizedFragment = normalizedFragment
        self.annotationText = annotationText
        self.translatedText = translatedText
        self.votesTotal = votesTotal
        self.verified = verified
    }
}

public struct GeniusSongMeaning: Codable, Sendable, Hashable {
    public let songID: Int
    public let title: String
    public let artist: String
    public let url: String?
    public let summary: String?
    public var translatedSummary: String?
    public let annotations: [GeniusReferentAnnotation]

    public init(
        songID: Int,
        title: String,
        artist: String,
        url: String? = nil,
        summary: String? = nil,
        translatedSummary: String? = nil,
        annotations: [GeniusReferentAnnotation] = []
    ) {
        self.songID = songID
        self.title = title
        self.artist = artist
        self.url = url
        self.summary = summary
        self.translatedSummary = translatedSummary
        self.annotations = annotations
    }
}

// MARK: - Lyrics Display Styles

public enum SpicyStageStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case celestify = "Celestify"
    case spicy = "Spicy"
    case apple = "Apple"
    case refreshed = "Refreshed"
    case simple = "Simple"
    case minimal = "Minimal"

    public var id: String { rawValue }
}

public enum SpicyStageBackground: String, Codable, Sendable, CaseIterable, Identifiable {
    case dynamicMesh = "Dynamic"
    case coverBlur = "Cover"
    case artistHeader = "Artist"
    case solidColor = "Color"
    case none = "None"

    public var id: String { rawValue }
}
