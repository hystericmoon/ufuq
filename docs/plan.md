# Plan

One phase per Claude Code session. Phases marked **cloud** run in a Linux cloud session (no Xcode): Foundation-only code in `UfuqCore`, verified with `swift test`. Phases marked **Mac** need Xcode and end with a notarized debug build that launches on a clean Mac.

1. **Core skeleton (cloud).** `UfuqCore` Swift package: `UfuqModule` protocol and UI-free `ModuleStatus`, `LiveActivity`, `PeekEvent`; `ModuleRegistry` (catches module errors), `ActivityArbiter` (wing priority + 8 s rotation), `PeekQueue` (critical jumps the queue). Usage thresholds (80/95) and burn-rate estimate.
   Done when: `swift test` passes on Linux with tests for arbiter priority, rotation, peek ordering, thresholds and burn rate.
2. **Prayer engine (cloud).** Port the Adwam calculation (hystericmoon/muslimdaily) into `UfuqCore`: Kemenag default, other methods and madhab, next-prayer and countdown, Hijri date.
   Done when: tests match Kemenag's published Jakarta times within 1 minute on 30 sampled days.
3. **Usage parsers (cloud).** Parsers for Claude Code JSONL logs (per `CLAUDE_CONFIG_DIR`) and Codex session files, from sample fixtures in `Tests/Fixtures`; defensive against unknown fields. Claude live-limit client behind a protocol (endpoint unverified).
   Done when: parser tests pass on the fixtures, and malformed files produce `.unavailable`, never a crash.
4. **Notch shell (Mac).** Xcode project importing `UfuqCore`; `NSPanel` over the notch, collapsed/peek/expanded, ⌥Space hotkey with focus in and Esc back, optional hover, floating pill on non-notch displays, launch at login.
   Done when: Prayer and AI show in their wings, ⌥Space opens the panel with VoiceOver focus inside, and the pill appears on an external display.
5. **Prayer + AI UI (Mac).** Prayer and AI expanded panels and peeks from the design canvas, real data from the user's `~/.claude*` and `~/.codex`; verify the Claude limit source and Codex fields on real files; Antigravity plugin labelled "Beta source".
   Done when: two Claude accounts and Codex show numbers that agree with `/usage`, and a disabled Antigravity source shows "unavailable".
6. **Agent status (Mac).** Claude Code hooks for running/waiting/done; click jumps to the terminal; GitHub Actions status.
   Done when: a real Claude Code task shows the three states in order and a click focuses its window.
7. **Media and Shelf (Mac).** Now Playing via adapter, HUD replacement, file shelf with AirDrop, clipboard history.
   Done when: Spotify and Music.app show with controls, and the module turns itself off cleanly when MediaRemote is unavailable.
8. **Designer shelf and Meeting mode (Mac).** Screenshot to shelf, annotate, color picker; next meeting, Join, mic/camera status, auto DND.
   Done when: a screenshot lands on the shelf instead of the Desktop, and an event with a Meet link shows Join 5 min before.
9. **Release (Mac).** Onboarding (permissions per module), Sparkle feed, DMG, app icon, website.
   Done when: a fresh Mac installs from the DMG and updates via Sparkle.

## Android track

Decided 2026-11-26. Lives in `android/` (Kotlin 2.3, Compose, minSdk 26, Adwam's toolchain). Ufuq replaces Adwam's island; Adwam keeps duas, routines, Qibla and its widget. Island design: [Android island mockup](https://claude.ai/artifact/6NrWnbG85x91mBkvknu2Uc) (option A Prayer first, B AI usage and C Media as swipe pages). All phases run in cloud sessions (Android SDK + Robolectric); each ends with tests and screenshots green on CI.

A1. **Core (cloud).** `:core` Kotlin/JVM port of `UfuqCore` (Swift tests are the spec) + Adwam's prayer domain.
A2. **App shell.** Island overlay (ported from Adwam) with collapsed pill and the expanded design above; Live Update chip (promoted ongoing notification, status bar + lock screen + AOD) as the accessible default; Quick Settings tile; settings; prayer wired in.
   Done when: Robolectric screenshots of pill, expanded A/B/C, chip and tile match the mockup; TalkBack labels tested.
A3. **Media.** Media page in the island (MediaSession via notification listener, seek + play/pause).
A4. **Prayer extras.** Prayer silence (DND for N min after adhan; geofenced saved mosques), Ramadan imsak→iftar progress Live Update, travel mode (city follows GPS).
A5. **Wear OS.** `:wear` module: tile + complication (next prayer, worst AI %), haptic at adhan.
A6. **Mac → phone sync.** AI usage page (B) and agent status ("needs input", "done") on the phone. Transport (decided 2026-11-26): local network first — the Mac app serves usage and agent events on the LAN (Bonjour/NSD discovery), paired once by QR code with a shared key, encrypted; no backend. Later, opt-in: a push relay the user hosts (e.g. self-hosted ntfy) for away-from-desk agent alerts.
A7. **Other apps' live activities (opt-in, beta).** Rides/deliveries from ongoing notifications in the island; shares the notification-listener permission with A3; nothing stored or sent.
