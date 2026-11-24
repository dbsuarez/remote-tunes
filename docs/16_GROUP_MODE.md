# RemoteTunes — Group Mode (Phase 9, DRAFT)

> Renumbered: it was Phase 8 until the Online Library (docs/18) took that number.

Status: draft for review. Not approved. Do not implement before Phases 0–7 are done and this doc is approved.

## Goal
One Host phone plays the same song in sync on N Player phones in the same room (target: 5 friends, 6 phones including the Host).

## Scope
- Same room, same Wi‑Fi or hotspot. Local mode only. No internet needed.
- Online/Supabase group sync is out of scope (internet latency is too variable for same-room sync).
- Host may also play audio.

## Conflicts with earlier specs (must be resolved before building)
| Spec | Current rule | Group Mode needs |
|---|---|---|
| FR-21 | One active Controller | Host may be Controller of many Players (one Controller → N Players is fine; N Controllers → 1 Player stays disallowed) |
| FR-46 | Files stay on Player | Host sends the file to each Player (opt-in, local network only) |
| 04 protocol | One session per Controller | Controller holds N sessions; commands fan out |
| Architecture | One `RemoteTransport` per Controller | A `GroupSession` owns N transports |

Rules that do NOT change: offline-first, no Supabase dependency, no music in Supabase, no telemetry, token required for every command.

## Requirements
- GM-01 Host creates a group; Players join via existing pairing (6-digit code) or a group join code.
- GM-02 Host sees all members: name, connection state, sync offset, calibration.
- GM-03 Any member can leave; Host can remove a member.
- GM-04 Play, pause, seek, next, previous apply to all members at the same scheduled time.
- GM-05 Host distributes the audio file to every member before playback (progress shown per member). A member without the file cannot play and is shown as "Not ready".
- GM-06 Host may start only when all selected members are Ready, or start anyway and skip the not-ready ones.
- GM-07 Clock sync runs on join and re-runs periodically.
- GM-08 Playback starts at a scheduled Host time `T` (not "now").
- GM-09 Continuous drift correction while playing.
- GM-10 Per-member manual latency nudge (ms, positive or negative), persisted per device.
- GM-11 A member that disconnects mid-song is dropped from sync and can rejoin and resync to the current position.
- GM-12 Plain-language errors; no crash on bad files, lost members, or network changes.

## Sync design
### Clock offset
- Each member exchanges `sync_ping`/`sync_pong` with the Host (monotonic timestamps t0..t3).
- Offset per sample: `((t1 - t0) + (t2 - t3)) / 2`; round trip: `(t3 - t0) - (t2 - t1)`.
- Take ≥ 20 samples, discard the slowest half by round trip, use the median offset of the rest.
- Re-run every ~30 s while idle and every ~10 s while playing.
- Use a monotonic clock, not wall-clock time.

### Scheduled start
- Host sends `group_play { trackId, startPositionMs, startAtHostTimeMs }` with `startAtHostTimeMs` ≈ now + 500–1000 ms so every member has time to receive it and prepare.
- Member converts to local time using its offset and its latency nudge, pre-loads/seeks, then starts at that instant.

### Drift correction
- Every ~2 s a member computes `expectedPosition` from Host time versus its actual player position.
- Error < 15 ms: do nothing. 15–200 ms: nudge with a small playback-speed change (e.g. 0.98–1.02) until corrected. > 200 ms: hard seek.
- Hard limits avoid audible pitch artifacts and seek-glitches.

### Latency calibration
- Android output latency differs per phone and per output route (speaker vs Bluetooth).
- Provide a per-member nudge slider (±200 ms, 5 ms steps) and a "tap-to-calibrate" helper (play a click track on Host + one member, adjust until aligned by ear).
- Persist per device; warn that changing the output route (headphones/Bluetooth) invalidates it.

## Protocol additions (extend 04_NETWORK_PROTOCOL.md; unknown types are ignored, so this is backward compatible)
Types: `group_join`, `group_members`, `sync_ping`, `sync_pong`, `file_offer`, `file_chunk`, `file_ack`, `group_play`, `group_pause`, `group_seek`, `group_state`.

Example:
```json
{"type":"group_play","sessionId":"s","requestId":"r","payload":{"trackId":"t1","startPositionMs":0,"startAtHostTimeMs":1234567}}
```
New error codes: `GROUP_FULL`, `FILE_NOT_READY`, `SYNC_UNAVAILABLE`, `TRANSFER_FAILED`.

## File distribution
- Host streams the file over the existing local WebSocket (chunked, with checksum), or a temporary local HTTP endpoint on the Host.
- Stored in app cache on the member; deleted when the group ends or on user request.
- Members verify checksum before reporting Ready.
- Max group size: 6 members including Host in v1 (configurable constant).

## UI additions (follow docs/15_UX_DESIGN_GUARDRAILS.md)
- Group screen: member list with connection pill, Ready/Not ready, sync status, nudge control.
- "Group" entry on the Controller dashboard; prominent "Group · N phones" pill during playback.
- Reconnecting banner per member.
- Must not copy Spotify branding or UI.

## Phased build plan (inside Phase 9)
- 8a Multi-session fan-out: one Host controls N Players with simple commands (no sync guarantees).
- 8b File distribution with progress and checksums.
- 8c Clock sync service + measurable offset readout (diagnostics screen).
- 8d Scheduled start + drift correction.
- 8e Per-member latency calibration + group UI polish.

## Acceptance targets
Measure with a recorded test: place all phones together, play a click/impulse track, record with a third device, compare onsets.
- Target: 90% of onsets within **50 ms** across all members after 2 minutes of playback; stretch goal **30 ms**.
- Clock-offset estimate stable within ±10 ms on the test Wi‑Fi/hotspot.
- Join, leave, and rejoin work without restarting the song for others.
- Works in airplane mode + hotspot (no internet).
- Tested with 6 phones including both Infinix devices.

## Risks
- `just_audio` cannot guarantee sample-accurate starts; the 50 ms target may need tuning, and < 20 ms probably requires native audio (Oboe/AAudio).
- Wi‑Fi/hotspot jitter and power-saving modes (Infinix battery optimization) can break sync; need foreground service and battery guidance.
- Phone hotspot capacity with 5 clients, and file-transfer time for large files.
- Bluetooth outputs add large, variable latency; recommend wired/speaker only for sync.
- Different Android versions/vendors have different output latency.

## Open questions
1. Is the Host also a playing member by default?
2. Who owns file transfer: always the Host, or may Players already have the file?
3. Maximum group size beyond 6?
4. Should Group Mode reuse the 6-digit pairing code per member or use one group code?
5. Is 50 ms acceptable as the v1 target, or is native audio (Oboe) justified?
