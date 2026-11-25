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
- [x] **Crossfade** (Settings > Crossfade, 0 to 12 s): two audio players, one fading out while the next fades in (equal power). Only between songs that are files on this phone; with it on, gapless lining-up is replaced by the fade; short songs, repeat-one, internet tracks and the last song just change. Never tried on a phone: it needs listening tests.
- [x] **EQ (built-in):** Android's own equalizer (usually 5 bands, differs per phone) with 9 presets, a slider per band, and settings remembered per sound output (speaker / wired / Bluetooth) that come back when that output is in use. Equalizer icon in the top bar and in Settings. Not done: a true 10-band EQ (needs our own audio processing), the response curve, Tone / Limit switches and Bass / Treble knobs.
- [x] **Replay Gain from tags** (schema v8): Settings > Even out loudness (Off / By song / By album) turns loud songs down to the level in their Replay Gain tags (read by "Update tags from files" and on import). It never turns a song up. Not done: *measuring* loudness for files that have no tags (that needs decoding every file).

### Library and search
- [x] Album Artists, Genres and Years (schema v7; read from the tags; Settings > "Update tags from files" fills in songs added before). Still to do: Composers (the tag reader only gives it for MP3) and a folder tree next to the flat Folders list.
- [x] Search: Album Artists scope and Play / Shuffle for the results. (A Select row is not done.)
- [ ] Tag editor: write the tags into the music files (needs a writer and Android 11+ file-edit permission); today it only changes RemoteTunes' listing.

### UI / UX
- [x] **EQ screen** with sliders, presets, per-output memory, a response curve, Preamp, Tone (Bass / Treble knobs) and Limit. Preamp up uses the phone's loudness enhancer, down lowers the volume. Not done: a true 10-band EQ.
- [ ] **Bottom bar** (Library, EQ, Search, Queue) with a persistent mini player and progress line on every screen. A big navigation change: it would replace the top tabs.
- [x] **Menu with shortcuts** (the button at the top left): Now Playing, Lyrics (opens the lyrics), Library, Playlists (opens the playlists), Search, Queue, Equalizer, Remote playback, Settings, What's new (release notes from GitHub) and Help. Skin settings are added with the skins.
- [ ] **Skinning engine** (JSON themes, named skins) that respects the album-art accent and the design guardrails.
- [ ] **Visualizer tab** (Player only). Needs audio analysis; the microphone permission or a simulated animation.
- [ ] Now Playing v2 on the **Player's own screen** (it still has the small card), and the edge swipes there.
- [x] A **favorite button** on the lock screen / notification (heart; shows only for library songs; may not appear on phones whose system hides notification buttons).

### Lyrics
- [ ] Megalobiz fallback (scraping a site that asks for attribution; skipped unless LRCLIB misses a lot).
- [x] Privacy page: [docs/21_PRIVACY.md](21_PRIVACY.md) lists everything that leaves the phone (lyrics, album art, Online Library, updates, links) and how to switch it off.

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

### Done in the batch after v0.9.0
- [x] Pairing requests pop up over whatever screen is open (no need to open the Remote playback page).
- [x] Keep the screen on while adding songs, updating tags and finding album art.
- [x] Library > Folders: pick several folders (long-press) and add them to a playlist or the queue; Back from an opened folder (or artist, album, playlist, genre...) returns to the same spot in the list with that row quietly tinted, and a search is kept.
- [x] Shuffle and repeat are remembered between runs (they use the Settings > Playback values, which now follow the Now Playing buttons).
- [x] The classic Home / Player / Controller screens are retired (no Home screen, no role buttons, no "Classic start screen"). The connect page ("Control another phone") and the Remote playback page remain; the connected Controller screen is kept only for the web page.

### Lyrics redesign (built, not yet tried on a phone)
- [x] **Fade, then replace:** the lyrics button fades the cover out completely (the first half of a 0.46 s animation) and only then fades the lyrics card in; the lyrics card takes the cover's whole space with a small margin. The button flips back the same way.
- [x] **Show fullscreen:** a button on the lyrics card opens a lightbox-style full-screen view (song name and artist, bigger type, a close button) that keeps following the music and the song behind it.
- [x] **A designed look:** a gradient background in the accent color (so it follows the cover) with a soft glow; the line being sung large, white and bold, nearby lines smaller and dimmer, fading out at the top and bottom edges; a smooth ease to the current line; the credit as a quiet footer; plain lyrics get the same card.
- Kept: tap a line to jump there, the "no lyrics" / "switched off" / retry messages, both phones.

### Verification and housekeeping (owner)
- [ ] Try everything on the phones with `docs/19_PHONE_TEST_CHECKLIST.md`: gapless, lyrics, edge swipes, Now Playing v2, library list, search, album-art finder, lock screen, updates, and group play / Auto-align (never verified).
- [ ] Free space on the C: drive (it was nearly full).
- [ ] GitHub Pages: Settings > Pages > Source: GitHub Actions (once) for the web Controller.
