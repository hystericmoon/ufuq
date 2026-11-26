# Progress

Last updated: 2026-11-26

## Resume here (paused 2026-11-26 15:25)

Auto-update: Mac (Sparkle) and Windows (signed MSI) are merged and green. **Android updater is NOT done** — the agent was stopped before committing. Restart it:

```
Add the sideload self-updater to the Ufuq Android app: port Adwam's updater (hystericmoon/muslimdaily: app/src/main/java/id/haho/muslimdaily/update/*, feature/settings/UpdateScreen.kt, their tests, FileProvider, SELF_UPDATE/UPDATE_REPO BuildConfig) without Hilt, reusing android/core app.ufuq.core.update (Versions, GitHubReleases). Asset ufuq-<VERSION>.apk; versionName from repo-root VERSION. Release signing from secrets UFUQ_KEYSTORE_BASE64, UFUQ_KEYSTORE_PASSWORD, UFUQ_KEY_ALIAS, UFUQ_KEY_PASSWORD (debug fallback with a warning). Add .github/workflows/release-android.yml (tag v* → assembleRelease → upload to the tag's release with softprops/action-gh-release@v2) and docs/release-android.md. Settings copy: "Ufuq checks GitHub once a day for a new version. Turn this off to check only when you ask." Tests + screenshots; keep CI green.
```

Then: run `bash tools/setup_release_keys.sh` on the Mac (sets all signing secrets), merge PR #1, tag `v0.1.0`.

## Status (2026-11-26, overnight)

All code is on PR #1 (`claude/ufuqcore-phase-1-setup-php4yz`), CI green on Linux, macOS and Android. Nothing has run on a real device yet.

| Platform | Built | Verified by | You still need to check |
|---|---|---|---|
| Mac (phases 1–4 + sync server) | Core, prayer, usage parsers, notch shell, LAN sync server + pairing QR | macOS CI (build, app tests, snapshots) | List under "Check on the Mac" below; then "Pair phone…" with the Android app |
| Android (A1–A4, A6, A7) | Kotlin core, island overlay + expanded design, Live Update chip, QS tile, media page, prayer silence / mosques, Ramadan, travel, Mac pairing + AI page + agent peeks, other apps (beta) | Robolectric tests, lint, screenshots in `android/app/src/test/screenshots` | Sideload the debug APK (CI artifact `ufuq-debug-apk`); see "Check on Android" |
| Windows (W1, W2, W3 config) | Compose Desktop island, Win+Alt+Space, tray, local Claude/Codex usage, MSI config | `:desktop:test` headless + screenshots; MSI built on windows-latest CI | See "Check on Windows" |
| Wear OS | skipped by owner | | |

### Check on Android (debug APK, ~20 min)
1. Install, open, pick Jakarta; Today screen times match Adwam.
2. Live Update chip in the status bar / lock screen (Android 16); QS tile shows the next prayer.
3. Settings → island overlay → grant "Display over other apps"; pill sits at the camera cutout; tap → expanded island; swipe pages; TalkBack reads each page as one item.
4. Media: play something, grant notification access, seek and pause from page C.
5. Prayer silence: grant DND access, test with a 5-min setting; add a mosque.
6. Pair with the Mac (QR or paste code) once the Mac app runs.

### Check on Windows (~15 min)
1. Install the MSI (CI artifact; unsigned, SmartScreen will warn).
2. Pill at top centre; Win+Alt+Space opens, Esc returns focus; no taskbar/Alt+Tab entry.
3. Tray menu, launch at login.
4. **NVDA/Narrator reads the island** — biggest risk (Compose Desktop via Java Access Bridge).
5. AI page reads your real `%USERPROFILE%\.claude` and `.codex`.

