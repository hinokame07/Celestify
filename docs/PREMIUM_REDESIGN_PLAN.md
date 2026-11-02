# MySpoti visual redesign plan

The app already has two Compose presentation paths. The Immersive path covers Home, Search,
Library, playback, lyrics, queue, artist, album, podcast, profile, downloads, extensions,
settings, and most detail pages. It also has a live backdrop renderer and a Haze fallback.
The repository keeps API, playback, and download logic in separate modules.

1. Make Immersive the initial presentation for new installs while preserving saved choices.
2. Define a restrained page, elevated surface, glass, typography, and spacing system in one
   place; route shared Material controls through the same palette.
3. Refine shared editorial cards, rows, search, sheet, tab, mini-player, and player details so
   the existing screens inherit the design without duplicate styling.
4. Review routes that still use shared or Classic UI and bring their common controls into the
   palette without changing their actions.
5. Compile the Android app, run available unit tests, and inspect previews or an emulator if
   the local Android toolchain is present. Record any validation limits.

The existing GPL-3.0 license, attribution, and architecture remain intact.

## Implementation notes

- New installs start in Immersive; existing saved look choices remain intact.
- The shared Immersive tokens now provide near-black, true AMOLED, and light surfaces, with
  readable type, rounded geometry, and a consistent Material palette for shared controls.
- The active track's cached artwork palette supplies a contrast-adjusted accent throughout the
  shell. The player keeps its own light-on-artwork colors in either page appearance.
- Home shortcuts now use a four-column layout on wide screens; search, sheets, tab chrome,
  controls, and artwork edges share the revised palette and spacing. The activity draws edge to
  edge and switches system-bar icon contrast for light pages and the dark full player.
- The light appearance switch is under Settings > Display. The existing Liquid Glass renderer
  and its Android fallback remain in use.

## Validation

- `git diff --check`: passed.
- New strings XML: parsed successfully.
- A local JDK 21 and Android SDK 37.0 were installed in the ignored `.toolchain/` directory.
- `gradlew.bat :app:assembleDebug :app:testDebugUnitTest --no-daemon --stacktrace`: **BUILD SUCCESSFUL**.
- Unit tests: 335 passed, 0 failures, 0 errors, 0 skipped, across 47 suites.
- `apksigner verify`: passed with APK Signature Scheme v2 and the Android debug certificate.
- Debug APK: `dist/MySpoti-redesign-debug.apk` (package `app.myspoti.dev`, 105.62 MiB).
- `adb devices` found no connected device or emulator, so on-device visuals and interactions
  could not be reviewed here.

The optional Classic look and extension-provided web pages retain their own presentation.
Visual device review and release signing remain required before shipping.
