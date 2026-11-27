# Mac to phone sync (plan A6)

Decided 2026-11-26: local network first, no backend. The Mac app is the server; the phone is the
client. Off by default (Settings: "Share with phone on this network").

Code: `UfuqCore/Sources/UfuqCore/Sync/` (models, pairing, HTTP parser, router, event log),
`App/Sources/Sync/` (Network.framework server, CryptoKit, key file, pairing UI),
`android/core/.../sync/` (models, sealer, client). Golden vectors: `UfuqCore/Tests/UfuqCoreTests/Fixtures/sync/`,
copied to `android/core/src/test/resources/fixtures/sync/` (keep the two in step).

## Discovery

The Mac advertises Bonjour service type `_ufuq._tcp` with the service name `ufuq-<deviceId>`
(lower-case UUID). The phone browses with NSD, picks the service whose name matches the paired
`deviceId`, and uses its resolved address and port. The `host` and `port` in the QR are only a
fallback (the port changes on each launch).

## Pairing

The Mac shows a QR ("Pair phone…" in the menu bar). Its text is compact JSON with sorted keys:

```json
{"deviceId":"6f1d2c3a-0b4e-4f5a-9c7d-1a2b3c4d5e6f","host":"Mac-mini.local","key":"AAEC…HR4f","name":"Mac mini","port":49152,"v":1}
```

- `v`: format version, `1`. A phone rejects other values.
- `key`: 32 random bytes, base64url without padding (43 characters). Kept on the Mac in `~/Library/Application Support/Ufuq/sync-key` (0600), not the Keychain: the app is ad-hoc signed, so the Keychain asked again after every update. 0.1.1 keys move to the file once, on first load.
- `deviceId`: stable per Mac install. `name` is optional.

The phone stores the key (Android Keystore-backed storage). "Forget phone" on the Mac deletes the
key and generates a new one on the next start; the old phone then gets 401 and shows "Pair again".
There is one key, so one paired phone at a time (a second phone scanning the same QR also works).

## Crypto

AES-256-GCM on both sides (CryptoKit `AES.GCM`; `javax.crypto` `AES/GCM/NoPadding`, available on
every Android API level). ChaCha20-Poly1305 is not used: it needs API 28 on Android and minSdk is 26.

Sealed box = `nonce (12 random bytes) || ciphertext || tag (16 bytes)`; associated data is the
ASCII string `ufuq-sync-v1`. This is exactly CryptoKit's `SealedBox.combined`.

Known-answer vector (`seal_vector.json`, tested on Swift and Kotlin):

| field | value |
|---|---|
| key | `000102…1f` (bytes 0 to 31) |
| nonce | `a0a1a2a3a4a5a6a7a8a9aaab` |
| plaintext | `ufuq sync known answer` |
| sealed | `a0a1a2a3a4a5a6a7a8a9aaab937e095c65b87bd10145ecbd680daefe11c22a67f7c5886e3a61175eaec0816c3e087a453091` |

## Transport

HTTP/1.1 over TCP, `GET` only, one request per connection (`Connection: close`). The server
rejects anything else: 400 malformed, 405 other methods, 413 any request body, 431 head over 8 KB.

Request auth: header `X-Ufuq-Auth` = base64url (no padding) of the sealed box of the ASCII text
`ufuq-sync-auth:<unix seconds>`. The server opens it with its key and requires the time within
5 minutes of its own clock. Anything else (missing, bad, stale, wrong key) gets `401` with an
empty body, before any routing, so an unpaired caller learns nothing (not even 404s).

Optional header `X-Ufuq-Client`: a short phone name (printable ASCII, at most 64 characters, e.g.
`Samsung SM-S928B`). After a request passes auth and the replay check, the Mac shows it as
"Paired with … · seen … ago". Older phones omit it; the Mac then says "a phone".

Every `200` body is a sealed box of the JSON below (`Content-Type: application/octet-stream`).
JSON is compact, keys sorted, dates ISO 8601 UTC with whole seconds. Clients ignore unknown keys.

### `GET /v1/snapshot`

```json
{"agents":[{"id":"a1","state":"waiting","title":"Refactor sync","updatedAt":"2026-11-28T08:59:50Z"}],
 "generatedAt":"2026-11-28T09:00:00Z",
 "readings":[{"accountId":"claude-work","accountName":"Claude Work","capturedAt":"2026-11-28T08:59:30Z",
   "fraction":0.82,"isEstimated":false,"kind":"session5h","provider":"claude","resetsAt":"2026-11-28T10:12:00Z"}],
 "version":1}
```

- `readings`: one `UsageWindowReading` plus its account. `provider` is `claude`, `codex` or
  `antigravity`; `kind` is `session5h`, `weekly` or `modelGroup` (then `group` holds the name).
  `fraction` is 0 to 1. `resetsAt` and `group` are omitted when unknown. A client skips readings
  with a provider or kind it does not know.
- `agents`: `state` is `running`, `waiting` ("needs input") or `done`. Unknown states are skipped.

### `GET /v1/events?since=<seq>`

Long-poll: the server answers as soon as an event with `seq > since` exists, or after 30 s with an
empty list. The client's read timeout is 35 s.

```json
{"events":[{"createdAt":"2026-11-28T09:00:00Z","id":"usage-claude-95","message":"95% of session","moduleId":"usage","priority":"critical","seq":7,"title":"Claude Work"}],
 "generatedAt":"2026-11-28T09:00:00Z","latestSeq":7,"version":1}
```

`latestSeq` is the cursor: the last event returned, or the request's `since` when none. Pass it
as the next `since`. If `since` is ahead of the Mac's log (the Mac app restarted and the counter
reset), the server starts over from 0. The log keeps the last 200 events in memory.
`priority` is `normal` or `critical`.

## Replay and clock rules

- Server: rejects a request token older or newer than 5 minutes.
- Client: rejects a response whose `generatedAt` differs from its own clock by more than 5 minutes
  (shown as "Clocks differ by more than 5 minutes"). A replayed old response is therefore refused.
- Responses use a fresh random nonce, never reused.

## Client behaviour (phone)

| Situation | Result |
|---|---|
| 401, or a reply that does not open with the key | `Unavailable("Pair again")` |
| Cannot connect or times out | `Unavailable("Mac not reachable")` |
| Other HTTP status | `Unavailable("Mac replied with HTTP n")` |
| JSON does not decode | `Unavailable("Unexpected reply from the Mac")` |
| `version` above 1 | `Unavailable("Update Ufuq on this phone")` |
| Clock skew over 5 minutes | `Unavailable("Clocks differ by more than 5 minutes")` |

Nothing throws to the UI; the sync source is one more data source that can be "unavailable".

## Security notes

- The server listens on all interfaces but answers only requests carrying a valid token.
- The `.local` host and port in the QR are not secret; the key is. Do not log or show the QR text.
- The connection is plain HTTP; confidentiality and integrity come from the sealed bodies. The
  request token proves possession of the key but is replayable for 5 minutes (it only authorises
  reads of the same data).
- Local network permission: the Mac Info.plist declares `NSBonjourServices` and
  `NSLocalNetworkUsageDescription`; the phone needs `CHANGE_WIFI_MULTICAST_STATE`/NSD and cleartext
  HTTP allowed for the paired host (network security config).

## Later

Opt-in push relay (self-hosted ntfy) for agent alerts away from the desk; not part of this protocol.
