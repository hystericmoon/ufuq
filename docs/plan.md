# Plan

One phase per Claude Code session. Phases marked **cloud** run in a Linux cloud session (no Xcode): Foundation-only code in `UfuqCore`, verified with `swift test`. Phases marked **Mac** need Xcode and end with a debug build that launches on a clean Mac.

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
7. **File Tray and Now Playing (cloud for UfuqCore, then Mac).** Replaces the old Media and Shelf scope (owner, 27 Nov 2026; reasoning in `docs/decisions/phase7.html`).
   - File Tray: drop files on the top edge (the notch grows a neck toward the drag); shake a drag to get a floating tray at the pointer; actions: zip, convert image, rename, share/AirDrop, reveal; pinned folders; "Add to Ufuq Tray" Services item and ⌥⇧T for keyboard users.
   - Now Playing: source is the open-source mediaremote-adapter helper (run through /usr/bin/perl; BSD-3; covers every player, including browsers and YouTube Music). Spotify via AppleScript is the fallback when the adapter's self-test fails; both failing shows "Now Playing unavailable". Settings shows the active source. It is a third activity in the right wing (8 s turns), a small 144×112 tile next to Battery in the open panel, and a floating player.
   - Motion follows `docs/motion.md`. The UfuqCore part (tray model, Now Playing module and parsers) is built in the cloud; the panel, drag and helper wiring need a Mac.
   Done when: Spotify and a browser tab show with working controls, a file dropped on the top edge can be AirDropped, and the module shows "unavailable" cleanly when the adapter is missing.
7b. **System HUDs and clipboard history (Mac).** Volume, brightness and keyboard backlight as a capsule budding from the notch; clipboard history. Start with a debug build tested on the owner's Mac: macOS 26 moved the volume HUD (the old OSDUIHelper trick is gone; intercepting the keys needs Accessibility access) and macOS may prompt every time an app reads the clipboard.
   Done when: the owner confirms on a real Mac that each HUD shows and that the clipboard prompt behaviour is acceptable; otherwise the part is dropped.
8. **Calendar, Meetings and Transform (Mac).** Next meeting, Join, mic/camera status, auto DND (Calendar and Meetings); Transform: image convert, video compress, combine to PDF; text capture (Vision OCR); remove background (Vision foreground mask). All on-device.
   Done when: an event with a Meet link shows Join 5 min before, and a dropped image can be converted, OCR'd and have its background removed.
9. **Utilities and Release (Mac).** Voice transcribe (Speech), timer/Pomodoro, Stay Awake, system stats, AirPods and download live activities, Make It Yours (glass, accent, shape); all on-device. Then onboarding (permissions per module), Sparkle feed, DMG, app icon, website.
   Done when: a fresh Mac installs from the DMG and updates via Sparkle.

Not planned: lock-screen art, teleprompter, camera, drop-down terminal, sales/stocks, DockDoor/window snap, a cloud file service, an iPhone app (owner, 27 Nov 2026; skipped or much later).

## Android track

Decided 2026-11-26. Lives in `android/` (Kotlin 2.3, Compose, minSdk 26, Adwam's toolchain). Ufuq replaces Adwam's island; Adwam keeps duas, routines, Qibla and its widget. Island design: [Android island mockup](https://claude.ai/artifact/6NrWnbG85x91mBkvknu2Uc) (option A Prayer first, B AI usage and C Media as swipe pages). All phases run in cloud sessions (Android SDK + Robolectric); each ends with tests and screenshots green on CI.

A1. **Core (cloud).** `:core` Kotlin/JVM port of `UfuqCore` (Swift tests are the spec) + Adwam's prayer domain.
A2. **App shell.** Island overlay (ported from Adwam) with collapsed pill and the expanded design above; Live Update chip (promoted ongoing notification, status bar + lock screen + AOD) as the accessible default; Quick Settings tile; settings; prayer wired in.
   Done when: Robolectric screenshots of pill, expanded A/B/C, chip and tile match the mockup; TalkBack labels tested.
A3. **Media.** Media page in the island (MediaSession via notification listener, seek + play/pause).
A4. **Prayer extras.** Prayer silence (DND for N min after adhan; geofenced saved mosques), Ramadan imsak→iftar progress Live Update, travel mode (city follows GPS).
A5. ~~Wear OS~~ — skipped by the owner (2026-11-26).
A6. **Mac → phone sync.** AI usage page (B) and agent status ("needs input", "done") on the phone. Transport (decided 2026-11-26): local network first — the Mac app serves usage and agent events on the LAN (Bonjour/NSD discovery), paired once by QR code with a shared key, encrypted; no backend. Later, opt-in: a push relay the user hosts (e.g. self-hosted ntfy) for away-from-desk agent alerts.
A7. **Other apps' live activities (opt-in, beta).** Rides/deliveries from ongoing notifications in the island; shares the notification-listener permission with A3; nothing stored or sent.

## Windows track

Decided 2026-11-26. Kotlin + Compose Multiplatform Desktop in `android/` as a `:desktop` module, sharing `:core` and the island UI with Android (two codebases total: Swift for Mac, Kotlin for Android + Windows). Starts after Android A2.

W1. **Desktop shell.** Floating pill top-centre (no notch), collapsed / peek / expanded from the shared island UI; hotkey Win+Alt+Space (Alt+Space is the window menu); Esc closes and returns focus; tray icon; launch at login; Narrator labels.
W2. **Local AI usage.** Port the Claude and Codex parsers to Kotlin (Swift tests as spec) and read `%USERPROFILE%\.claude*` and `.codex` directly; no sync needed.
W3. **Release.** MSI/MSIX via a Windows CI runner, signed; auto-update.