### Known issues to decide or fix
- Desktop Claude % uses **made-up token budgets** (30M / 5 h, 300M / week, editable in Settings) and is labelled "estimated". Proposal: show tokens used, no %, until the live limit source is verified (Phase 5).
- Slider hides the trailing text (reset time, media position) when it would straddle the handle; it stays in the TalkBack/Narrator description. Needs a design decision (move it outside the track?).
- Island UI is duplicated in `:app` and `:desktop`; extract a KMP `:island-ui` module.
- Sync auth header can be replayed within its 5-min window on the same Wi-Fi (read-only data). Add a nonce cache.
- Mac doesn't emit agent events yet (Phase 6); Android derives them from snapshots.
- Ramadan: Adwam has no Imsak (owner decision 19 Nov); Android shows "Sahur" at Subuh. Add a Kemenag Imsak offset only if you want it.
- Code-signing: Windows needs a certificate; Mac needs Developer ID + notarization (Phase 9).

## Next up

**Phase 4 — Notch shell: code done, Mac check pending.** Built and tested on GitHub's macOS runner (`.github/workflows/mac.yml`). Never run on a real Mac yet.

Check on the Mac (about 15 min), then fix what fails:
1. `brew install xcodegen && xcodegen generate && open Ufuq.xcodeproj`, run.
2. Panel sits over the notch, above the menu bar; left wing shows the real next prayer.
3. ⌥Space opens it, VoiceOver focus lands inside, Tab reaches the tabs with a visible ring, Esc closes and returns focus to the previous app.
4. External display: floating pill 8 pt below the menu bar.
5. Reduce Motion cross-fade; Increase Contrast border; hover toggle; launch at login (may refuse on an unsigned debug build).
6. Compare the `snapshots` artifact PNGs with `refs/` and the design canvas.

Deviation to judge: collapsed width on notch screens is `max(300, notch + 2×90)` (≈368 pt on a 14" MBP), because 300 leaves ~56 pt per wing, too narrow for "Ashar 15:12". The spec says 300.

Then Phase 5 (Prayer + AI UI) on the Mac.

Open items from the cloud phases:
- Phase 2: the Kemenag check covers 21 cities but only 7 Jakarta days (the plan asked for 30). It is within 1 minute everywhere. To close it, add a full Jakarta month from bimasislam.kemenag.go.id to `Tests/UfuqCoreTests/Fixtures/kemenag_official.tsv` (never hand-typed).
- Phase 3: every log field name is an assumption. Verify on real files in Phase 5 (list in "Done in Phase 3").

First prompt to type (Mac session):

```
Finish Phase 4 from docs/plan.md on this Mac. Read CLAUDE.md and docs/progress.md ("Check on the Mac") first.
Generate the project with XcodeGen, run the app, and go through the check list; fix anything that fails (keep the macOS CI green).
Then start Phase 5 if time remains. Update docs/progress.md before finishing.
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

- 2026-11-26 (night): Android A1–A4, A6, A7 and Windows W1–W2 built in cloud with parallel agents; Mac sync server; Wear OS skipped. CI green on all three platforms; device checks pending.

- 2026-11-26: Phase 4 code written in cloud and verified on the macOS CI runner (build + 23 tests + snapshots); real-Mac check pending.

- 2026-11-26: Phases 2 and 3 done in cloud (parallel agents), parser hardening review, CI (`.github/workflows/core.yml`). 123 tests green. Decided: Ufuq replaces Adwam's island on Android later (spec, Open questions).

- 2026-11-26: Phase 1 done: `UfuqCore` skeleton, 40 tests green on Linux (Swift 6.4.3).

- 2026-11-26: Plan reordered so cloud sessions build the `UfuqCore` package first (phases 1–3); Mac-only work moved to phases 4+.
- 2026-11-26: Kickoff. Features, mockups ([design canvas](https://claude.ai/artifact/4HsAKmFv7udUHpofxCsYpi)) and [product spec](https://claude.ai/artifact/TaMXyaqrAM7SMdM7UnRyio) done; name chosen (Ufuq); repo scaffolded with CLAUDE.md, docs, UI rules and start-up hook.
