# Releasing the Android app

The Android app (`android/app`) updates itself from GitHub Releases, ported from Adwam's updater.
A release carries one file for Android: `ufuq-<version>.apk`. Workflow: `.github/workflows/release-android.yml`.

## How the updater works

- Only **release** builds have it (`BuildConfig.SELF_UPDATE`). Debug builds (`app.ufuq.android.debug`,
  shared debug key, the CI `ufuq-debug-apk` artifact) show "Updates are off in development builds",
  because they could never install a release APK over themselves.
- Settings → About → Updates: version, last check, **Check for updates**, *Check automatically*
  (on by default: "Ufuq checks GitHub once a day for a new version. Turn this off to check only when
  you ask.") and *Beta versions* (pre-releases too; on by default only when the installed build is a
  pre-release).
- The daily check runs when the app opens (at most every 20 h) and shows a dialog only when a newer
  version exists. Offline or failed checks are silent.
- It reads `api.github.com/repos/hystericmoon/ufuq/releases/latest` (or `/releases` with Beta on) and
  takes the newest release newer than the installed one that has `ufuq-<version>.apk`
  (`app.ufuq.core.update.GitHubReleases.pickAsset`). A release that has only the Mac or Windows files
  so far is skipped.
- Download goes to the app cache. Before install it checks the size, GitHub's SHA-256 digest (when the
  API gives one) and that the APK's package is `app.ufuq.android`. The system installer then refuses
  any APK not signed with the same key as the installed app. On first install Android asks the user to
  allow "Install unknown apps" for Ufuq.

## One-time setup

Run `bash tools/setup_release_keys.sh` on your Mac (it sets the Mac and Windows keys too). For Android
it creates a 4096-bit RSA keystore in `~/UfuqKeys/ufuq-release.jks` (alias `ufuq`) and sets these
repository secrets:

| Secret | Value |
|---|---|
| `UFUQ_KEYSTORE_BASE64` | the keystore, base64 |
| `UFUQ_KEYSTORE_PASSWORD` | keystore password |
| `UFUQ_KEY_ALIAS` | `ufuq` |
| `UFUQ_KEY_PASSWORD` | key password |

**Back up `~/UfuqKeys`.** If the keystore is lost, installed phones can never update again; users would
have to uninstall (losing their settings) and reinstall.

## Releasing

1. Bump `VERSION` at the repo root (shared by all platforms; `MAJOR.MINOR.PATCH`).
   `versionName` is `VERSION`; `versionCode` is `MAJOR*1000000 + MINOR*1000 + PATCH`, so it always rises.
2. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`. The tag must match `VERSION`.
3. The workflow builds `:app:assembleRelease` (R8), signs it with the release key, checks the signer
   with `apksigner`, and attaches `ufuq-X.Y.Z.apk` to the tag's release (created if missing).

A tag push without the signing secrets fails on purpose: a debug-signed APK on a release would strand
everyone who installs it. Run manually (Actions → Release Android → Run workflow) without the secrets,
the workflow builds a debug-signed APK as the `ufuq-release-apk` artifact only, with a warning.

## Local release build

```
cd android
export ANDROID_HOME=/opt/android-sdk
# Optional: sign with the real key
export UFUQ_KEYSTORE_FILE=~/UfuqKeys/ufuq-release.jks UFUQ_KEY_ALIAS=ufuq
export UFUQ_KEYSTORE_PASSWORD=… UFUQ_KEY_PASSWORD=…
./gradlew :app:assembleRelease
```

Without `UFUQ_KEYSTORE_FILE`, Gradle warns and signs with the shared debug key. Such an APK installs as
`app.ufuq.android` but cannot update, or be updated by, a release-signed install.

## Testing an update end to end

1. Install the release APK of the current version (from a release, or a local build with the real key).
2. Publish a newer version (or a pre-release with Beta on).
3. Settings → About → Updates → Check for updates → Download → Install. Ufuq restarts on the new version.
