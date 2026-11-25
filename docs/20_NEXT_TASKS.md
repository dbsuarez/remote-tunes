# What is built and what is not

Updated after **`v0.13.0`**. This is the owner's list (UX handoff, Poweramp-inspired ideas, lyrics, releases, and later requests), kept honest: *built* means it has automated tests; **most of it has not been tried on a phone yet**, see [docs/19_PHONE_TEST_CHECKLIST.md](19_PHONE_TEST_CHECKLIST.md) (start at section 14).

Inspiration only: own look and own code, see [docs/15](15_UX_DESIGN_GUARDRAILS.md). Privacy: [docs/21_PRIVACY.md](21_PRIVACY.md).

---

## Not done

### To check by hand (owner)
- [ ] Try the phone checklist, sections 14 to 19 (everything since `v0.7.0`: crossfade, tag writing, visualizer, leaving folders out, lock screen, EQ, lyrics, menu, skins...). Group play and Auto-align were verified earlier on two phones.
- [ ] Lock screen on the **GT 30 Pro** did not show the player (it works on the Note 10 Pro); probably a phone setting, parked.
- [ ] Free space on the C: drive (it was nearly full).
- [ ] GitHub Pages: Settings > Pages > Source: GitHub Actions (once), for the web Controller.

### Known limits (built, but not as far as it could go)
- [ ] **10-band EQ is virtual:** Android's equalizer has about 5 bands, so the ten sliders are blended onto them (the screen says so). A true 10-band filter would need our own audio processing.
- [ ] **Replay Gain** reads the tags only; *measuring* loudness for files that have none needs decoding every file.
- [ ] **Writing tags into files** depends on Android: files in shared folders are refused unless *All files access* is on (Settings). It writes title, artist, album and track number only (not genre, year, cover).
- [ ] **Visualizer** needs the microphone permission (Android's rule for reading the sound; nothing is recorded), works only for this phone's own playback, and some phones or outputs may refuse it.
- [ ] **Crossfade** works only between songs that are files on this phone (not internet tracks); songs shorter than about twice the fade just change.
- [ ] **Group play card** shows only while controlling another phone.

### Ideas not started
- [ ] A **user guide for friends** (a shorter, friendlier version of [22_USER_GUIDE.md](22_USER_GUIDE.md)). Wanted later; for now the app is for personal use only.
- [ ] A true 10-band equalizer / our own audio effects (see above).
- [ ] Leave files out by pattern (for example "everything named *intro*"), or an exclude list you can edit by hand (today: untick folders and songs, and the *Left out of the library* screen).

---

## Done

### Releases and updates (`v0.2.0` on)
- [x] Release APKs on GitHub Releases, one per CPU type, built on a `v*` tag (`.github/workflows/release.yml`). Signed with the key your phones already use, so updates keep their data.
- [x] In-app update (Settings > App updates, checked about once a day): size and SHA-256 are checked, the download is kept until installed, it resumes after the install permission, and **What's new** (in the menu) lists the release notes.

### The app as a music player first
- [x] Opens on Now Playing for this phone's songs; bottom bar (Now Playing, Library, Search, Queue), a mini player with a progress line under every other tab, and a source chip (*This phone* / *Control another phone* / remote playback). The old Home / Player / Controller screens are gone.
- [x] **Controller as a mode:** the same screens show and control another phone's music; Now Playing is one screen (`NowPlayingView`) for both. Pairing requests pop up over whatever is open; *Control my last Player* and *Start remote playback* can run when the app opens.
- [x] **Menu** (top-left): Now Playing, Lyrics, Library, Playlists, Search, Queue, Equalizer, Skins, Remote playback, Settings, What's new, Help.
- [x] **Skins:** 7 built-in looks plus your own from pasted JSON (copy any skin to share it); dark-only guardrails; the cover's accent still tints the player.
- [x] **Queue** opens at the song playing (Settings switch, on by default); the **Up next sheet** rests as a handle, opens with a tap or swipe, and closes when you tap the player outside it.
- [x] Haptics, colors from album art, Queue peek, edge swipes (queue from the right, Library from the left), volume as a button with a vertical slider, the format line (kHz, kbps, type).
- [x] Shuffle and repeat are remembered between runs.

### Audio
- [x] Gapless playback for local songs.
- [x] **Crossfade** (Settings, 0 to 12 s): two players, equal-power fade; the next song is loaded early and the fade starts at the right moment (fixed in `v0.12.1`: the first fade used to restart the next song).
- [x] **Equalizer:** Android's bands with 9 presets, per-output memory (speaker / wired / Bluetooth), a response curve, Preamp, Bass / Treble and Limit, plus a **10-band view**.
- [x] **Replay Gain** from tags (Off / By song / By album); it never turns a song up.
- [x] **Visualizer** (Settings, off by default): 24 moving bars under the cover; follows whichever player is audible.
- [x] Lock screen / notification: cover, length, shuffle / repeat / speed, a heart for library songs; own channel; rebuilt only when something changes.

### Library and search
- [x] Categories: All Songs, Folders, **Folder tree**, Albums, Artists, Album Artists, **Composers**, Genres, Years, Favorites, Recent, Top, New, Playlists.
- [x] Search: sections, *See all*, history, Album Artists, Play / Shuffle, and **Select** (pick songs for the queue or a playlist).
- [x] Folders: multi-select to a playlist or the queue; Back returns to the same spot with the folder tinted.
- [x] **Edit info** (title, artist, album, track number) and **write into the music file** (read back to confirm; **All files access** switch in Settings for Android 11+).
- [x] **Adding music:** *Choose what to add* lets you untick folders (and single songs) to leave out; remembered; *Left out of the library* (Settings) lists them and lets them back in; a removed song does not return when its folder is added again; an optional *also remove their songs already in the library*; and every add ends with a **report** (found, added, already there, left out, removed, skipped with reasons). The screen stays on while it runs.
- [x] Album art finder (MusicBrainz + Cover Art Archive, on request); *Update tags from files* (genre, year, album artist, composer, Replay Gain).

### Lyrics
- [x] LRCLIB, then **Megalobiz** (timed lyrics when LRCLIB has none, credited), then lyrics.ovh; kept on the phone (30 days; a miss 1 day).
- [x] Redesign: the cover fades out and a lyrics card fades in at its size (gradient in the accent color, the sung line big and bright), tap a line to jump, **Show fullscreen**.

### Remote playback, group play, web
- [x] Pairing with QR / nearby / code, trusted devices, reconnect; the web Controller on GitHub Pages; External App Control; the Online Library (Jamendo).
- [x] Group play and Auto-align (verified on two phones).

### Docs
- [x] [User guide for the owner](22_USER_GUIDE.md): where things are and how they work.
- [x] [Privacy page](21_PRIVACY.md): everything that leaves the phone and how to switch it off. README updated.

---

## History of the releases (short)
`v0.2` updates, gapless, haptics, queue peek · `v0.3` lyrics, folders, edge swipes · `v0.4` lock screen, art finder, tag editor · `v0.5`–`v0.6` Now Playing v2, library list, search · `v0.7`–`v0.8` music player first, controller as a mode · `v0.9` crossfade, EQ, Replay Gain · `v0.10` pairing popup, folder multi-select, screen on · `v0.11` lyrics redesign · `v0.12` retired the classic screens, menu, privacy page, composers, folder tree, Megalobiz, skins, queue scroll, tag writing (`v0.12.1`: crossfade fix) · `v0.13` All files access, 10-band EQ, visualizer, leaving folders and songs out, the add report.
