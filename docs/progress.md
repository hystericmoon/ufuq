# Progress

Last updated: 2026-11-26

## Next up

**Phase 1 — Core skeleton (cloud)**, then Phase 2 — Prayer engine (see `docs/plan.md`). Linux cloud session: no Xcode, no AppKit/SwiftUI. Attach `hystericmoon/muslimdaily` to the session for Phase 2.

First prompt to type:

```
Start Phase 1 from docs/plan.md. Read CLAUDE.md and docs/spec.md (Notch states, Architecture) first.
Linux cloud session: no Xcode, no AppKit/SwiftUI. Install the Swift toolchain if missing.
Create the Swift package UfuqCore/ (Foundation only, swift-tools 5.9) with the UfuqModule protocol and UI-free ModuleStatus, LiveActivity, PeekEvent; ModuleRegistry, ActivityArbiter (wing priority + 8 s rotation) and PeekQueue (critical jumps the queue); usage thresholds (80/95) and a burn-rate estimate. Unit tests for each.
Run swift test until green. If time remains, continue with Phase 2 (port the prayer calculation from hystericmoon/muslimdaily).
Update docs/progress.md before finishing.
```

## History

- 2026-11-26: Plan reordered so cloud sessions build the `UfuqCore` package first (phases 1–3); Mac-only work moved to phases 4+.
- 2026-11-26: Kickoff. Features, mockups ([design canvas](https://claude.ai/artifact/4HsAKmFv7udUHpofxCsYpi)) and [product spec](https://claude.ai/artifact/TaMXyaqrAM7SMdM7UnRyio) done; name chosen (Ufuq); repo scaffolded with CLAUDE.md, docs, UI rules and start-up hook.
