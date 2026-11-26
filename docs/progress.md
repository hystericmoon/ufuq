# Progress

Last updated: 2026-11-26

## Next up

**Phase 2 — Prayer engine (cloud)** (see `docs/plan.md`). Linux cloud session; attach `hystericmoon/muslimdaily`.
Toolchain: if `swift` is missing, install with swiftly (`curl -sSL https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz | tar xz && ./swiftly init --assume-yes`, then `. ~/.local/share/swiftly/env.sh`, then `apt-get install -y libcurl4-openssl-dev libxml2-dev libz3-dev`). Phase 1 ran on Swift 6.4.3.

First prompt to type:

```
Start Phase 2 from docs/plan.md. Read CLAUDE.md, docs/spec.md (Prayer) and docs/progress.md first.
Linux cloud session: no Xcode. Install the Swift toolchain if missing (steps in docs/progress.md).
Port the prayer calculation from hystericmoon/muslimdaily into UfuqCore (Foundation only): Kemenag default, other methods and madhab, next prayer and countdown, Hijri date. Add a PrayerModule conforming to UfuqModule that emits a .prayer LiveActivity with its deadline.
Test against Kemenag's published Jakarta times (within 1 minute, 30 sampled days). Run swift test until green. Update docs/progress.md before finishing.
```

## Done in Phase 1

- `UfuqCore/` package (swift-tools 5.9, macOS 14, Foundation only). `swift test`: 40 tests green on Linux.
- `UfuqModule` (UI-free; throwing `refresh`/`collapsedActivity`). The Mac app adds `expandedView()`/`settingsView()` in a SwiftUI protocol that refines it.
- `ModuleStatus`, `LiveActivity` (source, isAlert, deadline, usageFraction), `PeekEvent` (normal/critical, 6 s, VoiceOver announcement).
- `ModuleRegistry`: duplicate ids rejected; a throwing module becomes `.unavailable(reason)` until its next good refresh; others keep working.
- `ActivityArbiter`: prayer left, AI right; empty home wing takes the top remaining activity; the rest rotate every 8 s in priority order; an alert pins the rotating slot.
- `PeekQueue`: FIFO per priority; critical jumps waiting normals and preempts a showing normal (which returns first, full duration); hover holds; Esc dismisses; same id replaces.
- `UsageThresholds` (80/95, crossing and reset alerts; 95% maps to a critical peek) and `BurnRate.estimate` (least squares over the last hour of the current window, needs 5 min of samples; says whether the limit hits before reset).

## History

- 2026-11-26: Phase 1 done: `UfuqCore` skeleton, 40 tests green on Linux (Swift 6.4.3).

- 2026-11-26: Plan reordered so cloud sessions build the `UfuqCore` package first (phases 1–3); Mac-only work moved to phases 4+.
- 2026-11-26: Kickoff. Features, mockups ([design canvas](https://claude.ai/artifact/4HsAKmFv7udUHpofxCsYpi)) and [product spec](https://claude.ai/artifact/TaMXyaqrAM7SMdM7UnRyio) done; name chosen (Ufuq); repo scaffolded with CLAUDE.md, docs, UI rules and start-up hook.
