//
//  Romanizer.swift
//  Celestify
//
//  Multi-script lyric romanizer supporting Korean Hangul (Revised Romanization),
//  Japanese Hiragana/Katakana (Hepburn with sokuon & digraphs), Cyrillic, and
//  Apple CoreFoundation ICU transliteration for Hanzi/Pinyin, Arabic, Thai, Greek, and Devanagari.
//  Adapted from Spicy Lyrics Mobile (Romanizer.kt), AGPL-3.0. See THIRD_PARTY_NOTICES.md.
//

import CoreFoundation
import Foundation

public enum Romanizer {
    // Korean Hangul Jamo tables (Revised Romanization of Korean)
    private static let hangulInitials = [
        "g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s",
        "ss", "", "j", "jj", "ch", "k", "t", "p", "h"
    ]
    private static let hangulMedials = [
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa",
        "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"
    ]
    private static let hangulFinals = [
        "", "k", "k", "k", "n", "n", "n", "t", "l", "k",
        "m", "p", "l", "t", "p", "l", "m", "p", "p", "t",
        "t", "ng", "t", "t", "k", "t", "p", "t"
    ]

    // Japanese Kana -> Hepburn Romaji table
    private static let kanaDigraphs: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "じゃ": "ja",  "じゅ": "ju",  "じょ": "jo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "キャ": "kya", "キュ": "kyu", "キョ": "kyo",
        "シャ": "sha", "シュ": "shu", "ショ": "sho",
        "チャ": "cha", "チュ": "chu", "チョ": "cho",
        "ニャ": "nya", "ニュ": "nyu", "ニョ": "nyo",
        "ヒャ": "hya", "ヒュ": "hyu", "ヒョ": "hyo",
        "ミャ": "mya", "ミュ": "myu", "ミョ": "myo",
        "リャ": "rya", "リュ": "ryu", "リョ": "ryo",
        "ギャ": "gya", "ギュ": "gyu", "ギョ": "gyo",
        "ジャ": "ja",  "ジュ": "ju",  "ジョ": "jo",
        "ビャ": "bya", "ビュ": "byu", "ビョ": "byo",
        "ピャ": "pya", "ピュ": "pyu", "ピョ": "pyo",
        "ファ": "fa",  "フィ": "fi",  "フェ": "fe", "フォ": "fo",
        "ティ": "ti",  "ディ": "di",  "トゥ": "tu", "ドゥ": "du"
    ]

    private static let kanaMonographs: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "o", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ア": "a", "イ": "i", "ウ": "u", "エ": "e", "オ": "o",
        "カ": "ka", "キ": "ki", "ク": "ku", "ケ": "ke", "コ": "ko",
        "サ": "sa", "シ": "shi", "ス": "su", "セ": "se", "ソ": "so",
        "タ": "ta", "チ": "chi", "ツ": "tsu", "テ": "te", "ト": "to",
        "ナ": "na", "ニ": "ni", "ヌ": "nu", "ネ": "ne", "ノ": "no",
        "ハ": "ha", "ヒ": "hi", "フ": "fu", "ヘ": "he", "ホ": "ho",
        "マ": "ma", "ミ": "mi", "ム": "mu", "メ": "me", "モ": "mo",
        "ヤ": "ya", "ユ": "yu", "ヨ": "yo",
        "ラ": "ra", "リ": "ri", "ル": "ru", "レ": "re", "ロ": "ro",
        "ワ": "wa", "ヲ": "o", "ン": "n",
        "ガ": "ga", "ギ": "gi", "グ": "gu", "ゲ": "ge", "ゴ": "go",
        "ザ": "za", "ジ": "ji", "ズ": "zu", "ゼ": "ze", "ゾ": "zo",
        "ダ": "da", "ヂ": "ji", "ヅ": "zu", "デ": "de", "ド": "do",
        "バ": "ba", "ビ": "bi", "ブ": "bu", "ベ": "be", "ボ": "bo",
        "パ": "pa", "ピ": "pi", "プ": "pu", "ペ": "pe", "ポ": "po",
        "ー": "-"
    ]

    private static let cyrillicMap: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
        "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
        "і": "i", "ї": "yi", "є": "ye", "ґ": "g"
    ]

    /// Returns `true` if `text` contains non-Latin script characters that benefit from romanization.
    public static func needsRomanization(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // Hangul, Hiragana, Katakana, CJK Unified Ideographs, Cyrillic, Arabic, Hebrew, Thai, Devanagari, Greek
            if (0xAC00...0xD7A3).contains(v)
                || (0x3040...0x30FF).contains(v)
                || (0x4E00...0x9FFF).contains(v)
                || (0x0400...0x04FF).contains(v)
                || (0x0590...0x06FF).contains(v)
                || (0x0E00...0x0E7F).contains(v)
                || (0x0900...0x097F).contains(v)
                || (0x0370...0x03FF).contains(v) {
                return true
            }
        }
        return false
    }

    /// Romanizes a single lyric line if it contains non-Latin characters; returns `nil` when already Latin.
    public static func romanize(_ text: String) -> String? {
        guard needsRomanization(text) else { return nil }

        // If pure Hangul/Kana/Cyrillic without Kanji/Hanzi, use deterministic phonetic rules first
        let hasCJKUnified = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        if !hasCJKUnified {
            let deterministic = romanizeDeterministic(text)
            if !needsRomanization(deterministic) {
                let cleaned = deterministic
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty || cleaned == text ? nil : cleaned
            }
        }

        // Apple ICU transliteration handles CJK Hanzi/Kanji, Thai, Arabic, Greek, Hebrew, Devanagari
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        let transformed = (mutable as String)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (transformed.isEmpty || transformed == text) ? nil : transformed
    }

    /// Annotates all lines in `lyrics` that lack TTML `romanized` text.
    public static func applyRomanization(to lyrics: Lyrics) -> Lyrics {
        let updated = lyrics.lines.map { line -> LyricLine in
            if line.romanized != nil || line.isInstrumental { return line }
            return line.withAnnotations(romanized: romanize(line.words))
        }
        return Lyrics(
            lines: updated,
            synced: lyrics.synced,
            wordSynced: lyrics.wordSynced,
            provider: lyrics.provider,
            colors: lyrics.colors,
            isRTL: lyrics.isRTL,
            songwriters: lyrics.songwriters,
            isLocalImport: lyrics.isLocalImport
        )
    }

    private static func romanizeDeterministic(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var i = 0
        var geminateNext = false

        while i < chars.count {
            let ch = chars[i]

            // Japanese Sokuon (っ / ッ) doubles the next consonant
            if ch == "っ" || ch == "ッ" {
                geminateNext = true
                i += 1
                continue
            }

            // Japanese 2-char digraphs
            if i + 1 < chars.count {
                let pair = String([ch, chars[i + 1]])
                if let roma = kanaDigraphs[pair] {
                    if geminateNext, let firstConsonant = roma.first {
                        out.append(firstConsonant)
                        geminateNext = false
                    }
                    out += roma
                    i += 2
                    continue
                }
            }

            // Japanese monographs
            if let roma = kanaMonographs[ch] {
                if geminateNext, let firstConsonant = roma.first, !"aeiou-".contains(firstConsonant) {
                    out.append(firstConsonant)
                }
                geminateNext = false
                out += roma
                i += 1
                continue
            }

            geminateNext = false

            // Korean Hangul syllable block (U+AC00..U+D7A3)
            if let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1,
               (0xAC00...0xD7A3).contains(scalar.value) {
                let offset = Int(scalar.value - 0xAC00)
                let initialIdx = offset / (21 * 28)
                let medialIdx = (offset % (21 * 28)) / 28
                let finalIdx = offset % 28
                out += hangulInitials[initialIdx] + hangulMedials[medialIdx] + hangulFinals[finalIdx]
                i += 1
                continue
            }

            // Cyrillic
            let lower = Character(ch.lowercased())
            if let cyr = cyrillicMap[lower] {
                if ch.isUppercase, let first = cyr.first {
                    out += String(first).uppercased() + cyr.dropFirst()
                } else {
                    out += cyr
                }
                i += 1
                continue
            }

            out.append(ch)
            i += 1
        }
        return out
    }
}
