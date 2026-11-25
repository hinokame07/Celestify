//
//  LyricsAndParsersTests.swift
//  CelestifyTests
//
//  Comprehensive XCTest suite covering LRC/ELRC, Kugou KRC, Apple Music/Spicy TTML,
//  LyricTiming binary search & median intro alignment, LyricClock smoothstep,
//  and Hangul/Kana/Cyrillic Romanizer.
//

import XCTest
@testable import Celestify

final class LyricsAndParsersTests: XCTestCase {

    func testLrcParserSupportsOffsetMultiTimestampsAndELRCWords() {
        let sample = """
        [offset:100]
        [00:10.00][00:30.00]Chorus line
        [00:15.50]<00:15.50>Star<00:15.80>light <00:16.20>shines
        """
        guard let doc = LrcParser.parse(sample, provider: "LRCLIB") else {
            XCTFail("Expected non-nil parsed LRC document")
            return
        }
        XCTAssertTrue(doc.synced)
        XCTAssertTrue(doc.wordSynced)
        XCTAssertEqual(doc.lines.count, 3)

        // [00:10.00] minus [offset:100] => 9_900ms
        XCTAssertEqual(doc.lines[0].startMs, 9_900)
        XCTAssertEqual(doc.lines[0].words, "Chorus line")

        // ELRC word-synced line at 15_400ms
        XCTAssertEqual(doc.lines[1].startMs, 15_400)
        XCTAssertEqual(doc.lines[1].wordTimings.count, 3)
        XCTAssertEqual(doc.lines[1].wordTimings[0].text, "Star")
        XCTAssertTrue(doc.lines[1].wordTimings[0].isPartOfWord)

        // Repeated chorus timestamp [00:30.00] minus 100ms => 29_900ms
        XCTAssertEqual(doc.lines[2].startMs, 29_900)
    }

