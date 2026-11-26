# Ufuq for Android

Gradle project (`android/`). Only the pure-Kotlin `:core` module exists so far; the app module comes next.

## `:core` (`app.ufuq.core`)

A Kotlin/JVM library with no Android dependency, so `./gradlew :core:test` runs in seconds on any machine with a JDK 17+.
It is a port of `UfuqCore` (Swift) using the Swift tests as the spec: `Models`, `UfuqModule`, `ModuleRegistry`,
`ActivityArbiter`, `PeekQueue`, `Usage`, `UsageModel`, and `PrayerModule`.

Differences from the Swift package, by design:

- **Claude and Codex log parsers** are in `app.ufuq.core.usage` (ported with the Swift tests). Windows reads the logs
  directly; Android gets usage by a sync from the Mac (plan A6), so the Android app does not use them.
- **Prayer is not a port of the Swift prayer code.** `app.ufuq.core.prayer` is copied from Adwam
  (`id.haho.muslimdaily.domain.prayer`), which uses the `adhan2` library and is calibrated against the Kemenag schedule
  (`KemenagReferenceTest`). Android prayer times may therefore differ from the Mac by a minute until the Mac side converges.
- Time is `java.time` (`Instant`, `Duration`, `LocalDate`, `ZoneId`); the Swift `CivilDate` has no counterpart.
- `UfuqModule.peekEvents()` is a `Flow` (Swift: `AsyncStream`).

Adwam's `CalculationSettings` and prayer types were copied without Hilt and without the Adwam settings classes.
