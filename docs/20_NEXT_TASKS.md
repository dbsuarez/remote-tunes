# Next tasks

What is built and what is still to do, from the owner's lists (the UX handoff, the Poweramp-inspired ideas and screenshots, lyrics, releases). Updated after `v0.7.0` (the next batch is built but not yet released).

Inspiration only: own look and own code, see [docs/15](15_UX_DESIGN_GUARDRAILS.md). Everything below marked done has automated tests; **none of the audio, gesture and layout items have been tried on a phone yet** (see [docs/19](19_PHONE_TEST_CHECKLIST.md)).

---

## Done

### Releases and updates (`v0.2.0` on)
- [x] Release APKs on GitHub Releases, one per CPU type, built on a `v*` tag (`.github/workflows/release.yml`, README "Releases and updates"). Signed with the key your phones already use, so updates keep their data.
- [x] In-app update: Settings > App updates, a card on Home when a newer version exists, checked about once a day. Download is checked (size and SHA-256) and kept until installed; the button says when Android's install screen is open; it carries on by itself after the "allow installs" switch, even if Android restarted the app (`v0.6.0`).

### UX handoff (`docs/handoff.md`, `v0.2.0`)
- [x] Haptics: `HapticButton`, firm tap on play / pause, light on skip, a click on sliders, hearts and selecting. Settings switch.
- [x] Colors from album art: the Controller's accent follows the cover (kept readable, never Spotify green). Settings switch.
- [x] Queue Peek: a draggable sheet on Now Playing with the song playing and the next three, up to the whole queue.

### Audio engine
- [x] Gapless playback for local songs (`v0.2.0`).
- [x] Lock screen / Android 13+ media controls: cover, length, loading state, shuffle, repeat and speed, and they can be changed from there (`v0.4.0`).

### Library and metadata
- [x] Folders view (flat list by folder name; paths never leave the Player), Top (play counts) and New (newest 100) (`v0.3.0`, schema v5).
- [x] Album art finder: Settings > Find missing album art (MusicBrainz + Cover Art Archive; on request; names only) (`v0.4.0`).
- [x] Basic tag editor: Edit info on the Player's library (title, artist, album, track number; changes the listing, not the file) (`v0.4.0`).
- [x] Library as a list of categories on both phones: All Songs, Folders, Albums, Artists, Favorites, Recent, Top, New, Playlists (`v0.6.0`).
- [x] Search screen: scope chips (All, Songs, Albums, Artists, Folders), sections with "See all", tap to play or open, and a history kept on the phone (20 entries, a cross on each, Clear) (`v0.6.0`).

### Lyrics (`v0.3.0`, schema v6)
- [x] LRCLIB (exact, then search) then lyrics.ovh, looked up once per song and kept on the Player (30 days; a miss 1 day). Lyrics button on Now Playing on both phones; synced lines follow the song and can be tapped to seek. Settings switch "Lyrics from the internet".

### Now Playing and gestures (Controller)
- [x] Now Playing v2 (`v0.5.0` / `v0.6.0`): big cover, accent-colored title with "Artist · Album", a quick row (favorite, shuffle, repeat, speed, sleep timer), round play button with previous / next and 10-second back / forward, seek bar with times and the file format line ("48 kHz · 256 kbps · MP3", read by the Player when the song starts).
- [x] Edge swipes on Now Playing (`v0.3.0`): from the right edge raises the queue (middle, then full), from the left edge opens the Library.

---

## Still to do

### Audio engine (Player side)
- [ ] **Crossfade:** a fade between songs. A real overlap needs a second audio player running at the same time as the first, and a length setting; it has to stay compatible with gapless. Not started.
- [x] **EQ (built-in):** Android's own equalizer (usually 5 bands, differs per phone) with 9 presets, a slider per band, and settings remembered per sound output (speaker / wired / Bluetooth) that come back when that output is in use. Equalizer icon in the top bar and in Settings. Not done: a true 10-band EQ (needs our own audio processing), the response curve, Tone / Limit switches and Bass / Treble knobs.
- [x] **Replay Gain from tags** (schema v8): Settings > Even out loudness (Off / By song / By album) turns loud songs down to the level in their Replay Gain tags (read by "Update tags from files" and on import). It never turns a song up. Not done: *measuring* loudness for files that have no tags (that needs decoding every file).

