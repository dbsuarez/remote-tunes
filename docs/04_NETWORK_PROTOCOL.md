# RemoteTunes — Network Protocol (v2)

Same JSON protocol for local WebSocket and Supabase Realtime.

## Envelope
```json
{"type":"command","sessionId":"uuid","requestId":"uuid","payload":{}}
```

## Types
hello, pairing_request, pairing_code, pairing_result, command, command_result, state, library_request, library_response, error, ping, pong.

## Pairing
Controller sends pairing_request. Player shows code (6 digits, 5 min). Controller sends pairing_code. Player returns pairing_result with session token.

## Commands
Actions: play, pause, toggle, next, previous, stop, seek, setVolume, playUrl, playSong, queueSong, getQueue, removeQueueItem, moveQueueItem, clearQueue, setRepeatMode, setShuffle.

Example play:
```json
{"type":"command","sessionId":"s","requestId":"r","payload":{"action":"play"}}
```

Seek:
```json
{"type":"command","sessionId":"s","requestId":"r","payload":{"action":"seek","positionSeconds":45}}
```

Volume:
```json
{"type":"command","sessionId":"s","requestId":"r","payload":{"action":"setVolume","volume":0.75}}
```

PlayUrl:
```json
{"type":"command","sessionId":"s","requestId":"r","payload":{"action":"playUrl","url":"https://example.com/song.mp3","title":"Song"}}
```

## State
```json
{"type":"state","sessionId":"s","requestId":"","payload":{"title":"Song","artist":"Artist","positionSeconds":42,"durationSeconds":210,"isPlaying":true,"queueIndex":3,"queueLength":12,"volume":0.8,"repeatMode":"off","shuffleEnabled":false,"source":"local_file"}}
```

## Errors
INVALID_MESSAGE, UNSUPPORTED_PROTOCOL, NOT_PAIRED, INVALID_SESSION, SESSION_REPLACED, INVALID_ACTION, INVALID_CODE, INVALID_URL, URL_UNREACHABLE, FILE_NOT_FOUND, UNSUPPORTED_FORMAT, PLAYBACK_FAILED, INVALID_POSITION, QUEUE_EMPTY, PERMISSION_DENIED, INTERNAL_ERROR.

## Rules
- Every command gets command_result or error.
- Player sends full state after successful command.
- Unknown types/fields ignored.
- Protocol version checked in hello.

## Phase 1 implementation notes (additive, backward compatible)
Added while building Phase 1. All are optional fields or values that older peers ignore.
- Envelope may carry a top-level `token` (the session token). Required on every `command`.
- `hello` payload: `protocolVersion`, `role` (`player`|`controller`), `deviceName`. A Controller may send `sessionId` + `token` in `hello` to resume; the Player's `hello` reply sets `payload.resumed`.
- `pairing_result.payload.status`: `pending`, `waiting_for_player`, `accepted` (with `sessionId`, `token`, `playerName`), `rejected`, `expired`, `too_many_attempts`.
- Pairing needs both: the Controller enters the 6-digit code **and** the Player user taps Accept (either order). 3 wrong codes cancel pairing.
- A new pairing request while a Controller is paired lets the Player user replace it; the old Controller gets `SESSION_REPLACED`.
- A Controller that disconnects on purpose closes the WebSocket with code 4000 so the Player revokes the session. Other close codes (network loss) keep the session so the Controller can resume. dart:io only allows close codes 1000 or 3000–4999.
- Heartbeat: Controller sends `ping` every 5 s; a connection silent for 15 s is considered lost. Controller reconnects automatically with its token.
- mDNS/NSD service type `_remotetunes._tcp`; TXT attribute `ip` lists the Player's IPv4 addresses, `v` the protocol version.
- A future non-socket transport (Supabase Realtime, web Controller) has no WebSocket close code, so it will need an explicit in-protocol way to say "I disconnected on purpose". Decide this in Phase 4.

## Phase 2 implementation notes (additive, backward compatible)
- New actions: `playSong`, `queueSong`, `getQueue`, `removeQueueItem`, `moveQueueItem`, `clearQueue`, `setRepeatMode`, `setShuffle`, plus `playQueueItem` (jump to a queue entry; not in the original list, needed for FR-50).
- Song arguments: `songId` (one) or `songIds` (list, max 2000). `playSong` replaces the queue with `songIds` and starts at `songId`. `queueSong` appends, or inserts after the current song with `playNext: true`, and does not start playback.
- `command_result.payload` may carry extra data. `getQueue` returns `queue`: `{items:[{queueItemId, song, isCurrent}], currentIndex, revision, shuffle, repeat}`.
- `library_request.payload`: `scope` (`songs`|`artists`|`albums`), `query`, optional `artist`/`album`, `offset`, `limit` (1-100). `library_response.payload`: `scope`, `total`, `offset`, `items`. Both require the session token.
- `state.payload` gains `album`, `songId` and `queueRevision` (bumps when the queue contents change, so Controllers refetch the queue).
- Songs are never sent with file paths or art paths (FR-46). `available:false` marks a song whose file is missing.
- New error use: `FILE_NOT_FOUND` (missing/unknown songs), `QUEUE_EMPTY`, `INVALID_ACTION` (bad arguments, or a Player without a queue).

