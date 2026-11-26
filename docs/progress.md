# Progress

Last updated: 2026-11-26

## Next up

**Phase 4 — Notch shell (Mac).** Needs a Mac with Xcode; the cloud phases (1–3) are done. See `docs/plan.md`.

Open items from the cloud phases:
- Phase 2: the Kemenag check covers 21 cities but only 7 Jakarta days (the plan asked for 30). It is within 1 minute everywhere. To close it, add a full Jakarta month from bimasislam.kemenag.go.id to `Tests/UfuqCoreTests/Fixtures/kemenag_official.tsv` (never hand-typed).
- Phase 3: every log field name is an assumption. Verify on real files in Phase 5 (list in "Done in Phase 3").

First prompt to type (Mac session):

```
Start Phase 4 from docs/plan.md. Read CLAUDE.md, docs/spec.md (Notch states, Architecture, Accessibility) and docs/progress.md first.
Create the Xcode project Ufuq (macOS 14, not sandboxed) importing the local UfuqCore package. Build the NSPanel over the notch with collapsed/peek/expanded states driven by ActivityArbiter and PeekQueue, ⌥Space hotkey with focus in and Esc back, optional hover, floating pill on non-notch displays, launch at login. Wire PrayerModule into the left wing.
Fill in the Mac build/test commands in CLAUDE.md. Update docs/progress.md before finishing.
```

## Done in Phase 1

- `UfuqCore/` package (swift-tools 5.9, macOS 14, Foundation only). `swift test`: 40 tests green on Linux.
- `UfuqModule` (UI-free; throwing `refresh`/`collapsedActivity`). The Mac app adds `expandedView()`/`settingsView()` in a SwiftUI protocol that refines it.
- `ModuleStatus`, `LiveActivity` (source, isAlert, deadline, usageFraction), `PeekEvent` (normal/critical, 6 s, VoiceOver announcement).
- `ModuleRegistry`: duplicate ids rejected; a throwing module becomes `.unavailable(reason)` until its next good refresh; others keep working.
- `ActivityArbiter`: prayer left, AI right; empty home wing takes the top remaining activity; the rest rotate every 8 s in priority order; an alert pins the rotating slot.
- `PeekQueue`: FIFO per priority; critical jumps waiting normals and preempts a showing normal (which returns first, full duration); hover holds; Esc dismisses; same id replaces.
- `UsageThresholds` (80/95, crossing and reset alerts; 95% maps to a critical peek) and `BurnRate.estimate` (least squares over the last hour of the current window, needs 5 min of samples; says whether the limit hits before reset).

## Done in Phase 2

- Prayer engine ported from Adwam (Meeus solar math; Adwam's Adhan library dependency was re-implemented): Kemenag default (20°/18°, ihtiyat, rounding, elevation dip), MWL, Umm al-Qura, custom angles, Hanafi Asr, high-latitude fallback, offsets.
- `PrayerSnapshots` (next prayer, countdown, Jumat), `HijriCalendar` (Foundation Umm al-Qura), `Timetable`, `PrayerWindows`.
- `PrayerModule` (id `prayer`): `.prayer` activity with deadline, "Ashar now" alert in the 60 s adhan window, pre-adhan peek (10 min, normal) and adhan peek (critical); no adhan peek for Terbit.
- Not ported: Qibla, iqamah offsets, Imsak (not in Adwam either).

## Done in Phase 3

- `ClaudeLogParser` (`<config>/projects/**/*.jsonl`, dedupe by message id + request id, 5-hour blocks and rolling 7 days), `CodexParser` (latest `token_count` rate-limit snapshot), `ClaudeLimitSource` protocol + estimate fallback (`isEstimated`), `UsageSummary.worst`.
- Hardened after review: saturating token sums, streaming per file with a 256 MB tail cap, partial last line ignored, BOM, deep nesting, epoch timestamps, tilde dirs, future-dated snapshots.
- To verify on a Mac: Claude fields `type`, `timestamp`, `requestId`, `message.id`, `message.usage.*`; block rule vs real resets; Codex path, `payload.type == "token_count"`, `rate_limits.primary/secondary.used_percent`, `window_minutes`, `resets_in_seconds`/`resets_at`; Claude live-limit endpoint (only a fake exists); token budgets for the estimate.

## History

- 2026-11-26: Phases 2 and 3 done in cloud (parallel agents), parser hardening review, CI (`.github/workflows/core.yml`). 123 tests green. Decided: Ufuq replaces Adwam's island on Android later (spec, Open questions).

- 2026-11-26: Phase 1 done: `UfuqCore` skeleton, 40 tests green on Linux (Swift 6.4.3).

- 2026-11-26: Plan reordered so cloud sessions build the `UfuqCore` package first (phases 1–3); Mac-only work moved to phases 4+.
- 2026-11-26: Kickoff. Features, mockups ([design canvas](https://claude.ai/artifact/4HsAKmFv7udUHpofxCsYpi)) and [product spec](https://claude.ai/artifact/TaMXyaqrAM7SMdM7UnRyio) done; name chosen (Ufuq); repo scaffolded with CLAUDE.md, docs, UI rules and start-up hook.
