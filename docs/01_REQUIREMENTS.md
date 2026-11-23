# RemoteTunes — Requirements (v2)

## Connection
- FR-01 Local control over same Wi‑Fi.
- FR-02 Local control over hotspot.
- FR-03 Local discovery, pairing, local playback, and remote commands work without internet.
- FR-04 mDNS/NSD discovery.
- FR-05 Manual IP/port fallback.
- FR-06 Optional online remote control using Supabase Realtime.
- FR-07 Online mode works across different Wi‑Fi networks or mobile data.
- FR-08 Online mode optional; local mode never blocked.
- FR-09 Auto mode prefers local, falls back to online.
- FR-10 User can choose Local/Online/Auto.
- FR-11 Clear connection status.
- FR-12 Reconnection.
- FR-13 Either phone can disconnect.

## Pairing
- FR-14 Pairing request before commands.
- FR-15 Show Controller name/address.
- FR-16 Six-digit pairing code.
- FR-17 Controller enters code.
- FR-18 Session token after pairing.
- FR-19 Token required for commands.
- FR-20 Reject invalid/expired token.
- FR-21 One active Controller in v1.
- FR-22 Second Controller requires replacement/rejection.
- FR-23 Tokens/codes local.
- FR-24 No music/history/telemetry upload.

## Playback
- FR-25 Play.
- FR-26 Pause.
- FR-27 Toggle.
- FR-28 Next.
- FR-29 Previous.
- FR-30 Seek seconds.
- FR-31 Seek percent.
- FR-32 Volume 0-100.
- FR-33 Stop.
- FR-34 Repeat off/one/queue.
- FR-35 Shuffle.

## Library/Queue
- FR-36 File picker.
- FR-37 Folder import.
- FR-38 MP3/M4A/AAC/FLAC/WAV/OGG where supported.
- FR-39 Metadata.
- FR-40 Filename fallback.
- FR-41 Library screen.
- FR-42 Controller browses library.
- FR-43 Controller searches library.
- FR-44 Controller plays song.
- FR-45 Controller queues song.
- FR-46 Files stay on Player.
- FR-47 Queue from song(s)/folder/album/artist.
- FR-48 Queue view.
- FR-49 Queue item info.
- FR-50 Play queue item.
- FR-51 Remove item.
- FR-52 Move item.
- FR-53 Clear queue.
- FR-54 Shuffle queue.
- FR-55 Queue persists while app alive.

## URL/State/Background/External
- FR-56 Controller sends URL.
- FR-57 HTTP/HTTPS direct audio.
- FR-58 URL validation.
- FR-59 Clear errors.
- FR-60 Internet notice.
- FR-61 Recent URLs local.
- FR-62 State updates.
- FR-63 Full state fields.
- FR-64 State after command.
- FR-65 State on track change/play/pause/stop/complete.
- FR-66 Periodic state while playing.
- FR-67 Controller updates from state.
- FR-68 No assumed success.
- FR-69 Background playback screen off.
- FR-70 Background playback minimized.
- FR-71 Background playback other app.
- FR-72 Media notification.
- FR-73 Headset/media buttons.
- FR-74 Battery optimization guidance.
- FR-75 External App Control mode.
- FR-76 Separate from RemoteTunes Player.
- FR-77 Detect active media session.
- FR-78 Basic transport controls.
- FR-79 Metadata where available.
- FR-80 Limitations explained.
- FR-81 Notification Listener permission.
- FR-82 No full Spotify/YouTube guarantee.

## Non-functional
- Local command <300 ms typical.
- Hotspot <500 ms typical.
- Online relay <1 s typical.
- State update <500 ms local.
- Start <3 s.
- MP3 start <2 s.
- No crash on bad files.
- Handle backgrounding/network changes.
- No analytics.
- Plain-language errors.
- 48dp tap targets.
- Android 10+.
- Test both Infinix phones.
