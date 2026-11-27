//
//  AuthNetworkingAndSecurityTests.swift
//  CelestifyTests
//
//  XCTest suite covering Base62->Hex GID, JSONPath, Keychain multi-account store,
//  Spotify magic-link normalization, AES-256-CTR OfflineCrypto, Spicetify/Glassify
//  Theme Converter, ListenHistory recap, and DiagnosticLogbook redaction.
//

import XCTest
@testable import Celestify

final class AuthNetworkingAndSecurityTests: XCTestCase {

    func testSpotifyBase62ToHex32Conversion() {
        let hex = SpotifyBase62.toHex32("4cOdK2wGLETKBW3PvgPWqT")
        XCTAssertNotNil(hex)
        XCTAssertEqual(hex?.count, 32)
        XCTAssertNil(SpotifyBase62.toHex32("invalid!id"))
    }

    func testJSONValueDottedAndIndexedPathLookup() {
        let raw = #"{"data":{"trackUnion":{"name":"Starboy","artists":{"items":[{"profile":{"name":"The Weeknd"}}]}}}}"#
        let json = JSONValue.parse(raw)
        XCTAssertEqual(json?.str("data.trackUnion.name"), "Starboy")
        XCTAssertEqual(json?.str("data.trackUnion.artists.items[0].profile.name"), "The Weeknd")
    }

    @MainActor
    func testWebPlayerPlayArgumentsSelectTheTappedTrackAndPreserveOrder() {
        let args = PlayerController.webPlayerPlayArguments(
            trackURI: "spotify:track:selected",
            contextURI: "",
            orderedTrackURIs: ["spotify:track:first", "spotify:track:selected"]
        )
        XCTAssertEqual(args["contextUri"], .string("spotify:track:selected"))
        XCTAssertEqual(args["trackUri"], .string("spotify:track:selected"))
        XCTAssertEqual(args["order"], .array([
            .string("spotify:track:first"),
            .string("spotify:track:selected")
        ]))
    }

    @MainActor
    func testWebPlayerPlayArgumentsUseTrackAsStandaloneContext() {
        let args = PlayerController.webPlayerPlayArguments(
            trackURI: "spotify:track:selected",
            contextURI: "",
            orderedTrackURIs: []
        )
        XCTAssertEqual(args["contextUri"], .string("spotify:track:selected"))
        XCTAssertEqual(args["trackUri"], .string("spotify:track:selected"))
        XCTAssertNil(args["order"])
    }

    @MainActor
    func testWebPlayerPlayArgumentsKeepNativePlaylistContext() {
        let args = PlayerController.webPlayerPlayArguments(
            trackURI: "spotify:track:selected",
            contextURI: "spotify:playlist:context",
            orderedTrackURIs: ["spotify:track:first", "spotify:track:selected"]
        )
        XCTAssertEqual(args["contextUri"], .string("spotify:playlist:context"))
        XCTAssertEqual(args["trackUri"], .string("spotify:track:selected"))
        XCTAssertNil(args["order"])
    }

    @MainActor
    func testMagicLinkNormalizationAndMultiAccountKeychain() async throws {
        let keychain = KeychainStore(service: "app.celestify.tests.\(UUID().uuidString)", inMemoryForTesting: true)
        let auth = SpotifyAuthManager(keychain: keychain)

        let validURL = auth.normalizeMagicLink("https://accounts.spotify.com/en/login/magic-link?token=abc")
        XCTAssertNotNil(validURL)
        let evilURL = auth.normalizeMagicLink("https://evil-phishing.example.com/login")
        XCTAssertNil(evilURL)

        let acc1 = StoredAccountSession(
            id: "acc-1",
            displayName: "Listener One",
            cookies: [StoredSessionCookie(name: "sp_dc", value: "token_one", domain: ".spotify.com")]
        )
        let acc2 = StoredAccountSession(
            id: "acc-2",
            displayName: "Listener Two",
            cookies: [StoredSessionCookie(name: "sp_dc", value: "token_two", domain: ".spotify.com")]
        )
        try await keychain.saveAccount(acc1, makeActive: true)
        try await keychain.saveAccount(acc2, makeActive: false)

        let activeBefore = await keychain.activeAccount()
        XCTAssertEqual(activeBefore?.id, "acc-1")

        try await keychain.saveAccount(acc2, makeActive: true)
        let activeAfter = await keychain.activeAccount()
        XCTAssertEqual(activeAfter?.id, "acc-2")
    }

