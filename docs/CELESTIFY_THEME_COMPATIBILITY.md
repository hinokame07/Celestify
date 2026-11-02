# Celestify native theme conversion v1

Celestify is a GPL-3.0 derivative of [Myspoti](https://github.com/kota-zo/myspoti). Original and third-party notices remain in the source.

## Supported conversion

The browser in Extensions → Themes accepts public `https://github.com/owner/repository` URLs. It discovers `color.ini`, `user.css`, and `celestify.json` in the default branch. Files are fetched from one immutable commit, so the preview and installed palette cannot mix revisions. Installation stores a native JSON configuration; no repository code runs in the application.

Spicetify's [theme specification](https://spicetify.app/docs/development/themes) targets Spotify Desktop. Celestify does not reproduce its DOM or CSS layouts.

| Source | Native token |
| --- | --- |
| `main` | page background |
| `sidebar` | secondary surface |
| `card`, fallback `player` | elevated surface |
| `text` | primary text |
| `subtext` | secondary text |
| `button` | accent |

INI sections become selectable color schemes. Hex RGB, short hex RGB and decimal RGB are accepted. CSS-only themes can supply these same `--spice-*` color variables. Desktop selectors, positioning, animations, arbitrary URLs, font loading, scripts, environment variables and unsupported color expressions are ignored. INI is authoritative when present. Theme geometry and the bundled licensed Inter font remain native.

All imported palettes are normalized to dark backgrounds (relative luminance at most 0.035). Text and accent colors must have at least 4.5:1 contrast against every imported surface; otherwise native defaults replace them. The preview shows the resulting colors. A desktop screenshot is labeled separately and never presented as an Android screenshot.

## Compatibility labels

- **Partially compatible**: any successfully converted desktop palette, even if every color was parsed. Unsupported desktop properties remain unapplied.
- **Unsupported**: no meaningful palette can be converted, or validation fails.
- **Fully compatible · Native v1**: an explicit `celestify.json` contract containing exactly the properties below, with no nonempty `user.css`, all colors valid, dark and accessible without normalization. This claims conformance only to the native v1 contract, not desktop Spicetify compatibility.

```json
{
  "schema": 1,
  "colors": {
    "background": "050507",
    "surface": "12151D",
    "elevated": "1A1E28",
    "text": "F7F9FF",
    "secondary": "A8B2C3",
    "accent": "B9DEFF"
  }
}
```

## Storage and transport

GitHub metadata uses HTTPS with bounded responses and connection/read/call timeouts. Raw files are pinned to the commit SHA. Redirects are disabled. Git symlinks, absolute paths, traversal components and backslashes are rejected. Only text files and bounded repository-owned raster previews are fetched. External scripts, native binaries, SVG and remote font assets are never loaded.

The browser intentionally does not download or extract ZIP archives. ZIP input presented as a theme text file is rejected. This removes the archive extraction and decompression-bomb path altogether. Text files are capped at 512 KiB, previews at 2 MiB and decoded preview dimensions at 4096 × 4096 with downsampling. The repository tree is capped at 6 MiB and 150 themes; truncated trees are rejected.

Installed configurations live in app-private `files/celestify-themes/themes.json`. Writes use a synced temporary file followed by atomic replacement. A failed installation leaves the active and installed registry intact. Installing an update preserves the previously applied configuration until Apply is pressed. Reset returns to Celestial Midnight. Removing an active theme returns to the built-in palette. Installed palettes work offline; catalog discovery and update checks require GitHub connectivity.

Update indicators compare the repository commit with the installed commit. An unrelated repository change can therefore offer a revision with unchanged theme colors. Previewing before applying makes this visible. No background automatic theme updates are performed.

## Validation

Tests cover parsing, RGB conversion, dark normalization and contrast, unsupported CSS, malformed/oversized text and ZIP rejection, repository/path validation, persistence, failed installation rollback, isolated update previews, lyric word timing, and phone-only layout policies. An opt-in live GitHub contract test uses `CELESTIFY_LIVE_THEMES_TEST=1` and discovers/converts the official Default theme.

Device rendering, real playback synchronization, and tablet screenshot comparison require an Android device or emulator; these must not be inferred from unit tests.
