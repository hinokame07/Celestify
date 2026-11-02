# Celestify releases

The [public release feed](https://api.github.com/repos/hinokame07/Celestify/releases/latest) identifies the latest stable release. Every published Android update should have a signed APK named `Celestify-<version>.apk`, its checksum and corresponding source. The app uses this feed without a GitHub login. Prereleases stay out of stable update prompts.

## Installed versions

- From 2.4.3, automatic checks are enabled by default. Settings remembers an explicit opt-out. The app checks at launch/resume and approximately every hour while open. An Android network-constrained periodic job also checks in the background. Android controls its timing, including Doze and force-stop. A notification opens the app for review and installation. Notifications need Android notification permission. In-app updates remain available when notifications are disabled. A release already announced in the app or by the notification is not repeatedly posted to the notification tray.
- From 2.2.0 through 2.4.2 the public stable feed works with the existing updater. Its switch was off by default. Turn on automatic checks under Settings → App or use the manual check. With the old switch off, those binaries cannot receive an automatic notice from the repository alone. Builds through 2.1.0 need a manual first installation of a current APK.
- Android requires the same package and signing certificate for an in-place upgrade. Installation is confirmed by the user.

## Publishing

Bump the version name and the checked-in Android version code for **every distributed APK**, including betas. Verify that the code increases over the previous release for `app.myspoti.dev`. Push main and its matching semantic version tag together. The Android workflow uses the tagged version code instead of a GitHub run counter. When CI signing is configured, it tests, builds and checks the certificate before uploading the APK and checksum. Without signing secrets, sign locally with the existing identity. Upload and verify all assets on a draft, then publish the stable release as GitHub's **Latest**. Check the anonymous releases/latest response and its APK download. Public downloaders have access to the matching source tag.

CI signing uses CELESTIFY_KEYSTORE_BASE64, CELESTIFY_KEYSTORE_PASSWORD, CELESTIFY_KEY_ALIAS and CELESTIFY_KEY_PASSWORD as GitHub Actions secrets. Keep keys and credentials outside Git.
