//
//  KrcParser.swift
//  Celestify
//
//  Kugou KRC word-by-word karaoke binary decryptor (4-byte "krc1" header + 16-byte XOR key
//  + zlib decompression) and line/syllable timing parser.
//  Ported from Myspoti (LyricsApi.kt). Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Compression
import Foundation

public enum KrcParser {
    public static let xorKey: [UInt8] = [
        64, 71, 97, 119, 94, 50, 116, 71,
        81, 54, 49, 45, 206, 210, 110, 105
    ]

    private static let lineRegex = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\](.*)$"#)
    private static let wordRegex = try! NSRegularExpression(pattern: #"<(\d+),(\d+),\d+>([^<]*)"#)

    /// Decrypts Base64-encoded Kugou KRC data into UTF-8 text.
    public static func decryptBase64(_ base64Content: String) -> String? {
        let cleaned = base64Content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawData = Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        return decrypt(data: rawData)
    }

    /// Decrypts raw KRC binary payload (`krc1` + XOR + zlib stream).
    public static func decrypt(data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return nil }
        // Verify "krc1" magic header when present
        let magic = String(bytes: bytes[0..<4], encoding: .ascii)
        guard magic == "krc1" else { return nil }

        var xored = [UInt8](repeating: 0, count: bytes.count - 4)
        for i in 0..<xored.count {
            xored[i] = bytes[i + 4] ^ xorKey[i % xorKey.count]
        }

        guard let inflated = zlibInflate(xored) else { return nil }
        return String(data: inflated, encoding: .utf8)
    }

    /// Parses decoded KRC plain text (`[lineStart,lineDur]<wordOffset,wordDur,0>word...`) into `LyricLine`s.
    public static func parseDecodedText(_ krcText: String) -> [LyricLine] {
        let normalized = krcText
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var output: [LyricLine] = []
        for raw in normalized.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = lineRegex.firstMatch(in: trimmed, range: range),
                  let startR = Range(match.range(at: 1), in: trimmed),
                  let durR = Range(match.range(at: 2), in: trimmed),
                  let bodyR = Range(match.range(at: 3), in: trimmed),
                  let lineStart = Int64(trimmed[startR]),
                  let lineDur = Int64(trimmed[durR]) else {
                continue
            }

            let body = String(trimmed[bodyR])
            let bodyRange = NSRange(body.startIndex..<body.endIndex, in: body)
            let wordMatches = wordRegex.matches(in: body, range: bodyRange)

            var words: [LyricWord] = []
            var fullLineBuilder = ""

            for (idx, wMatch) in wordMatches.enumerated() {
                guard let offR = Range(wMatch.range(at: 1), in: body),
                      let wDurR = Range(wMatch.range(at: 2), in: body),
                      let txtR = Range(wMatch.range(at: 3), in: body),
                      let offsetMs = Int64(body[offR]),
                      let wordDurMs = Int64(body[wDurR]) else { continue }

                let rawToken = String(body[txtR])
                fullLineBuilder += rawToken
                let hasTrailingSpace = rawToken.hasSuffix(" ")
                let cleanToken = rawToken.trimmingCharacters(in: .whitespaces)
                guard !cleanToken.isEmpty else { continue }

                let wStart = lineStart + offsetMs
                let wEnd = wStart + max(0, wordDurMs)
                let isPartOfWord = !hasTrailingSpace && (idx + 1 < wordMatches.count)
                words.append(LyricWord(text: cleanToken, startMs: wStart, endMs: wEnd, isPartOfWord: isPartOfWord))
            }

            let text = fullLineBuilder.trimmingCharacters(in: .whitespaces)
            // Filter Kugou metadata credit headers ("作词：...", "作曲：...", "编曲：...")
            if text.isEmpty || text.contains("：") { continue }

            output.append(
                LyricLine(
                    startMs: lineStart,
                    endMs: lineStart + max(0, lineDur),
                    words: text,
                    speaker: .main,
                    wordTimings: words
                )
            )
        }
        return output
    }

    // MARK: - Native Compression Zlib Inflate

    private static func zlibInflate(_ input: [UInt8]) -> Data? {
        guard !input.isEmpty else { return nil }
        // Strip 2-byte RFC 1950 zlib header if present (0x78 0x01 / 0x78 0x9C / 0x78 0xDA) for raw DEFLATE
        let payload: [UInt8]
        if input.count > 6 && input[0] == 0x78 && ((UInt16(input[0]) * 256 + UInt16(input[1])) % 31 == 0) {
            payload = Array(input[2..<(input.count - 4)])
        } else {
            payload = input
        }

        var capacity = max(payload.count * 6, 16_384)
        for _ in 0..<4 {
            var destination = [UInt8](repeating: 0, count: capacity)
            let decodedBytes = payload.withUnsafeBufferPointer { srcPtr -> Int in
                guard let base = srcPtr.baseAddress else { return 0 }
                return compression_decode_buffer(
                    &destination,
                    capacity,
                    base,
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            if decodedBytes > 0 && decodedBytes < capacity {
                return Data(destination.prefix(decodedBytes))
            }
            capacity *= 4
        }
        return nil
    }
}
