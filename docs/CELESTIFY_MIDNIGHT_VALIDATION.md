# Celestify Midnight implementation and validation

This revision replaces the light public identity with Celestial Midnight (default), Golden Seraph and Adaptive Celestial. The existing Compose navigation, tablet grid definitions, panel placement and player dimensions are retained. Phone controls additionally adapt to short landscape windows and large system fonts. These policies have unit coverage; screenshots of real devices have not been compared.

Extensions now links to a native theme browser. It discovers public GitHub repositories, loads previews and compatibility labels, offers installed/offline palettes, checks repository revisions, and supports install, apply, update, reset and removal. Installation and preview are separate from application. A previously applied configuration is retained while an update is staged. The [conversion specification](CELESTIFY_THEME_COMPATIBILITY.md) lists supported properties and limits.

Dark materials share the existing live backdrop renderer and fallback paths. The mini-player uses Moonlight material; navigation uses Obsidian; sheets use Crystal Overlay or Seraph fills. Theme tokens also feed Material controls, lyrics, dialogs, settings and the full player. Bundled Inter and its license remain intact. Animation reduction and lifecycle gates remain in use; player particles stop moving when playback pauses.

Lyrics use the playback clock, output latency and the user's timing offset. A fixed 150 ms line-selection lead was removed from the full lyrics view. Continuous word fill uses provided word duration; missing word ends use the supplied start timestamp without inventing a duration. Untimed lyrics remain static.

## Checks performed on 2026-10-31

- 351 tests passed, 0 failed, 0 skipped in the final test run. This includes an opt-in real GitHub discovery/conversion check for the official Spicetify Default theme.
- New coverage includes native/INI/CSS parsing, hex and RGB formats, dark normalization, contrast, invalid metadata and oversized/ZIP input rejection, repository/path validation, persisted applied themes, update preview isolation, failed installation/staging rollback, lyric word timing and compact/standard/large phone and tablet policies.
- Debug and optimized development builds are generated through Gradle. The delivered APK keeps `app.myspoti.dev` and is locally signed; it installs beside the official Beta.
- `lintDebug` ran and failed: the report contained 1025 errors, 442 warnings and 33 hints. The largest category was 895 missing-translation errors across the project. New theme strings currently support English and Portuguese and fall back to English for other locales. Existing reports also include Automotive manifest, experimental APIs and Compose state/resource findings. The new theme screen's configuration-unaware resource reads and the active Extensions screen's stale registry read were corrected after inspecting that report. The full Lint gate is not claimed to pass.
- ADB reported no connected devices; no emulator/system image was installed. Actual phone/tablet rendering, Android installation, gestures, real-audio lyric synchronization and Spotify login could not be verified here. The previously reported CAPTCHA login failure is not claimed fixed.

Source and license notices continue to credit [Myspoti](https://github.com/kota-zo/myspoti). Distribute the corresponding GPL-3.0 source archive with the APK.

## Profile photo and launcher checks, 2026-11-02

- [x] Built the debug APK and ran the app unit suite. 350 tests passed. The optional live GitHub theme test was skipped.
- [x] Verified the APK signature matches the previous Midnight development build. Inspected the packaged application ID, version and Celestify label.
- [x] Rendered and inspected the new launcher foreground against its dark background.
- [ ] On phone and tablet, select, replace and restore a photo in Classic and Immersive. Check cancellation, rotation, restart and switching accounts. ADB found no connected device.
- [ ] Verify launcher masks, themed icons and splash on device. Recheck the outstanding login and lint items above before a public release.
