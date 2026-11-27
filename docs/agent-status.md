# Agent status (Phase 6)

Shows each Claude Code session as running / waiting for input / done in the notch. Codex is out (owner does not use it). GitHub Actions status is a later sub-phase (needs a token in the Keychain).

## Flow

```
Claude Code ──hook (stdin JSON)──▶ ufuq-hook ──flock + atomic write──▶ ~/Library/Application Support/Ufuq/agents/<session>.json
                                                                                    │ read every 1 s (tiny files)
                                                     AgentStatusModule (UfuqCore) ◀─┘
                                                     ├─ LiveActivity (.agent) → rotation / pinned when waiting
                                                     ├─ PeekEvent "Claude needs input" (critical) / "Task done" (normal)
                                                     └─ [SyncAgent] → phone (SyncService.contentProvider)
```

Why the hook runs the state machine and writes one small state file per session (instead of appending events): the app polls every second, and reading a few 300-byte files is free; an event log would grow with every tool call. Prompts, tool input and assistant text are never stored.

## Hook events → state

| Hook event | Condition | New state |
|---|---|---|
| SessionStart | | `idle` (not shown); also prunes state files untouched for 24 h |
| UserPromptSubmit | | `running`, `runningSince = now` |
| PreToolUse, PostToolUse, PostToolUseFailure | state is not `ended` | `running` (keeps `runningSince`; sets it if missing) |
| PermissionRequest | | `waiting` |
| Notification | `notification_type` is `permission_prompt` or `elicitation_dialog` | `waiting` |
| Notification | any other type (`idle_prompt`, `auth_success`, …) | unchanged |
| Stop, StopFailure | | `done`, `finishedAt = now` |
| SessionEnd | | file deleted |
| anything else / unparseable | | unchanged, exit 0 |

The hook always exits 0 and prints nothing, whatever fails. Subagent events (`agent_id` present) use the same table.

## State file (`AgentSession`, JSON, sorted keys, ISO 8601)

`id` (session_id), `title` (`session_title` if given, else last path component of `cwd`), `cwd`, `state` (`idle|running|waiting|done`), `updatedAt`, `runningSince?`, `finishedAt?`, `appBundleID?` (from the hook's `__CFBundleIdentifier` env, e.g. `com.apple.Terminal`, `com.googlecode.iterm2`, `com.mitchellh.ghostty`; used by click-to-jump).

File name: session_id with every character outside `[A-Za-z0-9._-]` replaced by `_`, plus `.json`. Directory: `$UFUQ_AGENT_DIR` if set, else Application Support `Ufuq/agents`.

## Module rules (`AgentStatusModule`, id `agent`)

- Hidden: `idle`; any session not updated for 6 h (crashed sessions never send SessionEnd); `done` older than 5 min (wing only; tile and sync keep it until 6 h).
- One collapsed activity, id `agent`, source `.agent`, aggregated:
  - any waiting → text `Needs input · <title>` (`+N` when more waiting), `isAlert = true` (pins it in the rotation).
  - else any running → `<title> · 4m` (elapsed since `runningSince`, `TokenFormat`-style short), or `3 agents running`.
  - else a recent done → `<title> done`.
  - Accessibility label spells it out: "Claude Code, ufuq, needs input".
- Peeks (from comparing the previous refresh with the new one, per session):
  - → `waiting`: critical, title `Claude needs input`, message `<title>`, id `agent.waiting.<session>`.
  - `running` → `done` after ≥ 30 s of running: normal, title `Task done`, message `<title> · 4m 12s`, id `agent.done.<session>`. Shorter turns stay quiet.
  - First refresh after launch emits no peeks (baseline only).
- `syncAgents(at:) -> [SyncAgent]` for the phone: visible sessions, `idle` excluded.
- Missing directory = no sessions, status `.ok` (hooks not installed yet is not an error).

## Hook install (`ClaudeHookInstaller`)

Explicit button per Claude account in Settings, never automatic. Pure function on the account's `settings.json` Data: adds one entry per event above with `{"type":"command","command":"'<path>' || true","timeout":5}`, idempotent (finds ours by `ufuq-hook` in the command), keeps every other key and hook, writes `settings.json.ufuq-backup` before the first change. Uninstall removes only ours and drops event arrays left empty. Invalid JSON → refuse, change nothing.

## Mac

- `ufuq-hook`: executable target in the UfuqCore package (Foundation only), embedded in the app at `Contents/MacOS/ufuq-hook`.
- Collapsed: the agent activity joins the rotation; waiting pins. A small dot before the text pulses (1.2 s opacity) when waiting; static under Reduce Motion.
- Expanded: small tile "Agents" (144 × 112): up to two sessions, state as a word (never color alone), `+N more`. Click or Return on a row activates `appBundleID`'s app.
- Settings: "Agent status" section: per account, Install / Remove hooks with the result line.
- Sync: `contentProvider.agents = module.syncAgents(at:)`; peeks already flow through `enqueuePeek`.
