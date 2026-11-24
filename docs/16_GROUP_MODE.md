# RemoteTunes — Group Mode (Phase 9, DRAFT)

> Renumbered: it was Phase 8 until the Online Library (docs/18) took that number.

Status: **v1 built** (see "v1 as built" below). The rest of this document is the longer-term design and is still a draft.

## v1 as built: two phones, the Player leads

The first version covers the most wanted case: **the Controller phone plays the song along with the Player**. It is deliberately smaller than the full design below.

- **Roles:** the **Player is the master**. Its playback position and its clock define "now". The **Controller phone is the follower**: it downloads the song from the Player and plays it in sync. (The draft below has the Host sending files out; in RemoteTunes the music already lives on the Player, so the flow is reversed.)
- **Switch:** Controller > Now Playing > **Play on this phone too**. Fine-tune slider (-300 to +300 ms, 5 ms steps, saved on the phone), live readouts of the sync error, the round trip and the clock spread, and **Measure again**.
- **Local network only.** The Player refuses `groupJoin` over the internet relay, and the web Controller has no group play (no audio, no local network).
- **Clock sync:** NTP-style `sync_ping`/`sync_pong` probes on a monotonic clock. 14 probes at join, 5 more every 10 s, slower half dropped, median of the rest (`features/group/clock_sync.dart`).
- **Playing in step:** the Player sends `group_sync {songId, positionMs, atMs, playing, speed, nextSongId}` once a second and on every state change. The follower works out `expected = position + (Player clock now - atMs) * speed + nudge` and: starts there; hard-seeks if off by more than 200 ms (at most once per 1.5 s); plays 2% faster or slower if off by more than 15 ms; goes back to normal speed under 8 ms (`group_follower_core.dart`).
- **Songs:** the follower downloads the playing song from the Player (`GET /group/audio/<songId>`, only for a joined Controller, only library songs, session id and token as headers, SHA-256 checked) and fetches the **next** song ahead of time. Downloads are deleted when group play ends. Only the last 6 songs are kept while it runs.
- **Not covered in v1:** more than two phones, internet tracks (Jamendo/URL; the follower stays quiet and says so), native low-latency audio.

### Hardening after the first real test ("it is off by some milliseconds")
Nothing in the first version could see a *constant* offset between two phones' speaker delays, so it could look "in sync" by its own numbers while sounding apart. What was added:

- **Auto-align (measures it with the microphone).** The Player plays a click track (two chirp trains with different irregular timing, `calibration_track.dart`) through the normal group-play path. The follower is muted and records the Player's train; then the Player mutes itself, the follower unmutes and records its own train. Each train is located in the recording by FFT cross-correlation (`calibration_analysis.dart`), first coarsely for the whole track, then each train only within +/-0.7 s of where it must be (so a loud phone cannot be mistaken for a faint one). The microphone's own delay is the same for both trains and cancels. Result: how much later (+) or earlier (-) this phone sounds; the fine-tune moves by that amount. Running it again measures what is left. Tested with synthetic recordings (known delay, noise, echo, very different loudness, inverted speaker) to within 0.3 ms. The Player's queue, current song, position and volume are put back afterwards, also if it is cancelled or the connection drops (the Player undoes it by itself, and after 40 s at the latest).
- **Steadier correction.** The error is the median of the last five readings (one noisy reading does nothing); nothing is corrected for 0.8 s after a start or a jump (the engine's position is unsettled); speed nudges are 1% not 2%; a hard jump needs two far-off readings in a row (or the Player itself seeking, which is followed at once); at most one jump per 2 s; and if it stays more than 40 ms off for 12 s it says so ("Can't stay in step") instead of pretending.
- **Better clock estimate.** Only the quickest third of the probes is used (the least disturbed by Wi-Fi), 20 probes at join and 6 every 5 s while it runs; a spread over 15 ms shows an "uneven Wi-Fi" warning.
- **Stays awake, Wi-Fi in a fast mode.** Both phones hold a partial wake lock and a Wi-Fi lock while group play runs (Wi-Fi power saving adds jittery delay that spoils the clock measurements and can drop audio), and the phone that plays along keeps its screen on (`GroupSupport.kt`).
- **Output route.** Bluetooth adds a large delay that changes from moment to moment: the card warns, and Auto-align refuses to run on it. The fine-tune is remembered **separately per output** (speaker, wired, Bluetooth), because each has a different delay.
- **Downloads** are cancelled cleanly if group play ends mid-download (a race found by the tests).
- **Known limit:** an MP3's seek position can be approximate on Android for variable-bitrate files without a seek table, which Auto-align (a WAV) cannot see. If a phone joins mid-song and is consistently off by a fixed amount for one song only, that is the likely cause.
- **Open questions answered:** (1) the follower always plays; (2) the Player owns the files; (3) group size stays at 2 until the fan-out is built; (4) it uses the existing pairing/trust, no group code; (5) 50 ms is the target for v1, measure first, then decide about native audio.
- **How to judge it:** put the two phones side by side, play a song with a clear beat, and listen. The Group card shows "Off by" in ms. If one phone is consistently early or late, use the fine-tune slider. Output latency differs per phone and per speaker or Bluetooth device, so it needs a one-off adjustment per setup.



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
v1 (two phones, Player leads) covers 8b (file distribution with checksum), 8c (clock sync and readout), 8d (start at the right position + drift correction) and the per-phone nudge of 8e. Still to do:
- 8a Multi-session fan-out: more than one follower.
- 8e Tap-to-calibrate helper, per-route warnings, group UI polish.
- Background playback (foreground service) for the follower.

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
