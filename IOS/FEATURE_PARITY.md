# Android → iOS Feature Parity & Auth Remediation Matrix

This document maps every module and user-facing capability from the Android codebase (`/base`) to its native Swift/SwiftUI counterpart in `/IOS`, and documents the authentication bugs diagnosed in Android and resolved in iOS.

---

## 1. Diagnosed Android Authentication Issues & iOS Architectural Fixes

| Issue Diagnosed in Android (`/base/host-android` & `/base/app`) | Root Cause | Native iOS Resolution (`/IOS`) |
|---|---|---|
| **Google / Apple OAuth & CAPTCHA blocks during WebView sign-in** | `Fingerprint.kt` overrides the login WebView User-Agent to desktop `X11; Linux x86_64 Chrome/134` while running on a mobile WebView without `onCreateWindow` popup handling. | `SpotifyLoginWebView.swift` uses a coherent mobile iOS Safari User-Agent, isolates login in a clean non-persistent `WKWebsiteDataStore` until `sp_dc` is captured, and implements `WKUIDelegate.createWebViewWith` so OAuth / 2FA / Turnstile popup windows complete seamlessly. |
| **Email one-time code / authenticator switch resets login screen** | `MainActivity.onResume` re-evaluates login state when returning from Mail/Authenticator, tearing down the half-completed login flow. | `SpotifyLoginSheetContainer` preserves the live `WKWebView` across `.background` / `.inactive` `ScenePhase` transitions and observes `WKHTTPCookieStoreObserver` asynchronously without reloading `accounts.spotify.com`. |
| **Concurrent 401 responses trigger duplicate token fetches or stale `client-token` headers** | Parallel startup requests (`home`, `libraryV3`, `profileAttributes`) can race on expired bearer tokens or mismatched `client-token` app versions. | `SpotifyTokenCoordinator.swift` is a Swift `actor` providing single-flight `Task` coalescing for both web `accessToken` and `clienttoken.spotify.com` tokens, proactive 60-second expiry margin refresh, `clientId`+`appVersion` cache validation, and automatic 1× 401 invalidation + retry. |
| **Network/carrier environments blocking embedded WebView login** | No manual credential import fallback when corporate/ISP proxies interfere with embedded login. | `OnboardingLoginView.swift` provides three sign-in paths: interactive WebKit login, manual `sp_dc` cookie import, and Spotify magic-link (`accounts.spotify.com` / `wl.spotify.com`) handling, all stored in hardware-encrypted **Apple Keychain** (`KeychainStore.swift`). |

---

## 2. Module & Capability Parity Matrix