### Library and search
- [x] Album Artists, Genres and Years (schema v7; read from the tags; Settings > "Update tags from files" fills in songs added before). Still to do: Composers (the tag reader only gives it for MP3) and a folder tree next to the flat Folders list.
- [ ] Search: an Album Artists scope, and a Shuffle / Play / Select row on the results.
- [ ] Tag editor: write the tags into the music files (needs a writer and Android 11+ file-edit permission); today it only changes RemoteTunes' listing.

### UI / UX
- [x] **EQ screen** (sliders, presets, per-output memory); the extras (preamp, curve, Tone / Limit, Bass / Treble) are still to do.
- [ ] **Bottom bar** (Library, EQ, Search, Queue) with a persistent mini player and progress line on every screen. A big navigation change: it would replace the top tabs.
- [ ] **Menu with shortcuts** (Settings, Lyrics, Playlists, Skin settings, Library, Changelog, Help).
- [ ] **Skinning engine** (JSON themes, named skins) that respects the album-art accent and the design guardrails.
- [ ] **Visualizer tab** (Player only). Needs audio analysis; the microphone permission or a simulated animation.
- [ ] Now Playing v2 on the **Player's own screen** (it still has the small card), and the edge swipes there.
- [ ] A **favorite button** on the lock screen.

### Lyrics
- [ ] Megalobiz fallback (scraping a site that asks for attribution; skipped unless LRCLIB misses a lot).
- [ ] A note in the privacy documents that lyrics, album-art and update checks contact LRCLIB / lyrics.ovh, MusicBrainz / Cover Art Archive and GitHub (the Settings text already says what is sent).

### Direction: a music player first, the Controller as a mode (built, not yet tried on phones)
- [x] **Step 1:** Settings > "When the app opens": *This phone's music* (default), *Control my last Player* (reconnects to the last trusted Player and controls it) or *Classic start screen* (the old Player / Controller choice).
- [x] **Step 2:** the music-player shell: bottom bar (Now Playing, Library, Search, Queue), a mini player with a progress line under every tab but Now Playing, and a source chip in the top bar. It plays this phone's own music; with nothing playing there is no notification and no foreground service (a normal music player).
- [x] **Step 3:** the Controller is a mode of the same screens. The source chip opens a sheet: *This phone*, *Control another phone* (finds a Player; once connected the same tabs show and control that Player; if it goes away the app falls back to this phone), *Disconnect*, and **Start remote playback** (starts the Player server on demand; Stop ends it; the sheet's row opens the QR / pairing page). Nothing listens on the network until pressed; Settings can start it automatically. Online Library and Play a link are rows in the Library list.
- [x] **Now Playing is the same screen on both phones** (`NowPlayingView` on a `PlaybackSession`: `LocalSession` for this phone, `RemoteSession` for another): big cover, quick row, transport, lyrics, queue peek, edge swipes. The sleep timer is shared by this phone's screen and the Player server.
- [ ] Still to do here: the "Group play" card only shows when controlling another phone; the classic Home / Player / Controller screens are still reachable (Settings > Classic start screen) and could be retired once the new flow is trusted; the Player server's pairing page could show in the shell instead of its own screen; the shell has no tablet / landscape layout.

### Done after v0.7.0 (this batch)
- [x] The queue sheet rests as just a handle (tap or swipe it up).
- [x] Lyrics show inside the cover (button in its top-right corner); the separate Lyrics button is gone.
- [x] The volume is a button in the quick row with a small vertical slider.
- [x] The "Adding music" card has a fixed size (file names no longer make it jump).
- [x] Notification: rebuilt only when something changes (it was rebuilt every second), and it has its own channel with normal importance and no sound. Lock-screen player: see the notes below.
- [x] Group play and Auto-align verified by the owner on two phones.

### Verification and housekeeping (owner)
- [ ] Try everything on the phones with `docs/19_PHONE_TEST_CHECKLIST.md`: gapless, lyrics, edge swipes, Now Playing v2, library list, search, album-art finder, lock screen, updates, and group play / Auto-align (never verified).
- [ ] Free space on the C: drive (it was nearly full).
- [ ] GitHub Pages: Settings > Pages > Source: GitHub Actions (once) for the web Controller.
