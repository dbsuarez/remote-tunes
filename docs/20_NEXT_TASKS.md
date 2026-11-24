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
- [x] Album art finder: Settings > Find missing album art (MusicBrainz + Cover Art Archive, on request, 1 request a second, only artist and album names are sent; pictures saved on the Player)
- [x] Basic tag editor: song menu > Edit info on the Player's library (title, artist, album, track number). Changes the listing in RemoteTunes only; the music file is not touched. (Writing tags into the files is not done.)

### UI/UX (both sides)
- [ ] Skinning engine (JSON themes)
- [ ] Visualizer tab (Player only)
- [x] Gesture: edge-swipe on the Controller's Now Playing: in from the right edge raises the queue (middle, then full), in from the left edge opens the Library. Not on the Player screen. With Android gesture navigation the very edge is also "back": start the swipe a finger-width in.
- [x] Rich MediaSession: lock screen / Android 13+ media controls show the cover, length, shuffle, repeat and speed and can change them; a loading state is shown. (A favorite button on the lock screen is not done.)

## From the Poweramp screenshots (`docs/poweramp_screens/`)

Layout ideas only. Keep our own look (dark charcoal, teal/violet, connection status first) and do not copy Poweramp's icons, colors or skin.

- [x] **Now Playing v2 (Controller), mostly done:** big rounded cover, centered accent-colored title with "Artist · Album", favorite / shuffle / repeat row, round play button with previous / next and 10-second back / forward, seek bar with times. Still to do: sleep timer and speed in the quick row (they are cards below for now) and the format line. Original idea: big rounded cover, centered title in the accent color with "Artist - Album", a quick-action row (sleep timer, speed, repeat, shuffle), a large round play button with previous / next and seek back / forward 10 s, thin seek bar with times and a format line ("48 kHz 256 kbps mp3", needs the Player to read bitrate and sample rate).
- [ ] **Library home as a list:** one row per category with a colored icon (All Songs, Folders, Albums, Artists, Playlists...) instead of chips. New categories need tags we don't read yet: Album Artists, Genres, Years, Composers, plus a Folders hierarchy (tree) next to the flat Folders list.
- [ ] **Search as its own screen:** search box with scope chips (All, Albums, Artists, Album Artists, Folders), a Shuffle / Play / Select row, and a search history with a cross per entry and "Clear search history".
- [ ] **EQ screen:** vertical sliders (preamp + 10 bands from 31 Hz to 16 kHz), a response-curve preview, Equ / Tone / Limit switches, a preset chip, Bass and Treble knobs. Android's built-in equalizer often has only 5 bands, so a true 10-band EQ needs our own audio processing.
- [ ] **Persistent mini player** with a progress line under every screen, including Now Playing's neighbors, and a **bottom bar** (Library, EQ, Search, Queue). Our Controller already has a mini bar under the tabs; the bottom bar would replace the top tabs, which is a big navigation change.
- [ ] **Menu with shortcuts** (Settings, Lyrics, Playlists, Skin settings, Library, Changelog, Help) and named skins (relates to the skinning engine).

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
