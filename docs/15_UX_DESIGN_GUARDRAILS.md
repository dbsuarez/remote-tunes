# RemoteTunes — UX Design Guardrails

## Purpose

This document defines how RemoteTunes can use familiar music-player UX patterns without copying Spotify’s exact visual identity, branding, or interface.

RemoteTunes may take inspiration from common music-app workflows, but it must have its own distinct visual identity and prioritize its differentiator: remote control, connection state, and two-phone workflow.

## 1. What you may use

You may use common, functional music-app UX patterns:

- Dark theme with a strong accent color.
- Bottom navigation.
- Large “Now Playing” bar above bottom navigation.
- Full-screen Now Playing page.
- Large album art.
- Play/pause, previous, next, shuffle, repeat.
- Seek bar with elapsed/remaining time.
- Queue accessible from Now Playing.
- Search across songs, artists, albums.
- Artist and album detail pages.
- Playlist creation and song context menus.
- Mini-player that expands into full player.

These are common patterns, not Spotify-exclusive.

## 2. What you must not copy

Do not copy or imitate:

- Spotify logo.
- Spotify green color (#1DB954).
- Spotify circle-and-waves mark.
- Spotify name or confusingly similar name.
- Spotify icons, illustrations, fonts, layouts, screen compositions.
- Spotify artwork, playlist covers, or UI screenshots.
- Spotify exact visual identity or “look and feel.”

Spotify’s guidelines prohibit modified or imitative use of its trademarks and confusingly similar branding.

## 3. RemoteTunes visual identity

Use a distinct identity:

| Element | RemoteTunes direction |
|---|---|
| Theme | Dark charcoal + electric teal or violet accent |
| Layout | Controller dashboard first, music library second |
| Now Playing | Large centered album art, remote status badge |
| Navigation | Bottom tabs: Remote, Queue, Library, Settings |
| Player | Full-screen player with “Playing on <Player name>” label |
| Queue | Vertical list with drag handles and remote-control badges |
| Library | Grid/list toggle, filter chips for Artists/Albums/Songs |
| Connection | Prominent connection pill: Local Wi‑Fi, Hotspot, Online |

## 4. Example Home screen

```text
RemoteTunes

[ Connected to GT 30 Pro · Local Wi‑Fi ]

Now Playing
Album Art
Example Song
Example Artist

[ Previous ] [ Play/Pause ] [ Next ]

Seek bar
0:42 ------------------ 3:30

Bottom navigation:
[ Remote ] [ Queue ] [ Library ] [ Settings ]
```

## 5. Example full player

```text
[ Back ]

Album Art

Example Song
Example Artist

0:42 ------------------ 3:30

[ Shuffle ] [ Previous ] [ Play/Pause ] [ Next ] [ Repeat ]

Volume
[ speaker ] ------------------ [ speaker ]

[ Queue ] [ Devices ] [ More ]
```

## 6. UX differentiator

Make connection state more important than a normal music app:

- Persistent connection pill: Local Wi‑Fi, Hotspot, Online.
- Show Player phone name prominently.
- Use distinct color for online mode.
- Show reconnecting banner when connection drops.
- Keep Queue and Library easy to reach.
- Add “Send to Player” action for URLs and local songs.

## 7. Branding rule

Keep the name RemoteTunes.

Do not use:

- “Spotify Remote”
- “Spotify Controller”
- “Spotify Music Player”
- Any logo or green color resembling Spotify.

## 8. Rule for AI coding agents

Add this rule to every UI implementation prompt:

> RemoteTunes may use familiar music-player interaction patterns, but must not copy Spotify’s exact visual identity, logo, color palette, icons, artwork, typography, screen layouts, or branding. The app must have its own distinct visual identity and prioritize remote-control status, connection state, and two-phone workflow.

## 9. Design rule

Use Spotify as a UX reference, not a visual template.

- Copy the workflow: Now Playing, Queue, Search, Library.
- Change the identity: colors, icons, typography, layout details, branding.
- Emphasize the differentiator: remote control, connection status, two-phone workflow.
