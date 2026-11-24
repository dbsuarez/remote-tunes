# Next tasks

What is built and what is still to do, from the owner's lists (the UX handoff, the Poweramp-inspired ideas and screenshots, lyrics, releases). Updated at release `v0.6.0`.

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
- [ ] **Crossfade:** a fade between songs. Needs a second player (or a volume ramp) and a length setting; must stay compatible with gapless.
- [ ] **EQ:** Android's built-in equalizer usually has only 5 bands and differs per phone; a true 10-band graphic EQ needs our own audio processing. Start with the built-in one, per-output presets (speaker / wired / Bluetooth), then the screen below.
- [ ] **Replay Gain scanner** (background isolate; needs a new column and a re-scan of the library).

### Library and search
- [ ] Album Artists, Genres, Years and Composers (need tags we do not read yet: schema change and a re-read of the files) and a folder tree next to the flat Folders list.
- [ ] Search: an Album Artists scope, and a Shuffle / Play / Select row on the results.
- [ ] Tag editor: write the tags into the music files (needs a writer and Android 11+ file-edit permission); today it only changes RemoteTunes' listing.

### UI / UX
- [ ] **EQ screen:** vertical sliders (preamp + 10 bands, 31 Hz to 16 kHz), a response-curve preview, Equ / Tone / Limit switches, a preset chip, Bass and Treble knobs.
- [ ] **Bottom bar** (Library, EQ, Search, Queue) with a persistent mini player and progress line on every screen. A big navigation change: it would replace the top tabs.
- [ ] **Menu with shortcuts** (Settings, Lyrics, Playlists, Skin settings, Library, Changelog, Help).
- [ ] **Skinning engine** (JSON themes, named skins) that respects the album-art accent and the design guardrails.
- [ ] **Visualizer tab** (Player only). Needs audio analysis; the microphone permission or a simulated animation.
- [ ] Now Playing v2 on the **Player's own screen** (it still has the small card), and the edge swipes there.
- [ ] A **favorite button** on the lock screen.

### Lyrics
- [ ] Megalobiz fallback (scraping a site that asks for attribution; skipped unless LRCLIB misses a lot).
- [ ] A note in the privacy documents that lyrics, album-art and update checks contact LRCLIB / lyrics.ovh, MusicBrainz / Cover Art Archive and GitHub (the Settings text already says what is sent).

### Direction: a music player first, the Controller as a mode (all three steps wanted, planned for later)
The app should look like a normal music player; the Controller is reached by a button or tab and its extra settings live behind it. For the owner the Controller is the main use, so the app should be able to open straight into it. The Library, Queue, Now Playing and Search screens already work on either source (`MusicSource`), so this is mostly a new shell.
- [ ] **Step 1 (quick):** an "Open in" setting that skips Home and goes straight to Player or Controller, auto-reconnecting to the last Player.
- [ ] **Step 2 (medium):** the bottom-bar shell (Library, Now Playing, Search, Queue) with a mini player on every screen, playing this phone's own music. Looks like a plain music player by default.
- [ ] **Step 3 (larger):** merge the Controller into that shell as a source switch ("This phone" / a Player) behind a Remote button; pairing, QR, online room and group play behind it and in Settings; retire the Home and role screens. A **"Start remote playback" button** starts the Player server on demand (and a Stop button ends it), instead of Player mode having to be open: it shows the QR / pairing code and who is connected, and keeps a notification while it runs. Off by default, so the app is a plain player and costs no battery or network until pressed; an optional "start automatically" setting for the owner. Default source on a fresh install: this phone; the owner's setting can default to the last Player.

### Verification and housekeeping (owner)
- [ ] Try everything on the phones with `docs/19_PHONE_TEST_CHECKLIST.md`: gapless, lyrics, edge swipes, Now Playing v2, library list, search, album-art finder, lock screen, updates, and group play / Auto-align (never verified).
- [ ] Free space on the C: drive (it was nearly full).
- [ ] GitHub Pages: Settings > Pages > Source: GitHub Actions (once) for the web Controller.