    func testKrcParserDecodesSyllableTimingsAndFiltersCreditLines() {
        let decodedKRC = """
        [0,1000]<0,1000,0>作词：方文山
        [4000,2500]<0,500,0>Star<500,700,0>light <1200,1300,0>glows
        """
        let lines = KrcParser.parseDecodedText(decodedKRC)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].startMs, 4_000)
        XCTAssertEqual(lines[0].endMs, 6_500)
        XCTAssertEqual(lines[0].words, "Starlight glows")
        XCTAssertEqual(lines[0].wordTimings.count, 3)
        XCTAssertTrue(lines[0].wordTimings[0].isPartOfWord)
        XCTAssertFalse(lines[0].wordTimings[1].isPartOfWord)
    }

    func testTtmlParserExtractsSyllablesDuetsBackingVocalsAndMetadata() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"
            xmlns:itunes="http://music.apple.com/lyric-ttml-internal"
            xmlns:ttm="http://www.w3.org/ns/ttml#metadata"
            itunes:timing="Word">
          <head>
            <metadata>
              <ttm:agent type="person" xml:id="v1"/>
              <ttm:agent type="person" xml:id="v2"/>
              <iTunesMetadata>
                <songwriters>
                  <songwriter>Elena Vance</songwriter>
                </songwriters>
              </iTunesMetadata>
            </metadata>
          </head>
          <body>
            <div>
              <p begin="00:04.000" end="00:06.500" ttm:agent="v1">
                <span begin="00:04.000" end="00:04.600">Mid</span><span begin="00:04.600" end="00:05.200">night</span>
                <span begin="00:05.300" end="00:06.500">sky</span>
                <span ttm:role="x-bg" begin="00:05.800" end="00:06.500">(echoes)</span>
                <span ttm:role="x-translation">Ciel de minuit</span>
              </p>
              <p begin="00:07.000" end="00:09.000" ttm:agent="v2">
                <span begin="00:07.000" end="00:09.000">Answer back</span>
              </p>
            </div>
          </body>
        </tt>
        """
        guard let doc = TtmlLyricsParser.parse(xml) else {
            XCTFail("Expected non-nil parsed TTML document")
            return
        }
        XCTAssertTrue(doc.synced)
        XCTAssertTrue(doc.wordSynced)
        XCTAssertEqual(doc.songwriters, ["Elena Vance"])
        XCTAssertEqual(doc.lines.count, 2)

        let first = doc.lines[0]
        XCTAssertEqual(first.speaker, .main)
        XCTAssertTrue(first.wordTimings[0].isPartOfWord) // "Mid" + "night" without whitespace
        XCTAssertFalse(first.wordTimings[1].isPartOfWord) // space before "sky"
        XCTAssertEqual(first.backgroundText, "echoes")
        XCTAssertEqual(first.translation, "Ciel de minuit")

        let second = doc.lines[1]
        XCTAssertEqual(second.speaker, .duet) // v2 secondary vocalist
    }

    func testTtmlParserRejectsXXEDoctype() {
        let malicious = """
        <!DOCTYPE foo [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
        <tt><p>&xxe;</p></tt>
        """
        XCTAssertNil(TtmlLyricsParser.parse(malicious))
    }

    func testLyricTimingBinarySearchAndAudioIntroAlignment() {
        let external = Lyrics(
            lines: [
                LyricLine(
                    startMs: 12_000,
                    endMs: 14_000,
                    words: "Hello world from beyond",
                    wordTimings: [LyricWord(text: "Hello", startMs: 12_000, endMs: 13_000)]
                ),
                LyricLine(startMs: 15_000, endMs: 17_000, words: "Second verse begins tonight"),
                LyricLine(startMs: 19_000, endMs: 21_000, words: "Third verse carries home")
            ],
            synced: true,
            wordSynced: true,
            provider: "Spicy"
        )
        // Spotify audio starts 2,000ms earlier (radio edit vs music video cut)
        let spotifyRef = Lyrics(
            lines: [
                LyricLine(startMs: 10_000, words: "Hello world from beyond"),
                LyricLine(startMs: 13_000, words: "Second verse begins tonight"),
                LyricLine(startMs: 17_000, words: "Third verse carries home")
            ],
            synced: true,
            provider: "Spotify"
        )

        let aligned = LyricTiming.alignToSpotifyAudio(external, spotifyReference: spotifyRef)
        XCTAssertEqual(aligned.lines[0].startMs, 10_000)
        XCTAssertEqual(aligned.lines[0].wordTimings[0].startMs, 10_000)
        XCTAssertEqual(LyricTiming.activeLineIndex(in: aligned.lines, at: 13_500), 1)
    }

    func testLyricClockMonotonicAdvanceAndDiscontinuityGlide() {
        let clock = LyricClock()
        let p0 = clock.frame(nowMs: 1_000.0, reportedMs: 5_000, sampledAtMs: 1_000.0, discontinuity: 0)
        XCTAssertEqual(p0, 5_000)

        // 100ms later at 60fps -> advances smoothly to ~5100ms
        let p1 = clock.frame(nowMs: 1_100.0, reportedMs: 5_100, sampledAtMs: 1_100.0, discontinuity: 0)
        XCTAssertEqual(p1, 5_100)

        // User seeks backward to 1_000ms with discontinuity increment -> starts smoothstep glide
        let pSeek = clock.frame(nowMs: 1_120.0, reportedMs: 1_000, sampledAtMs: 1_120.0, discontinuity: 1)
        XCTAssertLessThanOrEqual(pSeek, 5_100)
    }

    func testRomanizerHangulKanaAndCyrillic() {
        XCTAssertNotNil(Romanizer.romanizeLine("봄날"))
        XCTAssertEqual(Romanizer.romanizeLine("さくら"), "sakura")
        XCTAssertEqual(Romanizer.romanizeLine("Привет"), "Privet")
        XCTAssertNil(Romanizer.romanizeLine("Already Pure English"))
    }
}
