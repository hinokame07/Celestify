# Third-Party Notices — Celestify for iOS

Celestify for iOS is free software published under the **GNU General Public License v3.0 (GPL-3.0)** (see `LICENSE`), with specific adapted components subject to **GNU Affero General Public License v3.0 (AGPL-3.0)** under Section 13 compatibility as detailed below.

---

## Myspoti — GPL-3.0
https://github.com/kota-zo/myspoti

Celestify is built on **Myspoti**. The Spotify Web Player bridge (`Resources/Spotify/player-bridge.js`), persisted GraphQL operation catalogue (`Resources/Spotify/gql-ops.json`), domain API contracts, Pathfinder/spclient JSON mappers, library/playlist merge semantics, offline AES-CTR format (`MSE1`), and multi-provider lyrics alignment pipeline are ported from Myspoti and remain licensed under the GNU General Public License v3.0.

## Celestify Android — GPL-3.0 / AGPL-3.0
https://github.com/hinokame07/Celestify

This iOS client ports Celestify 2.4.4's Celestial Midnight, Golden Seraph, and Adaptive Celestial palettes, Immersive experience, Spicy Stage & Cinema workflows, Genius song meanings, Spicetify/Glassify native theme importer, and playback/lyrics preferences to native Swift and SwiftUI with Apple Liquid Glass.

## BitChord — GPL-3.0-or-later
https://github.com/kushagrasinghx/BitChord (commit `edc1e6f`)

The frame-steered monotonic playhead clock (`Services/Lyrics/LyricClock.swift`), word-swept karaoke line timing/lift/glow math (`Features/Lyrics/ImmersiveLyricsPanel.swift`), thin expanding scrubber (`Components/ThinGlassScrubber.swift`), and floating glass tab pill mechanics (`Components/FloatingGlassTabBar.swift`) adapt algorithms from BitChord and remain under GPL-3.0-or-later.

## Spicy Lyrics & Spicy Lyrics Mobile — AGPL-3.0
- https://github.com/Spikerko/spicy-lyrics (commit `34ad8c683204c522f227060475bf4f8aae36508e`)
- https://github.com/spicylyrics/mobile (commit `4565dde58003a7796c2be32f3022cef773dfa73b`)

The TTML parser (`Services/Lyrics/TtmlLyricsParser.swift`), Spicy Catalogue client and local `.ttml` import store (`Services/Lyrics/SpicyCatalogueService.swift`), multi-script romanizer (`Services/Lyrics/Romanizer.swift`), syllable emphasis/float/glow rendering, and fullscreen/split Cinema stage (`Features/Lyrics/SpicyCinemaView.swift`) are native Swift ports of Spicy Lyrics and Spicy Lyrics Mobile, licensed under **AGPL-3.0**. Myspoti's GPL-3.0 notices remain in force; Section 13 of both licenses governs the combined work. The Spicy Lyrics hosted service, assets, and databases remain separate from this client.

## Kawarp Background Inspiration — MIT
Copyright (c) 2026 Better Lyrics. `Core/DesignSystem/AtmosphericBackdrop.swift` adapts the multi-stop artwork color extraction, domain-warped aurora motion, vignette, and saturation concepts of Kawarp 1.3.1 to SwiftUI `MeshGradient` / Canvas rendering.

## Glassify Native Compatibility Profile — AGPL-3.0
https://github.com/sanoojes/spicetify-glassify (commit `ee8932c59136e585f5e9c65dbfa2e1d786b97050`)

Copyright Sachu and contributors. `GlassifyAdapter` in `Services/Themes/GitHubThemeService.swift` maps the documented artwork-tinted dark glass and floating-chrome intent of `sanoojes/spicetify-glassify` onto Celestify's native iOS Liquid Glass renderer without bundling or executing remote CSS, SCSS, or TypeScript. Licensed under AGPL-3.0 (combined via Section 13).
