# Celestify development build

Celestify is derived from [Myspoti](https://github.com/kota-zo/myspoti). Copyright notices, GPL-3.0, source attribution, and third-party license files remain with this source. Distribute the complete corresponding source under GPL-3.0 with any APK.

## Build

The local APK uses `app.myspoti.dev` for compatibility with the existing Spotify bridge and to install beside the official Myspoti Beta. Its public Android label is **Celestify**. The package name and WebView bridge names are technical identifiers, not public branding.

From `base/`, with Android SDK 37 and JDK 21 configured:

```powershell
.\gradlew.bat :app:assembleDebug :app:testDebugUnitTest
.\gradlew.bat :app:assembleRelease -PoverDev
```

The second command produces a locally signed, optimized development APK. It is not signed by the Myspoti release key and cannot update an official installation. The old Myspoti release feed is not presented in Celestify's settings or at startup.

## Verification and limits

- Debug compilation and unit tests: 335 tests across 47 suites, 0 failures, on 2026-10-31.
- The optimized development APK is checked by the release build; see the delivery report for its final status.
- No emulator or USB Android device was available in this workspace. Phone and tablet screenshots, touch behavior, and on-device playback remain unverified.
- The earlier login diagnostics show Spotify's challenge orchestrator returning HTTP 400 after CAPTCHA in the development WebView. The official signed Myspoti Beta logged in on the same device. This build does not establish that the external challenge succeeds; test login on a device before relying on it.
- Lyrics only highlight words when the provider supplies word timestamps. Untimed lyrics remain static and readable. The offset control adjusts the visual clock; source timing quality still depends on the provider.