    func testOfflineCryptoSeekableAES256CTRRoundTrip() throws {
        var keyBytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { keyBytes[i] = UInt8(i * 7 & 0xFF) }
        let masterKey = Data(keyBytes)

        let originalString = String(repeating: "CelestifySeekableAudioFrame0123456789", count: 80)
        let plaintext = Data(originalString.utf8)

        let encrypted = try OfflineCrypto.encryptData(plaintext, masterKey: masterKey)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).mse1")
        try encrypted.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        XCTAssertTrue(OfflineCrypto.isEncryptedFile(at: tempURL))
        XCTAssertEqual(OfflineCrypto.plaintextLength(ofEncryptedFile: tempURL), Int64(plaintext.count))

        // Decrypt arbitrary mid-file unaligned byte slice [offset: 137, length: 519]
        let slice = try OfflineCrypto.decryptSlice(
            fromEncryptedFile: tempURL,
            streamOffset: 137,
            length: 519,
            masterKey: masterKey
        )
        XCTAssertEqual(slice, plaintext.subdata(in: 137..<(137 + 519)))
    }

    func testSpicetifyThemeParserAndGlassifyAdapterContrastSafety() throws {
        let ini = """
        [RosePine]
        main = #191724
        sidebar = #1f1d2e
        card = #26233a
        text = #e0def4
        subtext = #908caa
        button = #ebbcba
        """
        let converted = try SpicetifyThemeParser.parse(ini: ini, css: nil)
        XCTAssertNotNil(converted.schemes["RosePine"])
        if let colors = converted.schemes["RosePine"] {
            XCTAssertGreaterThanOrEqual(SpicetifyThemeParser.contrastRatio(colors.text, colors.background), 4.5)
        }

        let adapted = try GlassifyAdapter.adapt(
            repository: "sanoojes/spicetify-glassify",
            manifest: JSONValue.parse(#"{"name":"Glassify"}"#),
            converted: ConvertedTheme(schemes: [:], compatibility: .partial)
        )
        XCTAssertEqual(adapted.effects, .glassify)
        XCTAssertFalse(adapted.schemes.isEmpty)
    }

    func testListenHistoryThresholdAndRecapAggregation() {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let store = ListenHistoryStore(customFileURL: tempFile)
        // < 30s play must be ignored
        store.record(ListenRecord(key: "spotify:track:short", title: "Too Short", artist: "Artist A", album: "Album A", coverURL: "", playedMs: 12_000, source: .spotify))
        // >= 30s plays recorded
        store.record(ListenRecord(key: "spotify:track:1", title: "Celestial", artist: "Artist A", album: "Album A", coverURL: "", playedMs: 180_000, source: .spotify))
        store.record(ListenRecord(key: "spotify:track:1", title: "Celestial", artist: "Artist A", album: "Album A", coverURL: "", playedMs: 180_000, source: .download))

        let recap = store.recap()
        XCTAssertEqual(recap.totalListens, 2)
        XCTAssertEqual(recap.totalMinutes, 6)
        XCTAssertEqual(recap.topTracks.first?.name, "Celestial")
        XCTAssertEqual(recap.topTracks.first?.playCount, 2)
    }

    func testDiagnosticLogbookRedactsSecrets() {
        let raw = "Header Authorization: Bearer BQD1234567890abcdef Cookie sp_dc=AQB_super_secret_cookie_value"
        let scrubbed = DiagnosticLogbook.redact(raw)
        XCTAssertFalse(scrubbed.contains("BQD1234567890abcdef"))
        XCTAssertFalse(scrubbed.contains("AQB_super_secret_cookie_value"))
        XCTAssertTrue(scrubbed.contains("[REDACTED]"))
    }
}
