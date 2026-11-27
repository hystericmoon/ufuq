# Ufuq — Spec

Ufuq is a macOS notch app that shows prayer times and AI usage limits at the top edge of the screen. Its core is small and it looks native like Alcove. On top of that it adds modules no other notch app has: prayer times, multi-account AI quota tracking, and agent status.

Source docs: [Product spec (Claude Doc)](https://claude.ai/artifact/TaMXyaqrAM7SMdM7UnRyio) · [Design canvas](https://claude.ai/artifact/4HsAKmFv7udUHpofxCsYpi)

## Scope

| Item | Value |
| --- | --- |
| Name | Ufuq (Arabic أفق, "horizon"; Indonesian *ufuk*) |
| Bundle ID | `app.ufuq.mac` (placeholder until the domain is confirmed) |
| Platform | macOS 14+, Apple Silicon and Intel |
| Stack | Swift, SwiftUI, AppKit `NSPanel` |
| Distribution | Ad-hoc signed DMG + Sparkle (no Apple Developer account); not sandboxed |

## Non-goals

- No Mac App Store build (sandbox blocks reading `~/.claude*` and `~/.codex`).
- No Linux version. (Windows and Android were added 2026-11-26; see `docs/plan.md`.)
- No cloud backend or account system; everything runs locally.
- Not a full clipboard manager or file manager: 10 clipboard items, a simple shelf.

## Notch states

- **Collapsed** (300×32 pt; on notch screens `max(300, notch + 2×90)`, ≈368 pt): two wings beside the camera. Left = prayer, right = AI. A third activity rotates every 8 s.
- **Peek** (352×92 pt): one alert at a time, auto-dismisses after 6 s, hover holds it. 95% limits and adhan jump the queue.
- **Expanded** (bento, owner pick 27 Nov 2026, design canvas option A): the collapsed wings stay in a black strip at the notch; below it a Liquid Glass body (macOS 26; dark material on 14–15; solid black under Reduce Transparency or Increase Contrast) holds Prayer (216 pt) and AI (248 pt) as tall tiles and the small tiles (144 × 112 pt) in columns of two. Sized to content: only live tiles show, so the width is 496 pt with Prayer + AI and 952 pt with six small tiles. No tabs; Tab and ←/→ move between tiles. Opened by hover (optional) or the global hotkey (default ⌥Space).
- Every state returns to collapsed: peek → 6 s or Esc; expanded → mouse leaves or Esc.
- Wing priority: active alert > prayer under 10 min > AI at 80% or more > agent task running > Now Playing > other.
- Non-notch displays: the same states, hanging from the top edge of the screen like a notch: centred over the middle of the menu bar, collapsed 300 pt wide and as tall as the menu bar (at least 24 pt).
- Full-screen apps: hidden by default; peeks still show (toggle).

## Modules

### 1. Core (phase 1)
- Notch window, the three states, hotkey, floating pill, launch at login
- Battery/charging and AirPods/Bluetooth connect alerts; timers and focus sessions as live activities

### 2. Prayer (phase 2)
- Collapsed: prayer name on the left, countdown on the right; switches to mm:ss under 10 min
- Expanded: large countdown and today's six times (Subuh, Terbit, Dzuhur, Ashar, Maghrib, Isya), with the next one highlighted
- Method and madhab, Kemenag by default; system location or a manual city; works offline
- Pre-adhan peek (default 10 min before) with a "Mute media" action; optional adhan audio and auto-mute
- Hijri date; Ramadan mode with imsak and iftar countdowns
- Port the calculation from Adwam (hystericmoon/muslimdaily)

### 3. AI usage (phase 3)
- Claude, multiple accounts: 5-hour session % and weekly %, with reset countdowns
- Which account the active Claude Code session uses; one-tap "Use in Claude Code"
- Codex: 5-hour and weekly %; Antigravity: quota per model group
- Burn rate ("At this pace: session limit in 38 min"); peeks at 80%, 95% and on reset
- Refresh button and "Updated N s ago"

### 4. Agent status (phase 4)
- Claude Code / Codex tasks: running, waiting for input, done; "needs input" pulse; click jumps to the window
- GitHub Actions status for watched repos; finish summary (duration, tokens)

### 5. Media and Shelf (phase 5)
- Now Playing with controls, album-art tint, AirPlay picker
- System HUDs replaced (volume, brightness, keyboard backlight)
- File shelf (drag in/out, AirDrop, Quick Look); clipboard history (10 items, pin)

### 6. Designer shelf and Meeting mode (phase 6)
- Screenshots to the shelf, quick annotation, color picker (HEX/RGB/OKLCH/Tailwind), send to Claude
- Next meeting with a Join button, mic/camera status and toggles, camera mirror, auto DND

## Data sources

| Module | Source | Risk | Mitigation |
| --- | --- | --- | --- |
| Prayer | Local astronomical calculation + CoreLocation | Low | Unit-test against Kemenag Jakarta times |
| Claude tokens | Claude Code local logs per account config dir | Low | Defensive JSONL parsing |
| Claude limits | Internal endpoint read by `/usage`; undocumented | Medium | Version-check; fall back to an estimate labelled "estimated" |
| Claude accounts | One `CLAUDE_CONFIG_DIR` per account | Low | User adds accounts by config dir |
| Codex | Local session logs under `~/.codex` (rate-limit snapshots expected) | Medium | Spike first |
| Antigravity | No known public API; local state or language server | High | Isolated plugin, "Beta source", fails to "unavailable" |
| Now Playing | MediaRemote, restricted since macOS 15.4 | High | Adapter (e.g. mediaremote-adapter); module can be disabled |
| HUDs | Media key interception | Medium | Accessibility permission, explained in onboarding |
| Agent status | Claude Code hooks / log tail; Codex logs | Medium | Hooks over polling |
| GitHub Actions | REST API + user token | Low | Token in Keychain |
| Meeting | EventKit + mic/camera in-use state | Low | Ask permission on enable |

Every field name and endpoint above is an assumption to verify in a spike before building its UI.

## Architecture

```swift
protocol UfuqModule: Identifiable {
    var id: String { get }
    var title: String { get }
    var isEnabled: Bool { get set }
    var status: ModuleStatus { get }          // .ok, .stale(Date), .unavailable(reason)
    func collapsedActivity() -> LiveActivity?
    func peekEvents() -> AsyncStream<PeekEvent>
    func expandedView() -> AnyView
    func settingsView() -> AnyView
    func accessibilitySummary() -> String
}
```

- In `UfuqCore` the protocol is UI-free (no `AnyView`): `refresh()` and `collapsedActivity(at:)` throw, and the Mac app adds the two view methods in a SwiftUI protocol that refines it.
- **NotchController**: the `NSPanel`, its state, and positioning per screen
- **ActivityArbiter**: chooses what goes in each wing and rotates a third activity
- **PeekQueue**: one peek at a time; critical alerts jump the queue
- **ModuleRegistry**: loads modules, catches their errors, reports status
- **Settings**: one page with one collapsible section per module; `UserDefaults` for settings, Keychain for tokens
- **Permissions**: asked only when the module that needs one is turned on (Location, Accessibility, Calendar, Screen Recording)

## Accessibility

- The hotkey opens the panel and moves focus into it; Esc closes it and returns focus. Tab and arrow keys move between controls, with a visible focus ring.
- Each live activity is one accessibility element with a spoken summary ("Claude Work, 82 percent of session, resets in 1 hour 12 minutes").
- Peeks post VoiceOver announcements (high priority for 95% and adhan).
- Color always comes with a number or a label; provider colors differ in lightness.
- Text contrast on black: #FFFFFF, #A1A1A6, #8E8E93. Never darker grey.
- Reduce Motion: cross-fade instead of the morph animation, no pulses. Increase Contrast: thicker strokes and borders.

## Visual tokens

| Token | Value |
| --- | --- |
| notch.bg | #000000 |
| card.bg | #141416 |
| control.bg | #1C1C1F |
| track | #2A2A2E |
| text.primary / secondary / muted | #FFFFFF / #A1A1A6 / #8E8E93 |
| accent.prayer | #4FD1A5 |
| provider.claude / codex / antigravity | #D97757 / #E5E5EA / #6E9BFF |
| state.warning / critical | #FFB340 / #FF6B5E |
| android.accent.container / on-accent / track | #A8D8B9 / #0F3D25 / #26302A (Android expanded island) |
| Radius | 14 collapsed, 22 peek, 28 expanded |
| Type | SF Pro: 13/600 collapsed and row titles, 26/700 title, 44/600 countdown, 11/600 tile label (uppercase), 12/600 small value, 11/400 caption, 10/600 ring %; tabular numbers |
| Open panel | padding 12, gap 8, tile padding 12, tile radius 16 (concentric with 28), tile fill white 8% (card.bg on solid), glass tint black 45% |

## Open questions

- Domain (`ufuq.app`, `getufuq.app`)? The bundle ID follows from it.
- Free and open source, or paid one-time?
- Does Claude Code run only on this Mac, or also on the Windows machine (for agent status)?
- Hijri source: calculated (Umm al-Qura) or Kemenag announcements?
- App icon and wordmark.
- Android version (later). Decided 2026-11-26: Ufuq replaces Adwam's island/notch on Android; Adwam keeps duas, routines and its widget. Order: ship Ufuq for Android first, then an Adwam release removes its island and points users to Ufuq. Open: AI usage on Android needs a sync from the Mac (the logs live there); prayer settings are set in both apps unless Ufuq reads Adwam's. Leaning: port `UfuqCore` to Kotlin using its Swift tests as the spec, rather than KMP or the Swift SDK for Android.
