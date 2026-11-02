# Celestify release process

The private repository is the source of truth for Celestify. Each release contains the signed APK and its SHA-256 checksum. The tagged tree includes the corresponding source and licenses. Give APK recipients access to that source or provide a copy alongside the APK.

## On a phone

Open Settings → App → Versions on GitHub, sign in with an authorized GitHub account and download the APK. Android verifies the signing identity and asks before installing. Builds through 2.1.0 require a manual first update. The optional automated checker is prepared for an accessible releases API. GitHub denies anonymous API access to private releases. If a version check fails, use the authenticated browser link.

## Publishing

Push a semantic version tag such as v2.2.1 for a stable release or v2.3.0-beta.1 for a beta. Keep main and the tag on the tested source. The tag workflow runs unit tests, signs the APK, checks the Celestify certificate and publishes the APK and checksum together. GitHub creates source archives from the same tag. Use a consistent workflow and increasing version codes for all updates to app.myspoti.dev.

For unattended signing a repository administrator must configure CELESTIFY_KEYSTORE_BASE64, CELESTIFY_KEYSTORE_PASSWORD, CELESTIFY_KEY_ALIAS and CELESTIFY_KEY_PASSWORD as GitHub Actions secrets. The certificate must match the existing Celestify build. Before entrusting a signing key to CI, ensure it is dedicated to the app. With no signing secrets, CI runs tests and leaves signing to the maintainer. Build locally with the existing signing identity, verify the certificate with apksigner, then attach the signed APK and checksum to the release. Keep credentials, local device logs and keystores outside Git.
