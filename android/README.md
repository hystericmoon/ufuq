# Ufuq for Android

Gradle project (`android/`). Only the pure-Kotlin `:core` module exists so far; the app module comes next.

## `:core` (`app.ufuq.core`)

A Kotlin/JVM library with no Android dependency, so `./gradlew :core:test` runs in seconds on any machine with a JDK 17+.
It is a port of `UfuqCore` (Swift) using the Swift tests as the spec: `Models`, `UfuqModule`, `ModuleRegistry`,
`ActivityArbiter`, `PeekQueue`, `Usage`, `UsageModel`, and `PrayerModule`.

Differences from the Swift package, by design:

- **Not ported: the Claude and Codex log parsers** (`ClaudeLogParser`, `CodexParser`, `FileSource`, `ClaudeLimitSource`,
  `UsageEstimate`, `ClaudeUsageResolver`). The logs live on the Mac. Android will get usage by a sync from the Mac later;
  `UsageModel` and `Usage` (thresholds, alerts, burn rate) are ported because the UI needs them.
- **Prayer is not a port of the Swift prayer code.** `app.ufuq.core.prayer` is copied from Adwam
  (`id.haho.muslimdaily.domain.prayer`), which uses the `adhan2` library and is calibrated against the Kemenag schedule
  (`KemenagReferenceTest`). Android prayer times may therefore differ from the Mac by a minute until the Mac side converges.
- Time is `java.time` (`Instant`, `Duration`, `LocalDate`, `ZoneId`); the Swift `CivilDate` has no counterpart.
- `UfuqModule.peekEvents()` is a `Flow` (Swift: `AsyncStream`).

Adwam's `CalculationSettings` and prayer types were copied without Hilt and without the Adwam settings classes.
