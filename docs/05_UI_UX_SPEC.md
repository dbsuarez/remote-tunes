# RemoteTunes — UI/UX (v2)

Material 3 dark theme.

## Home
Device name, connection mode (Auto/Local only/Online only), Start as PLAYER, Start as CONTROLLER, connection history, settings.

## Discovery
Nearby Players list, refresh, manual IP/port, online room code field, connect online.

## Pairing
Player shows Controller name, connection type, 6-digit code, Accept/Reject. Controller enters code.

## Controller dashboard
Connected Player, connection type, now playing, transport controls, seek, volume, tabs Now Playing/Queue/Library/URL.

## Player dashboard
Player status, connected Controller, now playing, local controls, Add MP3, Add folder, Play URL, Queue, External App Control.

## Settings
Device name, connection mode, online relay toggle, Supabase URL/key, default volume, repeat, shuffle, background playback, external app control.

## States
Loading, empty, error, success, offline/disconnected, reconnecting.

## Rules
- Seek sends on release.
- Volume debounced 200-300ms.
- Buttons disabled when disconnected.
- Lazy lists.
- 48dp targets.
