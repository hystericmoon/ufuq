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

## `:desktop` (`app.ufuq.desktop`)

The Windows app (plan W1/W2): Compose Multiplatform Desktop on top of `:core`. A floating top-centre pill (300x32 dp), peek (352x92) and the expanded island, driven by a pure state machine (port of the Mac's `NotchState`). Win+Alt+Space (JNativeHook, Windows only), Esc returns focus, tray icon, launch at login (HKCU Run key), settings window, and real AI usage read from `%USERPROFILE%\.claude*` and `.codex` through the `:core` parsers (Claude falls back to an "estimated" figure).

Island UI is duplicated in :app and :desktop; extract to a KMP :island-ui module later.

`:desktop` pins `kotlinx-datetime` to 0.5.0: Compose Material3 pulls 0.7.1, which breaks adhan2 0.0.5 (every prayer time would fail with `NoSuchMethodError`).

