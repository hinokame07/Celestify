# Celestify

Celestify is a native Android music app derived from [Myspoti](https://github.com/kota-zo/myspoti). Its Immersive interface pairs a dark celestial palette with glass navigation, artwork lighting and timed lyrics when the provider supplies timestamps.

To personalize your account on this device, tap the avatar on Home and choose **Change photo on this device**. To go back, choose **Restore account photo** in the same menu. Both Classic and Immersive use the same local photo.

## Development build

See the [build instructions](docs/CELESTIFY_BUILD.md), [device and release checks](docs/CELESTIFY_MIDNIGHT_VALIDATION.md) and [theme compatibility notes](docs/CELESTIFY_THEME_COMPATIBILITY.md).

Open **Extensions → Themes** to import a public Spicetify theme. Glassify has a dedicated Android profile with artwork-driven color, translucent surfaces and native Liquid Glass; remote desktop scripts and CSS are never executed.

## Credits and licensing

Celestify retains the [GPL-3.0 license](LICENSE) and credits the original Myspoti authors. Distribute the complete corresponding source with the application. The [upstream README and credits](README.upstream.md), [third-party notices](THIRD_PARTY_NOTICES.md) and [bundled licenses](base/licenses/) accompany this project.

## Versions and updates

Open **Settings → App → Versions on GitHub** and sign in to the private repository. Install the APK from the latest release. The first upgrade from the earlier 2.1.0 builds is manual. The optional in-app checker requires a feed accessible without GitHub credentials. See [release instructions](docs/CELESTIFY_RELEASES.md). The Spicy Lyrics native renderer component is under [AGPL-3.0](base/licenses/Spicy-Lyrics-AGPL-3.0.txt), alongside the Myspoti GPL-3.0 code.

## Spicy Lyrics on Android

Open the player, tap **Lyrics**, then tap the **clapperboard** for Cinema. The eye button shows or hides playback controls. The arrows swap the lyrics and artwork on a wide screen. The overflow menu inside Cinema offers video when the active source provides it. The lyrics menu includes TTML imports, romanization, text size and floating lyrics.

Celestify 2.4.0 renders the player and Cinema with Jetpack Compose and synchronized lyrics with the Kotlin Canvas port of Spicy Lyrics Mobile. OpenGL ES draws the artwork background using the Kawarp 1.3.1 domain warp. The existing Spotify audio session, Connect and native media sources continue to supply the playback clock. See the [architecture and native test report](docs/SPICY_PORT.md).

- Syllables, duet alignment, background vocals, credits and embedded translations are preserved when present in the TTML. Static lyrics remain untimed. A temporary preview is kept in session memory. Import permanently to keep the file across restarts. Saved Lyrics in Settings lists imported tracks and can remove their files.
- The community catalogue is opt-in. Enter a **publishable client key** in Settings → Lyrics to send the current Spotify track ID to Spicy Lyrics. With no key, local files and Celestify's providers work independently. Availability and rate limits belong to each provider.
- Cinema includes transport controls and artwork-derived backgrounds. Floating lyrics require Android picture-in-picture support. The Compose Celestify mode remains available for the text list and Genius notes.
- Spicetify Marketplace installation, desktop CSS snippets, browser extension injection, Discord presence and community account administration are outside the Android renderer. This build does not implement community upload, desktop shortcuts or cloud library synchronization.
