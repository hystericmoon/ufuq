# Plan

One phase per Claude Code session, run on the Mac. Each phase ends with a notarized debug build that launches on a clean Mac.

1. **Notch shell.** Xcode project, `NSPanel` over the notch, collapsed/peek/expanded states, hotkey + optional hover, focus moves in and Esc returns it, floating pill on non-notch displays, `UfuqModule` + `ModuleRegistry` with stub Prayer and AI modules, launch at login.
   Done when: both stubs show in their wings, ⌥Space opens the panel with VoiceOver focus inside, and the pill appears on an external display.
2. **Prayer.** Port the Adwam calculation; countdown, the six times, Hijri date, pre-adhan peek with Mute media, manual city fallback.
   Done when: times match Kemenag's published Jakarta times within 1 minute on 30 sampled days (unit test).
3. **AI usage.** Spike the Claude limit source and Codex log fields first (findings in `docs/`), then multi-account Claude cards, Codex card, Antigravity plugin labelled "Beta source", 80%/95%/reset peeks, burn rate.
   Done when: two Claude accounts and Codex show live numbers that agree with `/usage`, and disabling Antigravity's source shows "unavailable" without errors.
4. **Agent status.** Claude Code hooks for running/waiting/done; click jumps to the terminal; GitHub Actions status.
   Done when: a real Claude Code task shows the three states in order and a click focuses its window.
5. **Media and Shelf.** Now Playing via adapter, HUD replacement, file shelf with AirDrop, clipboard history.
   Done when: music from Spotify and Music.app shows with controls, and the module turns itself off cleanly when MediaRemote is unavailable.
6. **Designer shelf and Meeting mode.** Screenshot to shelf, annotate, color picker; next meeting, Join, mic/camera status, auto DND.
   Done when: a screenshot lands on the shelf instead of the Desktop, and a calendar event with a Meet link shows Join 5 min before.
7. **Release.** Onboarding (permissions explained per module), Sparkle feed, DMG, app icon, website.
   Done when: a fresh Mac installs from the DMG and updates via Sparkle.
