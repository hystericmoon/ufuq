# Progress

Last updated: 2026-11-27

## Resume here (2026-11-27, 16:00 WIB)

Released: v0.1.0 to v0.1.3 and v0.2.0 (https://github.com/hystericmoon/ufuq/releases/tag/v0.2.0). Release steps: bump `VERSION` + `project.yml` `MARKETING_VERSION`, merge, then run `release-mac.yml`, `release-windows.yml`, `release-android.yml` by hand (workflow_dispatch on `main`); tags cannot be pushed from cloud sessions.
Phase 5 (Mac AI tile) merged in PR #9, not released yet. `AIUsageModule` in UfuqCore reads every Claude account (`~/.claude`, `~/.claude-*`, `CLAUDE_CONFIG_DIR`) as tokens in the current 5-hour block (no %, no amber/red, no alerts; owner decision 27 Nov), and Codex only when `~/.codex/sessions` exists. Owner does not use Codex (27 Nov): no Codex row, and Phase 5's "Codex shows numbers" done-when is dropped.
Claude JSONL fields verified on real Claude Code logs (27 Nov): `type`, `timestamp`, `requestId`, `message.id`, `message.usage.*`; ~45% of assistant lines repeat a (message id, request id) pair with identical usage, deduped once. No limit data is in the logs.
Phase 6 (agent status, Claude Code hooks) merged in PR #12, not released. Design: `docs/agent-status.md`. `ufuq-hook` (embedded at `Ufuq.app/Contents/MacOS/ufuq-hook`) writes one state file per session in `~/Library/Application Support/Ufuq/agents/`; `AgentStatusModule` refreshes every 1 s: wing "Needs input" (pinned, pulsing dot) / "ufuq · 4m" / "ufuq done", peeks "Claude needs input" (critical) and "Task done" (turns ≥30 s), Agents tile (click opens the session's terminal app), phone sync gets `agents`. Hooks install only from Settings → Agent status (per account, backup `settings.json.ufuq-backup`). Known limit: parallel tool calls can clear "Needs input" early (PermissionRequest has no tool_use_id).
Next: (1) owner on the Mac: AI tile numbers vs `/usage` for each account; collapsed wing "Claude 4.2M"; Settings → Agent status → Install, restart a Claude Code session, then check running / needs input (trigger a permission prompt) / done peek and the tile click; (2) release 0.3.0 (Phase 5 + 6) once the owner agrees; (3) follow-up: the AI module re-parses every log each minute; skip files older than the 7-day window (needs mtime in `FileSource`); (4) Phase 6b (GitHub Actions status, `docs/github-actions.md`) merged in PR #13: owner on the Mac checks Settings → GitHub Actions ("Using gh (login)"), the Actions tile and a "CI failed" peek; (5) collapsed right wing now shared (PR #14): owner checks "82%" and the agent/CI text take 8 s turns and "Needs input" pins.

0.2.0 (released 27 Nov) carried:
- Mac open panel = **bento, design canvas option A** (owner pick 27 Nov, https://claude.ai/artifact/PpqkyeEQu7EhFj8gxvRD1j): black strip with the wings at the notch; Prayer (216 pt) and AI (248 pt) tall tiles; small tiles 144×112 in columns of two (Battery only so far, IOKit). Sized to live tiles (496 pt, 648 with battery). Liquid Glass on macOS 26, dark material on 14–15, solid under Reduce Transparency / Increase Contrast. Tabs removed; Tab/←→ move between tiles. CI and release build with Xcode 26 (26.3 on macos-15). AI tile shows "No usage yet" until the usage readers are wired (Phase 5).
- Android: Home is the settings (no Today screen). Next-prayer status card, then Island & notification / Mac / Prayer / About cards; location, method, reminder, silence, other apps and Mac open sub-screens (back stack).
- CLAUDE.md: delegate lighter work to Haiku/Sonnet sub-agents (owner, 27 Nov).

Next:
1. Owner checks on 0.2.0: Mac panel on macOS 26 (glass over a light wallpaper: is text readable?) and on 14–15; Tab/arrows/Esc; Android Home, sub-screens, Back, permission round-trips.
2. Phase 5: see Resume here.

Owner rule (CLAUDE.md): do every step you can yourself (merge, workflows, CI fixes, releases); only device checks, local keys and decisions go to the owner.

## Status (2026-11-26, overnight)

All code is on PR #1 (`claude/ufuqcore-phase-1-setup-php4yz`), CI green on Linux, macOS and Android. Nothing has run on a real device yet.

| Platform | Built | Verified by | You still need to check |
|---|---|---|---|
| Mac (phases 1–4 + sync server) | Core, prayer, usage parsers, notch shell, LAN sync server + pairing QR | macOS CI (build, app tests, snapshots) | List under "Check on the Mac" below; then "Pair phone…" with the Android app |
| Android (A1–A4, A6, A7) | Kotlin core, island overlay + expanded design, Live Update chip, QS tile, media page, prayer silence / mosques, Ramadan, travel, Mac pairing + AI page + agent peeks, other apps (beta) | Robolectric tests, lint, screenshots in `android/app/src/test/screenshots` | Sideload the debug APK (CI artifact `ufuq-debug-apk`); see "Check on Android" |
| Windows (W1, W2, W3 config) | Compose Desktop island, Win+Alt+Space, tray, local Claude/Codex usage, MSI config | `:desktop:test` headless + screenshots; MSI built on windows-latest CI | See "Check on Windows" |
| Wear OS | skipped by owner | | |

### Check on Android (~25 min; the debug APK works for 1–6, step 7 needs the release APK)
1. Install, open, pick Jakarta; Today screen times match Adwam.
2. Live Update chip in the status bar / lock screen (Android 16); QS tile shows the next prayer.
3. Settings → island overlay → grant "Display over other apps"; pill sits at the camera cutout; tap → expanded island; swipe pages; TalkBack reads each page as one item.
4. Media: play something, grant notification access, seek and pause from page C.
5. Prayer silence: grant DND access, test with a 5-min setting; add a mosque.
6. Pair with the Mac (QR or paste code) once the Mac app runs.
7. Updates: Settings → About → Updates shows 0.1.0; after a newer release exists, Check → Download → Install (allow "Install unknown apps" once); app reopens on the new version.

### Check on Windows (~15 min)
1. Install the MSI (CI artifact; unsigned, SmartScreen will warn).
2. Pill at top centre; Win+Alt+Space opens, Esc returns focus; no taskbar/Alt+Tab entry.
3. Tray menu, launch at login.
4. **NVDA/Narrator reads the island** — biggest risk (Compose Desktop via Java Access Bridge).
5. AI page reads your real `%USERPROFILE%\.claude` and `.codex`.

### Known issues to decide or fix
- Island UI is duplicated in `:app` and `:desktop`; extract a KMP `:island-ui` module.
- Mac doesn't emit agent events yet (Phase 6); Android derives them from snapshots.
- Mac stays ad-hoc signed: no Apple Developer account (owner, 27 Nov). First open needs System Settings → Privacy & Security → Open Anyway. The Keychain asked again after each update (owner, v0.1.1), so the sync key now lives in `~/Library/Application Support/Ufuq/sync-key` (0600); the old Keychain item is moved once and deleted.
- Windows code-signing certificate: optional, removes the SmartScreen warning.

## Next up

**Phase 4 — Notch shell: code done, Mac check pending.** Built and tested on GitHub's macOS runner (`.github/workflows/mac.yml`). Never run on a real Mac yet.

Check on the Mac (about 15 min), then fix what fails:
1. `brew install xcodegen && xcodegen generate && open Ufuq.xcodeproj`, run.
2. Panel sits over the notch, above the menu bar; left wing shows the real next prayer.
3. ⌥Space opens it, VoiceOver focus lands inside, Tab reaches the tabs with a visible ring, Esc closes and returns focus to the previous app.
4. External display: the island hangs from the top edge, centred over the menu bar, as tall as the menu bar (changed 27 Nov after the owner's v0.1.1 check; was 8 pt below it).
5. Reduce Motion cross-fade; Increase Contrast border; hover toggle; launch at login (may refuse on an unsigned debug build).
6. Compare the `snapshots` artifact PNGs with `refs/` and the design canvas.

Collapsed width on notch screens is `max(300, notch + 2×90)` (≈368 pt on a 14" MBP) so "Ashar 15:12" fits a wing; kept by owner decision 27 Nov.

Then Phase 5 (Prayer + AI UI) on the Mac.

Open items from the cloud phases:
- Phase 2: the Kemenag check covers 21 cities but only 7 Jakarta days (the plan asked for 30). It is within 1 minute everywhere. To close it, add a full Jakarta month from bimasislam.kemenag.go.id to `Tests/UfuqCoreTests/Fixtures/kemenag_official.tsv` (never hand-typed).
- Phase 3: Claude log fields verified on real files (27 Nov). Codex fields stay unverified (owner has no Codex).

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

## Decisions (27 Nov 2026, owner took every recommendation)

- Claude shows **tokens used in the 5-hour block, no %** until its live limit is verified (Phase 5). Done on Windows (no budgets setting, no amber/red, no alerts, plain track); the Mac AI page must follow it.
- The slider's trailing text (reset time, media length) sits **on a caption line under the track**, right-aligned to its end; AI resets read "Resets in 1:12". Android island 104 → 116 dp, Windows 112 → 124 dp.
- Mac collapsed width stays ≈368 pt (not the spec's 300).
- Ramadan keeps "Sahur" at Subuh; no Imsak.
- No Apple Developer account: the Mac app stays ad-hoc signed.
- Mac island on every display (owner ask, 27 Nov): one panel per display with the same wings and peeks; the expanded panel opens on one display (pointer's display for ⌥Space, the touched one for click/hover). Setting "Show the island on every display", default on.
- Pairing QR is now a `ufuq://pair#<base64url JSON>` link: the phone camera opens Ufuq with the code filled in; the user still taps Pair. Bare JSON still parses.

## History

- 2026-11-27 (afternoon): v0.2.0 released (Mac bento, Android settings home). Phase 5 Mac AI tile merged (PR #9).
- 2026-11-27 (afternoon): 0.1.3: one Android notification, live-only island rows, place names. Mac revamp waits on a reference design.

- 2026-11-27 (afternoon): v0.1.2 released: Android and Windows open island option C, pill countdown, Mac sync key file, menu-bar island on external screens, paired-phone line.

- 2026-11-27 (morning): v0.1.1 released (Mac every-display island, faster Settings, pairing link; Windows tokens; reset caption). Owner tested 0.1.1; feedback fixes in PR #4. CI: Robolectric runtimes now resolved by Gradle, tests run offline.

- 2026-11-27: v0.1.0 released (DMG, MSI, APK; release workflows started by hand because tags cannot be pushed from cloud sessions, so the `v0.1.0` tag still points at the kickoff commit). v0.1.1 carries the four decisions and the Mac release-script fix.

- 2026-11-26 (late): Sync replay fix: the Mac server accepts each auth token once (`SyncReplayGuard`, keyed on the decoded bytes, entries expire with the 5-min window, capped at 4096). No Android change: it already seals a fresh token per request.

- 2026-11-26 (night): Android A1–A4, A6, A7 and Windows W1–W2 built in cloud with parallel agents; Mac sync server; Wear OS skipped. CI green on all three platforms; device checks pending.

- 2026-11-26: Phase 4 code written in cloud and verified on the macOS CI runner (build + 23 tests + snapshots); real-Mac check pending.

- 2026-11-26: Phases 2 and 3 done in cloud (parallel agents), parser hardening review, CI (`.github/workflows/core.yml`). 123 tests green. Decided: Ufuq replaces Adwam's island on Android later (spec, Open questions).

- 2026-11-26: Phase 1 done: `UfuqCore` skeleton, 40 tests green on Linux (Swift 6.4.3).

- 2026-11-26: Plan reordered so cloud sessions build the `UfuqCore` package first (phases 1–3); Mac-only work moved to phases 4+.
- 2026-11-26: Kickoff. Features, mockups ([design canvas](https://claude.ai/artifact/4HsAKmFv7udUHpofxCsYpi)) and [product spec](https://claude.ai/artifact/TaMXyaqrAM7SMdM7UnRyio) done; name chosen (Ufuq); repo scaffolded with CLAUDE.md, docs, UI rules and start-up hook.