| Capability / Subsystem | Android Source (`/base`) | iOS Native Implementation (`/IOS/Celestify`) | Status |
|---|---|---|---|
| **Domain Models** (`Track`, `Album`, `Artist`, `Playlist`, `Show`, `Episode`, `Jam`, `Credits`) | `:api/Models.kt`, `Media.kt` | `Models/DomainModels.swift` | Complete |
| **Web Player JS Bridge** (`PlayerAPI`, `PlaybackAPI`, `LibraryAPI`, `PlaylistAPI`, `Connect`, `Jam`) | `:api-spotify/resources/bridge/player-bridge.js`, `Bridge.kt` | `Resources/Spotify/player-bridge.js` (`WKScriptMessageHandler`), `Networking/SpotifyWebPlayerBridge.swift` | Complete |
| **Pathfinder v2 Persisted GraphQL + Live Hash Refresh** | `:api-spotify/gql/Gql.kt`, `GqlOpsUpdater.kt`, `gql-ops.json` | `Networking/SpotifyGraphQLClient.swift`, `Resources/Spotify/gql-ops.json` | Complete |
| **Spotify Catalog, Search, Home, Library, Blends, Recents, Friends, Credits, Canvas** | `SpotifyContent.kt`, `SpotifyLibrary.kt`, `SpotifyBlends.kt`, `SpotifyMore.kt`, `SpotifyRecents.kt` | `Networking/SpotifyAPIClient.swift`, `SpotifyMappers.swift`, `JSONPath.swift` | Complete |
| **Base62 → Hex GID & Protobuf Track Metadata (`ISRC`)** | `SpotifyMore.kt` | `Networking/JSONPath.swift` (`SpotifyBase62`, `SpotifyTrackProtobuf`) | Complete |
| **Apple Music / Spicy TTML Word-Synced Parser** (duets, `x-bg`, `x-roman`, `x-translation`, XXE guard) | `LyricsApi.kt` (`TtmlParser`) | `Services/Lyrics/TtmlLyricsParser.swift` | Complete |
| **LRC / ELRC & Kugou KRC (`@Gaw^2tGQ61-ÎÒni` XOR + zlib) Parsers** | `LyricsApi.kt` | `Services/Lyrics/LrcParser.swift`, `KrcParser.swift` | Complete |
| **Multi-Provider Lyrics Waterfall + Median Audio Intro Alignment** | `LyricsApi.kt` (`alignTo`, `LyricsTiming`) | `Services/Lyrics/LyricsRepository.swift`, `LyricTiming.swift` | Complete |
| **60/120Hz Monotonic Smoothstep Playhead (`LyricClock`)** | `LyricClock.kt` | `Services/Lyrics/LyricClock.swift` | Complete |
| **Spicy Catalogue (`api.spicylyrics.org`) + Custom `.ttml` Local Store** | `SpicyCatalogue.kt` | `Services/Lyrics/SpicyCatalogueService.swift` | Complete |
| **Hangul / Hiragana / Katakana / Cyrillic / CJK Romanizer** | `Romanizer.kt` | `Services/Lyrics/Romanizer.swift` | Complete |
| **Bilingual Lyrics Translation** | `LyricTranslate.kt` | `Services/Lyrics/LyricTranslationService.swift` | Complete |
| **Genius Song Meanings & Verified Referent Annotations** | `GeniusMeaning.kt` | `Services/Lyrics/GeniusMeaningService.swift`, `Features/Lyrics/SongMeaningSheet.swift` | Complete |
| **Spicetify (`color.ini` / `user.css`), `celestify.json` & Glassify Theme Converter** | `NativeTheme.kt`, `GitHubThemes.kt` | `Services/Themes/GitHubThemeService.swift`, `Features/Settings/SettingsSubViews.swift` | Complete |
| **Liquid Glass Chrome & Live Artwork Atmospheric Backdrop** | `LiquidGlass.kt`, `Palette.kt`, `Theme.kt` | `Core/DesignSystem/{LiquidGlass,CelestialTheme,ArtworkPaletteExtractor,AtmosphericBackdrop}.swift` | Complete |
| **Seekable AES-256-CTR (`MSE1`) Offline Encryption & Downloads** | `OfflineCrypto.kt`, `OfflineStore.kt` | `Services/Offline/{OfflineCrypto,OfflineStore}.swift` (`AVAssetResourceLoaderDelegate`) | Complete |
| **Local Audio Files Import & Playlist Merge** | `LocalFiles`, `PlaylistMerge.kt` | `Services/Offline/OfflineStore.swift`, `Features/Library/PlaylistEditorSheets.swift` | Complete |
| **Private On-Device Listening History & 8-Week Recap** | `ListenHistory.kt` | `Services/Offline/ListenHistoryStore.swift`, `Features/Settings/SettingsSubViews.swift` | Complete |
| **Sandboxed JS Extensions (`lyrics`, `audio-source`, `download-source`)** | `:extensions` (QuickJS) | `Services/Extensions/ExtensionManager.swift` (`JavaScriptCore`) | Complete |
| **Lock Screen / Control Center / AirPods Remote & Output Latency Sync** | `PlaybackService.kt`, `SongPlayer.kt` | `Services/Playback/{NowPlayingCoordinator,NativeAudioPlayer,PlayerController}.swift` | Complete |
| **Redacted Diagnostic Logbook** | `Logbook.kt` | `Services/Diagnostics/DiagnosticLogbook.swift` | Complete |
| **Localizations (`en`, `fr`, `pt-BR`)** | `res/values{,-fr,-pt-rBR}/strings.xml` | `Resources/Localizable.xcstrings` | Complete |
