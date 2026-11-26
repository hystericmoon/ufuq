# Ufuq

## Goal

A macOS notch app (Dynamic Island-style) with native polish and a small core. Main modules: prayer times and multi-account AI usage limits (Claude, Codex, Antigravity). Later: agent status, media/shelf, designer shelf, meeting mode. Full spec: `docs/spec.md`.

## Decisions

- **Swift + SwiftUI, AppKit `NSPanel` for the notch window.** SwiftUI alone can't place a borderless panel above the menu bar.
- **macOS 14+, Apple Silicon and Intel.** Same floor as the leading notch apps; keeps modern SwiftUI APIs available.
- **Not sandboxed; notarized DMG + Sparkle; no Mac App Store.** The AI usage module must read `~/.claude*` and `~/.codex`, which the sandbox blocks.
- **Logic lives in the `UfuqCore` Swift package (Foundation only); the Mac app imports it.** Work starts in Linux cloud sessions with no Xcode, and keeping logic UI-free lets `swift test` run anywhere.
- **Every module implements `UfuqModule` and is loaded by `ModuleRegistry`.** Several data sources are undocumented (Claude limits, Codex logs, Antigravity, MediaRemote); one breaking must show "unavailable", never crash the app.
- **Collapsed AI indicator = one ring per provider + worst % as text.** Chosen on the design canvas: all providers visible without opening the panel.
- **Prayer in the left wing, AI in the right; a third activity rotates every 8 s.** Fixed positions build habit; notch width stays constant.
- **Usage thresholds: amber at 80%, red at 95%.** Also the two peek-alert points.
- **Prayer: local calculation, Kemenag method by default.** Works offline; primary user is in Jakarta. Port the logic from Adwam (hystericmoon/muslimdaily).
- **Hotkey always opens the panel; hover is optional.** Keyboard and VoiceOver users must never depend on the pointer.
- **Antigravity is an isolated plugin labelled "Beta source".** No public API; its source is the most fragile.

## Commands

Core package (Linux or Mac), from `UfuqCore/`:

- Build: `swift build`
- Test: `swift test`

Mac app (Xcode required). Fill in once the Mac phase creates the project:

- Build: `xcodebuild -scheme Ufuq -configuration Debug build`
- Test: `xcodebuild -scheme Ufuq test`

## Pointers

- Spec: `docs/spec.md`
- Plan: `docs/plan.md`
- Design canvas and refs: `refs/README.md`
- UI rules: `.claude/rules/ui.md`
- Tracker: docs/progress.md