## Phase 3 implementation notes (additive, backward compatible)
- `playUrl` command: `{"action":"playUrl","url":"https://…","title":"optional"}`. The Player validates the link (http/https only, no credentials, max 2048 chars), runs a network pre-flight check, then replaces the queue with the stream and plays it. It can take several seconds, so Controllers should wait longer than for normal commands (the app uses 30 s).
- Errors: `INVALID_URL` (not a usable link, or the address is a web page instead of audio), `URL_UNREACHABLE` (no internet on the Player, DNS/TLS failure, 4xx/5xx, timeout), `PLAYBACK_FAILED` (the link was reachable but could not be decoded). `message` is plain language.
- `state.payload` gains `isLoading` (true while a stream is opening; omitted when false) and `error` (plain-language playback problem such as a dropped stream; omitted when empty). `source` is `"url"` for streams and `songId` is omitted. Streams have `durationSeconds` 0 until/unless the length is known.
- The stream address is never included in `state`, queue items or any other message to a Controller. Queue items for a stream use artist "Internet" and `available: true`.

## Phase 4 implementation notes (additive, backward compatible)
- **Relay framing.** The online relay is a Supabase Realtime Broadcast channel `remotetunes:<room-code>` (event `rt`). Every participant hears every frame, so each frame is wrapped: `{"v":1,"from":"<peer>","to":"<peer>","m":"<RemoteMessage JSON text>"}`. The Player is `player`; a Controller is `c-xxxxxxxx` (stable for the session). `m` is the unchanged local protocol message. Frames not addressed to a participant, and frames that fail to parse, are ignored.
- **Room code.** 8 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0/1/I/L/O), random, new for every Player session. Written `ABCD-2345`; dashes and spaces are ignored when typing.
- **`bye` message type.** A Controller that disconnects on purpose sends `bye` so the Player revokes the session (the relay has no socket close code). Closing a local socket with code 4000 still works.
- **`pong` payload** carries `hello` (bool). `false` means the Player no longer knows this connection (e.g. it was dropped as stale), so the Controller must say `hello` again and resume. This matters on the relay, where nothing tells a Controller its connection was dropped.
- **Resume across routes.** `hello` with `sessionId` + `token` resumes a session on any route (Wi‑Fi or relay); the session is not tied to a connection type.
- **mDNS TXT** adds `room` (the Player's room code) when the online relay is on, so an Auto-mode Controller can fall back without typing it.
- **Queue size.** Over the relay, `getQueue` returns at most 250 items and adds `total` (the real count) when it cut the list.
- **Security.** Anyone who knows the room code can join the room. Pairing (6-digit code + Accept) and the session token protect commands, but relay messages are not encrypted at the application level.

## Phase 5 implementation notes (additive, backward compatible)
- **`setControlMode` command:** `{"action":"setControlMode","mode":"local"|"external"}` switches the Player between its own player and another music app on the Player phone. Errors: `PERMISSION_DENIED` (External App Control is off on the Player, or Notification access is not allowed), `INVALID_ACTION` (bad mode, or a Player that cannot switch).
- **`state.payload` additions** (sent only when they differ from the defaults, so older peers see nothing new): `externalApp` (name of the controlled app, e.g. "Spotify"), `externalEnabled` (true when the Player has External App Control on, i.e. a Controller may switch), `canSeek` / `canSkip` (false when the other app does not allow seeking / skipping). In external mode `source` is `"external"`, there is no queue (`queueLength` 0) and `songId` is omitted.
- **While external:** all queue, library-song and URL commands return `INVALID_ACTION` ("…not available while controlling <app>. Switch back to RemoteTunes first."). Transport commands go to the other app; `next`, `previous` and `seek` return `INVALID_ACTION` naming the app when it does not currently allow them. `setVolume` sets the phone's media volume.
- **Privacy:** the Player sends only the app's display name, title, artist, album, position and play state. Package names and notification contents never leave the Player.

## Phase 6 implementation notes (no protocol change)
- The web Controller speaks the same protocol over `OnlineTransport` only. No new message types.
- `ControllerClient` can resume a saved session (`hello` with `sessionId` + `token`); the web app stores it in browser local storage and clears it on `bye`/disconnect or when the Player rejects it (`sessionInvalid`).
- The token in browser storage is a secret: it is never put in a URL.

- `saveQueueAsPlaylist {name}` (Phase 7): makes a playlist from the queue's library songs in queue order and returns `{playlistId, added, skipped}` (`skipped` = internet tracks left out). Refused with a plain message for an empty queue, a queue of only internet tracks, or a bad name; no playlist is left behind on failure.

## Phase 9: group play (additive, local network only)
- `sync_ping {t0}` (Controller to Player) is answered by `sync_pong {t0, t1, t2}`: `t1` is when the Player received it and `t2` when it replied, both on the Player's monotonic clock (milliseconds, fractions allowed). The Controller adds its own receive time `t3`: `offset = ((t1-t0)+(t2-t3))/2`, `rtt = (t3-t0)-(t2-t1)`. Needs an authenticated session.
- Command `groupJoin {enabled}`: while `true` the Player sends this Controller `group_sync` once a second and on every state change; refused over the online relay (`INVALID_ACTION`).
- `group_sync` payload: `songId` (library id, omitted when nothing followable plays), `positionMs`, `atMs` (the Player's clock when the position was read), `playing`, `speed`, `durationMs`, `nextSongId` (optional).
- `GET /group/audio/<songId>` on the Player's HTTP port, headers `x-rt-session` and `x-rt-token`. Only while that session has joined; library songs only; answers 403 / 404 otherwise. The reply carries `x-rt-sha256` and `x-rt-ext`.

- Auto-align (group play): command `groupCalibrate {step}`, `step` one of `start`, `mutePlayer`, `unmutePlayer`, `end`. Needs a joined session. `start` plays the click track (library id -1, "Sync test (Auto-align)") as the next queue entry; `mutePlayer` sets the Player's volume to 0 (its previous volume is remembered); `end` restores the volume, removes the click track, goes back to the song and position that was playing, and its play state. The same restore happens by itself if the Controller leaves group play, disconnects, or after 40 s. `GET /group/audio/-1` serves the click track WAV only while a test runs.

## Phase 7 implementation notes (additive)
- **`setSleepTimer` command:** `{"action":"setSleepTimer","minutes":30}`; `0` cancels; allowed 0 to 720, otherwise `INVALID_ACTION`. The Player pauses when the time is up.
- **`state.payload.sleepTimerSeconds`:** time left, sent only while a timer runs.
- **Trusted devices (QR pairing):** a `pairingCode` message may carry the one-time ticket from the Player's QR code instead of the 6-digit code. A `hello` with `sessionId` + `token` may resume a session the Player has stored as trusted (it keeps a SHA-256 hash of the token), even after the Player restarted.

## Phase 7 additions (library and playback)
- `library_request` scope `songs` accepts `view` (`favorites` or `recent`) and `playlistId`; new scope `playlists` returns `{id, name, songCount}`. Songs carry `favorite: true` when set.
- Commands: `setFavorite {songId, favorite}`, `createPlaylist {name}` (returns `playlistId`), `renamePlaylist`, `deletePlaylist`, `addToPlaylist {playlistId, songIds}` (returns `added`), `removeFromPlaylist {playlistId, songId}`, `setSpeed {speed}` (0.5 to 2.0), `getArt {songId, size?}` (returns `art`, a base64 JPEG thumbnail with longest side `size`, 48 to 256, default 256, or nothing).
- `state.payload` may carry `speed` (when not 1.0) and `favorite` (current song).
- Online history (docs/18): `library_request` scope `onlineHistory` (items without stream links, plus `enabled`); commands `playHistory {historyId, queue?}`, `removeHistory {historyId}`, `clearHistory`, `setHistoryEnabled {enabled}`. `playUrl` also accepts `license` (creativecommons.org) and `art` (jamendo.com), otherwise ignored.
- `playUrl` accepts `artist`, `album` (shown on the Player and in the queue) and `queue: true` (add to the end of the queue instead of playing at once). Used by the Online Library (docs/18).
- `playSong` accepts `keepQueue: true`: the songs are inserted after the current one and the first plays, without clearing the queue.
- A Controller that receives `SESSION_REPLACED` or `INVALID_SESSION` while connected does not forget the Player; only a refused `hello` (resume) does.
- Pairing QR: the text is `https://dbsuarez.github.io/remote-tunes/#/pair?v=1&h=&p=&r=&t=&n=` (the older `remotetunes://pair?...` is still read).
