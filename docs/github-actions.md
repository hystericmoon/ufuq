# GitHub Actions status (Phase 6b)

Shows the CI of the repos you work in: running, failed, passed. Owner decisions (27 Nov 2026): token from `gh`, else a pasted PAT in a 0600 file; repos auto-detected from Claude Code sessions plus a manual list; peeks on failures and on your own finished runs.

## Token

1. `gh auth token` via `Process`, trying `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, `/usr/bin/gh` (a GUI app gets no shell `PATH`). 5 s timeout; trimmed stdout; non-zero exit or empty = no token.
2. Else `~/Library/Application Support/Ufuq/github-token` (0600, directory 0700, like `sync-key`). Settings asks for a fine-grained PAT with **Actions: read** (and Metadata: read, implied).
3. Neither: module status `.unavailable("No GitHub token")`; the tile is hidden, Settings explains.

Never the Keychain: ad-hoc signing makes it ask again after every update. The token is never logged and never sent to the phone.

## Watched repos

- **Auto:** for each visible Claude Code session (`AgentStatusModule.sessions(at:)`), read the git remote `origin` URL from `<cwd>/.git/config`, walking up parent directories to the first `.git`; a `.git` *file* (worktree) has `gitdir: <path>`: read `config` from that gitdir's `commondir` (or two levels up from `worktrees/<name>`). Only `github.com` remotes: `git@github.com:o/r(.git)`, `https://github.com/o/r(.git)`, `ssh://git@github.com/o/r(.git)`. Kept for 24 h after the session was last seen.
- **Manual:** `owner/repo` entries in Settings (validated by `GET /repos/{o}/{r}`; 404 = "Not found or the token can't see it").
- Union, deduped case-insensitively, at most 10 (manual first). Settings lists them with the source ("from a Claude session" / "added").

## Polling

- `GET https://api.github.com/repos/{o}/{r}/actions/runs?per_page=20` with `Authorization: Bearer`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `If-None-Match: <etag>` (a 304 does not count against the rate limit).
- Every 15 s while any watched repo has a run `queued`/`in_progress`, else every 60 s. `GET /user` once per token for `login`.
- 401 → `.unavailable("GitHub token rejected")`. 403/429 with `x-ratelimit-remaining: 0` → back off until `x-ratelimit-reset`. Network error → keep last data, status `.stale(since:)`. One repo failing never hides the others.

## Model

A **build** = runs of one repo with the same `head_sha` and `event` (one push fans out to several workflows). Only runs whose `updated_at` is within 24 h.

- `running` if any run is `queued`/`in_progress`/`waiting`/`pending`/`requested`.
- else `failed` if any `conclusion` is `failure`, `timed_out`, `startup_failure` or `action_required`.
- else `passed` (`success`, `skipped`, `neutral`; `cancelled`-only builds are hidden).
- Fields: repo full name, short repo name, branch (`head_branch`), PR number (first of `pull_requests`), workflow count, `startedAt` (min `run_started_at`), `finishedAt` (max `updated_at` once completed), `url` (the failing run's `html_url`, else the newest run's), `isMine` (`triggering_actor.login` or `actor.login` == token login).

## Notch

- One collapsed activity, id `github`, source `.other`, never `isAlert`. Priority: any running → `CI running` (`2 CI running`); else a failed build finished < 10 min ago → `CI failed`; else a mine build passed < 5 min ago → `CI passed`. The slot fits ~11 characters; repo and branch go in the label: "GitHub Actions, ufuq, main, failed".
- Peeks (from comparing the previous poll; none on the first poll after launch or after a token change):
  - build → `failed`: normal, title `CI failed`, message `ufuq · main · Mac app` (PR: `ufuq · PR #12`; several failing workflows: `… · 2 workflows`), id `github.failed.<repo>.<sha>`.
  - build → `passed`, `isMine`, ran ≥ 60 s: normal, title `CI passed`, message `ufuq · PR #12 · 3m 40s`, id `github.passed.<repo>.<sha>`.
- Small tile "Actions" (144 × 112, like Agents): newest two builds, `ufuq` + `Running 2m` / `Failed` / `Passed`; ✕ / ✓ / spinner glyph next to the word (never color alone). Row click opens `url` in the browser. Hidden when there are no builds in 24 h.
- Peeks reach the phone through the existing `enqueuePeek` → sync event log.

## Code

- UfuqCore (Foundation only, tested on Linux): `GitHubRun` (Decodable subset), `GitHubBuild` + grouping, `GitRemote` (parse `.git/config`, find the repo for a cwd through a `FileSource`-style seam), `GitHubClient` (builds requests, parses responses and rate-limit headers; transport injected as `(URLRequest) async throws -> (Data, HTTPURLResponse)`), `GitHubTokenSource` (command runner + file read injected), `GitHubActionsModule: UfuqModule` (id `github`).
- Mac: transport = `URLSession.shared`; command runner = `Process`; token file write in Settings; tile, Settings section, snapshots.
