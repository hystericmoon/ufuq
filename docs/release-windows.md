# Releasing the Windows app

The Windows app (`android/desktop`) updates itself from GitHub Releases. A release carries two
files for Windows: `Ufuq-<version>.msi` and `Ufuq-<version>.msi.sig`. The app downloads both,
checks the Ed25519 signature (and GitHub's SHA-256 digest when the API gives one), and only then runs
`msiexec /i Ufuq-<version>.msi /passive /norestart` and exits so the installer can replace it.
An unverified file is never run.

## One-time setup

1. Generate the keypair (needs `pip install cryptography`):
   ```
   python tools/gen_update_key.py
   ```
2. In the GitHub repo, Settings, Secrets and variables, Actions:
   - Secret `UFUQ_UPDATE_PRIVATE_KEY` = the printed private key. Keep a copy in a password manager.
   - Variable (not secret) `UFUQ_UPDATE_PUBLIC_KEY` = the printed public key.
3. Optional, later: secrets `WIN_CERT_PFX` (base64 of the .pfx) and `WIN_CERT_PASSWORD` for Authenticode.
   The workflow already has a step that signs with `signtool` and is skipped while they are absent.

The public key is baked into each build. Installed apps trust only the key they were built with, so
losing the private key means users must install a new build by hand once. Builds made without
`UFUQ_UPDATE_PUBLIC_KEY` (local, pull requests) show "Updates are off in development builds" and never
download anything. For a local test of the updater: `./gradlew :desktop:run -PUFUQ_UPDATE_PUBLIC_KEY=<key>`.

## Releasing

1. Edit the repo-root `VERSION` (for example `0.2.0`, or `0.2.0-beta.1` for a beta). The MSI version is
   the numeric part (`0.2.0`); the full string is shown in the app and used for comparison.
2. Merge, then tag and push: `git tag v0.2.0 && git push origin v0.2.0`. The tag must equal `v` + `VERSION`,
   or the workflow fails.
3. `Release Windows` builds the MSI, signs it, and attaches both files to the release for that tag
   (Mac and Android attach theirs to the same release). A version with a `-` suffix is marked as a pre-release.
   Running the workflow by hand (workflow_dispatch) does the same for the current `VERSION`.
4. Users on the stable channel see the newest non-pre-release; users who turned on "Include beta versions" also
   see pre-releases. A release missing the `.msi` or the `.sig` is ignored by the app.

The MSI `upgradeUuid` in `android/desktop/build.gradle.kts` must never change; it is how `msiexec` finds
and upgrades the installed copy in place.

## SmartScreen

Until Authenticode signing is set up, Windows SmartScreen warns on the first install ("Windows protected
your PC": More info, Run anyway). The Ed25519 signature protects updates from tampering, but it is not
something Windows understands, so it does not remove that warning.
