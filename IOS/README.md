# Celestify for iOS

<p align="center">
  <strong>Native Swift &amp; SwiftUI iOS Port of Celestify — Liquid Glass Aesthetics, Syllable-Synced Spicy Lyrics, Live Artwork Atmospheres &amp; Resilient Keychain Authentication</strong>
</p>

Celestify for iOS (`/IOS`) is a complete, clean-room native iOS port of Celestify (`2.4.x`), built with **Swift**, **SwiftUI**, **Observation (`@Observable`)**, **WebKit**, **AVFoundation**, **MediaPlayer**, **JavaScriptCore**, and **Apple Keychain**.

The Android codebase in `/base` remains 100% untouched.

---

## Upstream Foundation & Open-Source Attribution

- **Built on [Myspoti](https://github.com/kota-zo/myspoti)** by **kota-zo** — Celestify's clean-room Spotify Web Player bridge, Pathfinder v2 persisted GraphQL & `spclient` protocol client, seekable AES-256-CTR offline encryption (`MSE1`), listening history, and multi-provider lyrics engine originate from Myspoti and are distributed under the **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)**. See [`LICENSE`](./LICENSE).
- **Glassify Compatibility Profile ([`sanoojes/spicetify-glassify`](https://github.com/sanoojes/spicetify-glassify))** — Native Liquid Glass compatibility rules in `GlassifyAdapter` are adapted from `spicetify-glassify` under **GNU Affero General Public License v3.0 (`AGPL-3.0`)**. Remote CSS and JS are never executed on iOS. See [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md).

---

## Highlights

- **Apple Music iOS 26 Liquid Glass Design System**
  - Uses native `.glassEffect(...)` when compiled with the iOS 26 SDK (`#if compiler(>=6.2)` + `@available(iOS 26.0, *)`) and falls back gracefully on iOS 17–18 to multi-stop specular refraction borders, vibrancy materials, and real-time `MeshGradient` / Canvas album-art atmospheres.
  - Full support for **Celestial Midnight**, **Golden Seraph**, **Adaptive Celestial**, **Pure Black OLED**, **Reduce Transparency**, **Reduce Motion**, **Dynamic Type**, and **VoiceOver**.
- **60/120Hz ProMotion Spicy Lyrics & Music Player**
  - Parallel word-synced resolution across **Spicy Catalogue (`spicylyrics.org`)**, **Local `.ttml` Overrides**, **Spotify Color Lyrics**, **LyricsPlus**, **lrc.red TTML**, **Kugou KRC** (`@Gaw^2tGQ61-ÎÒni` XOR + zlib), and **LRCLIB** (plus opt-in NetEase & Genius), with a configurable Spicy API key.
  - Median audio intro timestamp alignment (`LyricTiming.alignToSpotifyAudio`), timestamped smoothstep `LyricClock` playhead steering, Bluetooth/AirPlay `AVAudioSession.outputLatency` compensation, offset-correct lyric seeks, simultaneous duet highlighting, `x-bg` backing vocals, native Hangul/Kana/Cyrillic/ICU `Romanizer`, live bilingual translation, and **Genius Song Meanings & Verified Line Annotations**.
  - Lyrics player backdrops can use the animated artwork mesh, blurred cover, artist header, artwork palette, or no image, with adjustable blur.
- **Hardened Spotify Authentication & Session Persistence**
  - Fixes Android's WebView User-Agent mismatch, OAuth/CAPTCHA popup drops, email-OTP lifecycle wipes, and multi-caller 401 token race conditions.
  - Supports interactive WebKit login, manual `sp_dc` cookie import, email magic-link deep links, and multi-account switching stored in hardware-backed **Apple Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- **Unified Playback, Lock Screen Controls & Encrypted Offline Audio**
  - Coordinates the hidden `WKWebView` Spotify Web Player engine (`player-bridge.js` adapted for `WKScriptMessageHandler`), **Spotify Connect**, **Spotify Jam**, **Soundfinder** direct podcast streaming, **JavaScriptCore** audio-source extensions, imported **Local Audio Files**, and seekable **AES-256-CTR (`MSE1`)** encrypted offline downloads streamed directly into `AVPlayer` via `AVAssetResourceLoaderDelegate` without writing plaintext to disk.

---

## Project Layout

```text
IOS/
├── Celestify.xcodeproj/           # Ready-to-open Xcode 15/16/26 project + shared scheme
├── Package.swift                  # Swift Package Manager manifest for indexing & CLI testing
├── project.yml                    # Optional XcodeGen specification
├── Configuration/                 # Base/Debug/Release xcconfig, Info.plist, Entitlements, PrivacyInfo.xcprivacy
├── Celestify/
│   ├── App/                       # CelestifyApp.swift, AppDependencies.swift, RootShellView.swift
│   ├── Core/
│   │   ├── DesignSystem/          # LiquidGlass, CelestialTheme, ArtworkPaletteExtractor, AtmosphericBackdrop, Haptics
│   │   ├── Navigation/            # AppRouter (4 tabs + spotify: / open.spotify.com deep links)
│   │   └── Preferences/           # PreferencesStore (@Observable persisted settings)
│   ├── Models/                    # DomainModels, LyricsModels, ThemeModels
│   ├── Networking/                # HTTPClient, JSONPath, Base62/Protobuf, TokenCoordinator, Bridge, GQL, APIClient
│   ├── Services/
│   │   ├── Auth/                  # KeychainStore, SpotifyAuthManager, SpotifyLoginWebView
│   │   ├── Diagnostics/           # Redacted DiagnosticLogbook
│   │   ├── Extensions/            # Sandboxed JavaScriptCore ExtensionManager
│   │   ├── Lyrics/                # LRC/ELRC, KRC, TTML, LyricTiming, LyricClock, Romanizer, Translate, Genius, Spicy
│   │   ├── Offline/               # OfflineCrypto (AES-256-CTR + AVAssetResourceLoader), OfflineStore, ListenHistoryStore
│   │   ├── Playback/              # NowPlayingCoordinator, NativeAudioPlayer, PlayerController
│   │   └── Themes/                # SpicetifyThemeParser, GlassifyAdapter, ThemeManager
│   ├── Components/                # ArtworkView, TrackRowView, MediaCardView, FloatingLiquidTabBar
│   ├── Features/                  # Auth, Home, Search, Library, Catalog, Lyrics, Player, Settings
│   └── Resources/                 # Assets.xcassets, Localizable.xcstrings (en/fr/pt-BR), gql-ops.json, player-bridge.js
└── Tests/
    ├── CelestifyTests/            # Unit tests (parsers, timing, clock, crypto, themes, history, redaction)
    └── CelestifyUITests/          # XCUITest launch & onboarding smoke suite
```

---

## Building & Running in Xcode

### Requirements
- **macOS Sonoma 14.5+** or **macOS Sequoia / Tahoe**
- **Xcode 16.0+** (or **Xcode 26+** for native iOS 26 `.glassEffect` SDK APIs)
- **iOS 17.0+** deployment target (runs on iOS 17, iOS 18, and iOS 26 devices & simulators)

### Quick Start
1. Open `IOS/Celestify.xcodeproj` in Xcode:
   ```bash
   open IOS/Celestify.xcodeproj
   ```
2. Select the **Celestify** target → **Signing & Capabilities**, and pick your Apple ID / Personal Team (or Developer Program Team). Adjust the Bundle Identifier if needed.
3. Select an iPhone Simulator or physical iPhone and press **⌘R** to build and run.
4. Run unit tests via **⌘U** or from Terminal:
   ```bash
   xcodebuild test \
     -project IOS/Celestify.xcodeproj \
     -scheme Celestify \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
   ```

*(Optional)* If you add or remove files and use [XcodeGen](https://github.com/yonaskolb/XcodeGen), run `cd IOS && xcodegen generate`.

---

## License

Celestify for iOS is free software distributed under the **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)**. See [`LICENSE`](./LICENSE) and [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md) for complete terms and upstream credits.
