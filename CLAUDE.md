# Ufuq

## Goal

A macOS notch app (Dynamic Island-style) with native polish and a small core. Main modules: prayer times and multi-account AI usage limits (Claude, Codex, Antigravity). Later: agent status, media/shelf, designer shelf, meeting mode. Full spec: `docs/spec.md`.

## Decisions

- **Swift + SwiftUI, AppKit `NSPanel` for the notch window.** SwiftUI alone can't place a borderless panel above the menu bar.
- **macOS 14+, Apple Silicon and Intel.** Same floor as the leading notch apps; keeps modern SwiftUI APIs available.
- **Not sandboxed; ad-hoc signed DMG + Sparkle; no Mac App Store, no Apple Developer account (owner, 27 Nov 2026).** The AI usage module must read `~/.claude*` and `~/.codex`, which the sandbox blocks. Never plan work that needs Developer ID or notarization.
- **Logic lives in the `UfuqCore` Swift package (Foundation only); the Mac app imports it.** Work starts in Linux cloud sessions with no Xcode, and keeping logic UI-free lets `swift test` run anywhere.
- **Every module implements `UfuqModule` and is loaded by `ModuleRegistry`.** Several data sources are undocumented (Claude limits, Codex logs, Antigravity, MediaRemote); one breaking must show "unavailable", never crash the app.
- **Collapsed AI indicator = one ring per provider + worst % as text.** Chosen on the design canvas: all providers visible without opening the panel.
- **Prayer in the left wing, AI in the right; a third activity rotates every 8 s.** Fixed positions build habit; notch width stays constant.
- **Usage thresholds: amber at 80%, red at 95%.** Also the two peek-alert points.
- **Prayer: local calculation, Kemenag method by default.** Works offline; primary user is in Jakarta. Port the logic from Adwam (hystericmoon/muslimdaily).
- **Hotkey always opens the panel; hover is optional.** Keyboard and VoiceOver users must never depend on the pointer.
- **Antigravity is an isolated plugin labelled "Beta source".** No public API; its source is the most fragile.

## Working with the owner

- If you can do it yourself (merge, run workflows, fix CI, publish), do it; never hand the owner a step you can run. Only device checks, local keys and decisions are theirs.

## Commands

Core package (Linux or Mac), from `UfuqCore/`:

- Build: `swift build`
- Test: `swift test`

Android (from `android/`; JDK 17 or newer, `export ANDROID_HOME=/opt/android-sdk` once the app module exists):

- Test the Kotlin core: `./gradlew :core:test`
- App checks (what CI runs): `./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleRelease`
- Release and self-update: `docs/release-android.md` (tag `v*` → `release-android.yml`)
- Re-record screenshots (Linux renders, `android/app/src/test/screenshots`): `./gradlew :app:recordRoborazziDebug`; compare with `:app:verifyRoborazziDebug`

Windows (from `android/`; JDK 21, `export ANDROID_HOME=/opt/android-sdk` because the build includes `:app`):

- Test (headless, also on Linux; writes PNGs to `android/desktop/build/screenshots`): `./gradlew :desktop:test`
- Run the island on a dev machine: `./gradlew :desktop:run`
- MSI (needs a Windows runner with WiX): `./gradlew :desktop:packageMsi`; CI is `.github/workflows/windows.yml`

Mac app (Xcode required). The Xcode project is generated from `project.yml` and not committed. From the repo root:

- Generate: `brew install xcodegen && xcodegen generate` (rerun after adding or removing files)
- Build: `xcodebuild -scheme Ufuq -configuration Debug build`
- Test: `xcodebuild -scheme Ufuq test`
- CI (`.github/workflows/mac.yml`, macos-15) runs `xcodebuild -scheme Ufuq -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build test`; `CODE_SIGNING_ALLOWED=NO` is for CI only. Snapshot PNGs are written to `$SNAPSHOT_DIR` (CI passes it as `TEST_RUNNER_SNAPSHOT_DIR`) and uploaded as the `snapshots` artifact.

## Pointers

- Spec: `docs/spec.md`
- Plan: `docs/plan.md`
- Design canvas and refs: `refs/README.md`
- UI rules: `.claude/rules/ui.md`
- Tracker: docs/progress.md
