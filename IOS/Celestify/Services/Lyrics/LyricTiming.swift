//
//  LyricTiming.swift
//  Celestify
//
//  Binary-search active line & active syllable/word lookup, continuous word sweep
//  progress, simultaneous duet range detection, instrumental interlude progress,
//  RTL script detection, and Spotify audio intro alignment.
//  Ported from Myspoti (LyricTiming.kt & LyricsApi.alignTo).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public struct InterludeState: Sendable, Equatable {
    public let startMs: Int64
    public let endMs: Int64
    public let progress: Double

    public var remainingMs: Int64 {
        max(0, endMs - startMs - Int64(Double(endMs - startMs) * progress))
    }
}

public enum LyricTiming {
    /// Minimum instrumental gap duration (3.0s) before rendering the 3-dot interlude indicator.
    public static let minInterludeDurationMs: Int64 = 3_000

    /// Computes effective lyric position in milliseconds, compensating for audio route lag and user offset.
    /// Matches `LyricTiming.position(playbackMs, outputLagMs, offsetMs)`.
    public static func effectivePositionMs(
        playbackMs: Int64,
        outputLagMs: Int64 = 0,
        userOffsetMs: Int = 0
    ) -> Int64 {
        max(0, playbackMs - outputLagMs - Int64(userOffsetMs))
    }

    /// Binary search for the latest lyric line whose `startMs <= positionMs` (`-1` before the first line).
    public static func activeLineIndex(in lines: [LyricLine], at positionMs: Int64) -> Int {
        guard !lines.isEmpty else { return -1 }
        var low = 0
        var high = lines.count - 1
        var result = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].startMs <= positionMs {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        // If the matched line has an explicit endMs well in the past and the next line hasn't started yet,
        // check whether we are inside a long instrumental gap (>3s)
        if result >= 0,
           let endMs = lines[result].endMs,
           positionMs > endMs + 400,
           result + 1 < lines.count,
           lines[result + 1].startMs - endMs >= minInterludeDurationMs {
            return result
        }
        return result
    }

    /// Returns all simultaneously active line indices at `positionMs` (e.g., overlapping lead + duet lines).
    public static func activeLineIndices(in lines: [LyricLine], at positionMs: Int64) -> Range<Int>? {
        let primary = activeLineIndex(in: lines, at: positionMs)
        guard primary >= 0 else { return nil }
        var first = primary
        while first > 0 {
            let prev = lines[first - 1]
            let prevEnd = prev.endMs ?? lines[first].startMs
            if prev.startMs <= positionMs && prevEnd > positionMs && abs(prev.startMs - lines[primary].startMs) <= 1_500 {
                first -= 1
            } else {
                break
            }
        }
        var last = primary
        while last + 1 < lines.count {
            let next = lines[last + 1]
            if next.startMs <= positionMs {
                last += 1
            } else {
                break
            }
        }
        return first..<(last + 1)
    }

    /// Binary search for the active word/syllable inside `words` at `positionMs`.
    public static func activeWordIndex(in words: [LyricWord], at positionMs: Int64) -> Int {
        guard !words.isEmpty else { return -1 }
        var low = 0
        var high = words.count - 1
        var answer = -1
        while low <= high {
            let mid = (low + high) / 2
            if words[mid].startMs <= positionMs {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    /// Computes `[0.0, 1.0]` sweep progress for a single `LyricWord` at `positionMs`.
    public static func wordSweepProgress(_ word: LyricWord, nextWordStartMs: Int64?, lineEndMs: Int64?, at positionMs: Int64) -> Double {
        if positionMs <= word.startMs { return 0.0 }
        let rawEnd: Int64 = {
            if word.endMs > word.startMs { return word.endMs }
            if let nextWordStartMs, nextWordStartMs > word.startMs { return nextWordStartMs }
            if let lineEndMs, lineEndMs > word.startMs { return lineEndMs }
            return word.startMs + 280
        }()
        if positionMs >= rawEnd { return 1.0 }
        return Double(positionMs - word.startMs) / Double(max(1, rawEnd - word.startMs))
    }

    /// Detects whether playback is currently inside an intro or instrumental interlude (`>= 3s`)
    /// so the 3-dot breathing countdown indicator can be rendered.
    public static func interludeState(in lines: [LyricLine], at positionMs: Int64) -> InterludeState? {
        guard let first = lines.first else { return nil }
        // Intro before the first sung line
        if positionMs < first.startMs && first.startMs >= minInterludeDurationMs {
            let p = Double(max(0, positionMs)) / Double(first.startMs)
            return InterludeState(startMs: 0, endMs: first.startMs, progress: min(max(p, 0.0), 1.0))
        }

        let idx = activeLineIndex(in: lines, at: positionMs)
        guard idx >= 0 else { return nil }
        let current = lines[idx]

        // Explicit "♪" instrumental marker line
        if current.isInstrumental, idx + 1 < lines.count {
            let end = lines[idx + 1].startMs
            let span = end - current.startMs
            if span >= minInterludeDurationMs && positionMs < end {
                let p = Double(positionMs - current.startMs) / Double(span)
                return InterludeState(startMs: current.startMs, endMs: end, progress: min(max(p, 0.0), 1.0))
            }
        }

        // Gap between current line's endMs and next line's startMs
        if let lineEnd = current.endMs,
           idx + 1 < lines.count {
            let nextStart = lines[idx + 1].startMs
            let gap = nextStart - lineEnd
            if gap >= minInterludeDurationMs && positionMs >= lineEnd && positionMs < nextStart {
                let p = Double(positionMs - lineEnd) / Double(gap)
                return InterludeState(startMs: lineEnd, endMs: nextStart, progress: min(max(p, 0.0), 1.0))
            }
        }
        return nil
    }

    /// Detects Right-to-Left scripts (Arabic, Hebrew, Syriac, Thaana, N'Ko).
    public static func containsRTLCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) {
                return true
            }
        }
        return false
    }

    // MARK: - Third-Party Word Timing Alignment to Spotify Audio Cut

    /// Aligns word-synced third-party lyrics (LyricsPlus / lrc.red / Kugou) to Spotify's line timestamps
    /// using the median timestamp delta across `>= 3` matching lines when `abs(median) >= 60ms`.
    public static func alignToSpotifyAudio(_ candidate: Lyrics, spotifyReference: Lyrics?) -> Lyrics {
        guard let sp = spotifyReference, sp.synced else { return candidate }
        let spLines = sp.lines.filter { $0.startMs > 0 && normalizedMatchKey($0.words).count >= 6 }
        guard spLines.count >= 3 else { return candidate }

        var deltas: [Int64] = []
        var searchFrom = 0
        for line in candidate.lines {
            let key = normalizedMatchKey(line.words)
            guard key.count >= 6 else { continue }
            if let matchIdx = (searchFrom..<spLines.count).first(where: { normalizedMatchKey(spLines[$0].words) == key }) {
                deltas.append(spLines[matchIdx].startMs - line.startMs)
                searchFrom = matchIdx + 1
            }
        }

        guard deltas.count >= 3 else { return candidate }
        let sorted = deltas.sorted()
        let medianShift = sorted[sorted.count / 2]
        guard abs(medianShift) >= 60 else { return candidate }

        DiagnosticLogbook.shared.log("lyrics", "Aligned \(candidate.provider) by \(medianShift)ms across \(deltas.count) lines to Spotify audio")
        return candidate.shifted(by: medianShift)
    }

    public static func normalizedMatchKey(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
