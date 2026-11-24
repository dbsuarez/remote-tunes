# Next tasks

Ideas queued by the project owner. Nothing here is built unless ticked.

## Poweramp-inspired additions

(Inspiration only. Own look and own code, see [docs/15](15_UX_DESIGN_GUARDRAILS.md).)

### Audio engine (Player side)
- [x] Gapless playback: the next local song is lined up in just_audio's playlist (`QueuePlaybackEngine._preloadIfChanged`, `AudioBackend.setNext`). Internet tracks and repeat-one still load normally. Not yet heard on a phone.
- [ ] Crossfade (a fade between songs; needs two players or a volume ramp, and a setting for its length)
- [ ] 10-band graphic EQ with per-output presets (speaker / wired / Bluetooth)
- [ ] Replay Gain scanner (background isolate)

### Library and metadata (Player side)
- [x] Folder browser view (Library > Folders; folders are listed by name only, never by path)
- [x] Auto playlists: Recent (already there), Top (play counts, schema v5) and New (the newest 100)
- [ ] Album art auto-fetcher service
- [ ] Basic tag editor

### UI/UX (both sides)
- [ ] Skinning engine (JSON themes)
- [ ] Visualizer tab (Player only)
- [x] Gesture: edge-swipe on the Controller's Now Playing: in from the right edge raises the queue (middle, then full), in from the left edge opens the Library. Not on the Player screen. With Android gesture navigation the very edge is also "back": start the swipe a finger-width in.
- [ ] Rich MediaSession / lock-screen controls

## Lyrics (Poweramp-style synced lyrics)

**Providers:** primary LRCLIB (lrclib.net: free, no key, time-synced LRC, CORS enabled). Fallbacks: lyrics.ovh (plain text), Megalobiz (synced; requires attribution).

- [x] Drift table `LyricsCache` (schema v6; kept 30 days, a miss 1 day)
- [x] Protocol: `getLyrics {songId}` -> `RemoteLyrics` (plain + LRC)
- [x] `LyricsService` on the Player (LRCLIB exact, LRCLIB search, then lyrics.ovh) and `core/lyrics/lrc.dart` (LRC parser)
- [x] UI: a Lyrics button under the song on Now Playing (Player and Controller) opens a panel that follows the song line by line; tap a line to jump there. (The album art stays in the card above it rather than being swapped out.)
- [x] Sync: the Controller asks the Player, which answers from its cache
- [ ] Megalobiz fallback (scraping a site that asks for attribution; skipped for now)
- [x] Settings switch "Lyrics from the internet" (Look and feel)

**Legal / privacy:** personal and open-source use only; no bulk download; cache per track, on demand. Only the song's title, artist, album and length are sent to the lyrics provider (never file paths); this needs a note in the privacy text and an off switch in Settings.

## Releases and self-update (built)
- [x] Release APKs on GitHub Releases (`.github/workflows/release.yml`, see README "Releases and updates").
- [x] In-app update: Settings > App updates, and a card on Home when a newer version exists.
