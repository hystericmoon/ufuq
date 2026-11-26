# Mac release and auto-update

Ufuq updates itself with Sparkle 2. The app checks
`https://github.com/hystericmoon/ufuq/releases/latest/download/appcast.xml` once a day and installs
updates that are signed with the project's EdDSA key. Workflow: `.github/workflows/release-mac.yml`.

## One-time setup

1. Generate the EdDSA key pair on a Mac with Sparkle's tool (from the Sparkle release tarball,
   `bin/generate_keys`). It stores the private key in your login keychain and prints the public key.
   Export the private key with `bin/generate_keys -x sparkle_private_key`.
2. Repository secret `SPARKLE_ED_PRIVATE_KEY`: the contents of the exported private key file.
3. Repository variable `SPARKLE_PUBLIC_KEY`: the printed public key (base64).
4. Keep a safe offline backup of the private key. If it is lost, installed apps can never verify
   an update again.

Builds without `SPARKLE_PUBLIC_KEY` (local, `mac.yml` CI) leave the updater off and Settings shows
"Updates are off in development builds".

## Releasing

1. Bump `VERSION` at the repo root (shared by all platforms).
2. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`. The tag must match `VERSION`.
3. The workflow builds `Ufuq.app`, writes `Ufuq-X.Y.Z.zip` and `Ufuq-X.Y.Z.dmg`, generates and signs
   `appcast.xml`, and uploads all three to the GitHub Release for the tag (created if missing; other
   platform workflows add their files to the same release).

The build number (`CFBundleVersion`) is the workflow run number, so it always increases.
The appcast lists only the version just built.

## Signing and Gatekeeper

Without Developer ID secrets the app is ad-hoc signed. Updates install through Sparkle (the EdDSA
signature is what Sparkle checks), but a first download from the DMG or zip may show a Gatekeeper
warning (right-click, Open). To remove it, add Developer ID and notarization. The workflow already
has marked TODO steps that run only when these secrets exist: `MAC_CERT_P12` (base64 .p12),
`MAC_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.
