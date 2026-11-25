# What is built and what is not

Updated for **`v1.0.0`**. This is the owner's list (UX handoff, Poweramp-inspired ideas, lyrics, releases, and later requests), kept honest: *built* means it has automated tests; **most of it has not been tried on a phone yet**, see [docs/19_PHONE_TEST_CHECKLIST.md](19_PHONE_TEST_CHECKLIST.md) (start at section 14).

Inspiration only: own look and own code, see [docs/15](15_UX_DESIGN_GUARDRAILS.md). Privacy: [docs/21_PRIVACY.md](21_PRIVACY.md).

---

## Not done

### Planned next (not coded yet; the owner chose to wait, credits are low)

**1. A true 10-band equalizer** is **built (not yet tried on a phone)**, see Done. What is still open of "our own audio effects": a compressor, stereo width, a real bass boost and reverb. Android's `DynamicsProcessing` (the effect used for the equalizer) also has a multiband compressor, so a compressor is the easy next one; the others would need our own processing (see the note under *Known limits*).

**2. Auto-tagging the local library** (from [remotetuneslocallibrary.md](remotetuneslocallibrary.md); the owner has about 2,000 songs)
- Rule: trust good tags; fill only what is missing; correct only on a high-confidence match; send doubts to a review queue; never silently overwrite.
- Already built that this uses: *Update tags from files* (reads genre, year, album artist, composer, Replay Gain), *Edit info*, and **writing tags into files** (title, artist, album, track number; read back to check; *All files access*), plus the *Album art finder*.
- Phases:
  - [ ] **1. Scan and report:** a *Tag cleanup* screen with counts (complete, missing title / artist / album / artwork, possible mismatches). Changes nothing.
  - [ ] **2. Safe auto-fill:** parse the file name when tags are missing; fill only empty fields; progress; resumable (a `tag_jobs` table with the statuses pending, processing, tagged, needs review, no match, failed, skipped).
  - [ ] **3. AcoustID / MusicBrainz:** fingerprint only the songs that need help, confidence scoring, conflict detection, a **review queue** (*Keep current* / *Use suggestion* / *Skip*) and *Approve all high-confidence*. Needs a fingerprint library for Android (to choose) and an AcoustID key (kept out of git, like the Jamendo ID). It works for known commercial recordings, so personal recordings, remixes and live versions will often be *no match*.
  - [ ] **4. Batch tag writing:** write the cleaned tags into the files on request, with an undo or backup, progress, and the *All files access* rule. (Single-song writing exists; the batch and the undo do not.)
  - [ ] **5. Cloud Library preparation:** pick cleaned songs to upload (see 3).
- Not now: AI genre / mood / BPM, lyrics tagging, automatic artwork downloads, silent overwriting, uploading during tagging.
- Names are sent to MusicBrainz / AcoustID, so add them to the [privacy page](21_PRIVACY.md) with their own switch.

**3. A personal Cloud Library** (from [remotetunescloud.md](remotetunescloud.md))
- What: your own songs stored in **Cloudflare R2** (one account, bucket `remotetunes`, public development URL, test song verified; keys stay private and never go in git) with the catalog (songs, artists, albums, genres, playlists) in **Supabase**. It is one more music source beside *This phone*, the *Online Library* (Jamendo) and other apps. Songs stream from R2 to whichever phone plays; the player gets a normal URL (the existing *play a link* path), so playback itself does not change.
- Since the doc was written the app became player-first: a cloud song can play on **this phone** (like an Online Library track) or, when controlling another phone, on that one with the existing `playUrl` command. The Cloud Library should appear like the Online Library does (a Library category, searchable, *Play*, *Add to queue*), and cloud songs behave like internet tracks in the queue (no gapless or crossfade into them, no Replay Gain unless their tags are stored).
- Phases:
  - [ ] **8.1 Minimum:** a Cloud Library list, search by title, play, add to queue; a basic `songs` table; songs uploaded by hand through the Cloudflare dashboard.
  - [ ] **8.2 Better browsing:** artists, albums, genres, artwork, sort, recently played, genre filters.
  - [ ] **8.3 Upload and manage:** upload from the phone (with the auto-tagging above and a review screen before saving), edit, delete, duplicate detection.
  - [ ] **8.4 Private access:** a private bucket with short-lived signed URLs and owner-only access, only if needed (the public URL means anyone who has the exact link can fetch the file).
- Rules: one Cloudflare account only; MP3s in R2, never in Supabase Storage; only songs you own or may host (not Spotify or YouTube songs); stay offline-first; no accounts, sharing, recommendations or DRM in v1; no automatic uploads of the whole library.
- Free tier: 10 GB of storage on R2 is roughly 2,500 songs at 128 kbps; no egress fees.
- Privacy: song titles and the files themselves would go to your own R2 and Supabase; add this to the privacy page when built.

**4. Insights: a statistics dashboard with charts** (from [remotetunes-visualization.md](remotetunes-visualization.md))
- What it is: stat cards, a genre doughnut, top artists, library growth, tag-cleanup progress and (later) cloud storage use, drawn with **FL Chart** (`fl_chart`, free and open source, no network use). **Not the audio Visualizer**: the bars under the cover stay as they are. To avoid mixing the two up, the screen is called **Insights** (a menu entry), not "visualization". The doc says "replace the current visualization", but there is no statistics screen today, so this is new.
- Rules from the doc: only bar, doughnut and line charts, progress bars and stat cards; 5 to 7 categories per chart with the exact numbers beside them; stable colors per genre (not random per rebuild); theme colors and skins respected; charts open a useful filtered list only when tapping makes sense (for example the *Rock* slice opens the Rock songs with *Play all* / *Add all to queue*); no radar, network, 3D or heatmap charts; **aggregate in SQL**, never load all 2,000 songs for a chart.
- Reusable widgets planned: `GenrePieChart`, `TopArtistsBarChart`, `LibraryLineChart`, `TagCleanupBarChart`, `StorageProgressCard`, `StatCard`.
- What the library already records (so these need no new data): genre, year, artist, album, duration, file size, **date added**, **play count**, **last played**. So *genre distribution*, *top artists*, *songs per album*, *songs added over time*, *most played songs / artists*, totals and *total size* can be built now.
- What is missing: there is **no log of individual plays** (only a count and the last time), so *plays over time*, *plays this week / month* and *listening time* need a small play-events table first; the doc itself says not to build playback analytics unless that data exists. Tag-cleanup charts need item 2, and the storage-use card needs item 3.
- Phases (the doc's, with what depends on what):
  - [ ] **1. Foundation:** add `fl_chart`, the reusable widgets above, the Insights screen and its menu entry, in the app's theme.
  - [ ] **2. Library insights** (no other work needed): totals, genre distribution, top artists, songs per album, recently added, songs added over time, size on the phone.
  - [ ] **3. Tag cleanup charts:** after item 2 phase 1 exists (progress bar plus a bar chart of updates / needs review / no match).
  - [ ] **4. Cloud Library charts:** after item 3 (R2 storage used of 10 GB, genre distribution, uploads per month).
  - [ ] **5. Playback insights:** first record each play (song, time, how long it was heard); then most played, plays over time, listening time and plays by genre. Plays would stay on the phone.
- Privacy: everything is computed on the phone from its own library; nothing is sent anywhere.

**5. Online Library home screen (Jamendo): built (not tried on a phone yet), see Done.** Left over: a *Top this week* shelf per genre, and a refresh of the shelves in the background.

**What to listen for in your own library: most played, most skipped** is **built (first step, not tried on a phone yet)**, see Done. Still open from it: a log of every play (for *plays this week*, *listening time* and charts), and header totals.

**4. Insights: a statistics dashboard with charts** (from [remotetunes-visualization.md](remotetunes-visualization.md))
- What it is: stat cards, a genre doughnut, top artists, library growth, tag-cleanup progress and (later) cloud storage use, drawn with **FL Chart** (`fl_chart`, free and open source, no network use). **Not the audio Visualizer**: the bars under the cover stay as they are. To avoid mixing the two up, the screen is called **Insights** (a menu entry), not "visualization". The doc says "replace the current visualization", but there is no statistics screen today, so this is new.
- Rules from the doc: only bar, doughnut and line charts, progress bars and stat cards; 5 to 7 categories per chart with the exact numbers beside them; stable colors per genre (not random per rebuild); theme colors and skins respected; charts open a useful filtered list only when tapping makes sense (for example the *Rock* slice opens the Rock songs with *Play all* / *Add all to queue*); no radar, network, 3D or heatmap charts; **aggregate in SQL**, never load all 2,000 songs for a chart.
- Reusable widgets planned: `GenrePieChart`, `TopArtistsBarChart`, `LibraryLineChart`, `TagCleanupBarChart`, `StorageProgressCard`, `StatCard`.
- What the library already records (so these need no new data): genre, year, artist, album, duration, file size, **date added**, **play count**, **last played**. So *genre distribution*, *top artists*, *songs per album*, *songs added over time*, *most played songs / artists*, totals and *total size* can be built now.
- What is missing: there is **no log of individual plays** (only a count and the last time), so *plays over time*, *plays this week / month* and *listening time* need a small play-events table first; the doc itself says not to build playback analytics unless that data exists. Tag-cleanup charts need item 2, and the storage-use card needs item 3.
- Phases (the doc's, with what depends on what):
  - [ ] **1. Foundation:** add `fl_chart`, the reusable widgets above, the Insights screen and its menu entry, in the app's theme.
  - [ ] **2. Library insights** (no other work needed): totals, genre distribution, top artists, songs per album, recently added, songs added over time, size on the phone.
  - [ ] **3. Tag cleanup charts:** after item 2 phase 1 exists (progress bar plus a bar chart of updates / needs review / no match).
  - [ ] **4. Cloud Library charts:** after item 3 (R2 storage used of 10 GB, genre distribution, uploads per month).
  - [ ] **5. Playback insights:** first record each play (song, time, how long it was heard); then most played, plays over time, listening time and plays by genre. Plays would stay on the phone.
- Privacy: everything is computed on the phone from its own library; nothing is sent anywhere.

**5. Online Library home screen (Jamendo): built (not tried on a phone yet), see Done.** Left over: a *Top this week* shelf per genre, and a refresh of the shelves in the background.

**What to listen for in your own library: most played, most skipped** (changes item 4)
- The owner's question: is a chart dashboard needed, when what he wants to know is *which song is played most, skipped most*? Decision: **lists first, charts second.** A ranked, tappable list does that better than any chart: tap a song to play it, long-press to queue it.
- What is recorded today: only a play count and the last time played. There is **no skip count and no log**, so "most skipped" cannot be answered yet.
- Plan: record one small **play event** per song played (song, when it started, how long it was really heard, and how it ended: *finished*, *skipped* (left before 30 seconds or before half of it), or *stopped*). It stays on the phone and can be cleared (Settings). Old play counts are kept as they are.
- **Insights screen, first version (lists, no new package needed):** Most played · Most skipped · Recently played · Never played · Played this week · and by artist / genre. Each row shows the number (plays, skips, minutes). A small header of totals (songs, hours of music, size).
- Charts (FL Chart, item 4 above) then become an optional second step: a genre doughnut and a songs-added line are the only two worth having at first.
- [ ] play events recorded (with a switch and *Clear*) · [ ] the lists · [ ] header totals · [ ] charts later

**6. A better audio Visualizer: built (not tried on a phone yet), see Done.**

**7. Backup and restore to another phone: built (not tried on a phone yet), see Done.** Left over: a matching report that lets you pick a song by hand for the ones not found; edits made before `v1.0.7` are not remembered (there was no flag), only later ones.

**8. List options, per list: first step built after `v1.0.12` (not tried on a phone yet).** Built: the sheet, *View as* (List, List small, List compact, List no images, 1 line, Grid) and *Show titles only*, remembered per kind of list. Left: header with count and total time, pinch-to-zoom, list position, per-track progress, the song menu inside the grid (long-press picks a song there). (the owner's idea, from the screenshots `docs/arts/drawer_part_1.jpg` and `drawer_part_2.jpg`; the layout idea is free to follow, we draw our own)
- What the screenshots show: a gear / *List options* sheet that opens from a song list, titled for the kind of list (*List Options: Playlist Songs*), with settings **remembered per kind of list**:
  - **List memory:** *List position* (come back to where you were in this list when you start it with Play or move with previous / next) and *Per track progress* (each song remembers how far you listened, handy for long recordings).
  - **Layout:** *Compact header* and *Show titles only*.
  - **View as** (radio buttons, also changed by **pinch-to-zoom** on the list): *Grid* in four sizes (normal, small, extra small, 1 line small), *List* (normal, small, compact, **no images**) and *1 line* / *1 line extra small*.
  - A header with the list's cover and name, **how many songs and how long** (`128 | 9:07:26`), and a row of actions (shuffle, play, search, Select, a menu); rows show `3:59 | mp3` under the title.
- What we already have to build on: *Song list > Text size* (Small, Medium, Large), the Back-returns-to-the-same-spot memory, Select, and the format reader (kHz, kbps, type). What is new: choosing the **view** (list / grid / one line / no images), settings kept **per kind of list** (All Songs, Album, Artist, Playlist, Queue, Most played...), pinch to zoom, the list header with count and total time, and per-track progress.
- Proposed first step: one *List options* sheet reachable from every song list, with *View as* (List, List small, List compact, List no images, 1 line, Grid) and *Show titles only*, remembered per kind of list; then the header with count and total time; then pinch-to-zoom; per-track progress last (it changes playback).
- [x] the sheet and the views · [x] per-list memory · [ ] header with count and total time · [ ] pinch-to-zoom · [ ] per-track progress

**9. Settings, grouped: built (not tried on a phone yet), see Done.**

**10. One-tap rescan of the music folders: built (not tried on a phone yet), see Done.** Left over: a switch *Rescan when the app opens* (quiet, a few seconds); folders added before this version are not remembered until they are added once more; a song retagged while being moved is added as a new song and the old one is offered for removal (it is not matched by tags yet).

**11. Edit info: look the song up (metadata, lyrics and cover in one go): built after `v1.0.11`, not tried on a phone yet.** (the owner's idea)
- In a song's menu > Edit info, a button **Look up this song**: one query for the one song, with a result sheet to choose from.
  - **Details:** a search of MusicBrainz by title + artist (+ album, length) lists up to five matches, each with title, artist, album, year and track number; tap one to fill the Edit info fields (you can still change them before saving). Only the title, artist, album and length are sent, as the art finder already does.
  - **Lyrics:** shows whether lyrics were found (LRCLIB, then Megalobiz, then lyrics.ovh, as in the lyrics view) and a preview of the first lines, with *Use these* (kept on the phone like any lyrics) or *Not these*. This is also the way to get lyrics again after a miss (a miss is otherwise remembered for a day).
  - **Cover:** the cover from the Cover Art Archive for the chosen match, shown as a picture to accept or skip; accepted, it becomes the album's picture on this phone (all songs of that album).
  - One *Apply* saves what was ticked: the fields (and, with *Also write into the music file* ticked, into the file), the lyrics, the cover.
- Reuses: the album-art finder (MusicBrainz + Cover Art Archive), `LyricsService`, `TagWriter`. New: a MusicBrainz recording search and the result sheet.
- Privacy page: add *looking up one song* (the same names and the same two services as the art finder).
- [ ] the search and result sheet · [ ] lyrics preview · [ ] cover preview · [ ] Apply · [ ] tests with a fake MusicBrainz

**12. Edit info for several songs at once** (the owner's idea)
- In the Library, after **Select** (long-press) and picking songs, an **Edit info** button opens a version of the dialog that only has the fields that make sense for a group: **Artist, Album, Album artist, Genre, Year** (and Composer). **Title and track number are never offered** (they belong to one song).
- Each field starts as *unchanged*: it shows the value when every picked song has the same one, or *(different)* when they differ; only the fields you type into are changed, on every picked song. A tick on a field can *clear* it.
- *Also write into the music file* is ticked from the start, as in the single-song dialog; the report says how many files were written and how many were refused by Android (with the *All files access* hint). Each changed song is marked as edited, so a backup carries the change.
- Needs: the tag writer to also write year, genre and album artist (title, artist, album and track number only today); a repository method that changes the same fields on many songs in one go.
- [ ] the group dialog · [ ] repository update for many songs · [ ] tag writer: year, genre, album artist · [ ] report · [ ] tests

Suggested order: **1** first (the owner's choice, and it stands alone), then **5** (the Online Library home: built), then **6** (the visualizer: built), then the **most played / most skipped lists** and **4 (phases 1 to 2)**, then **2 (phases 1 to 2)**, which prepares **3** and feeds the Insights tag-cleanup charts.

---

### To check by hand (owner)
- [ ] Try the phone checklist, sections 14 to 19 (everything since `v0.7.0`: crossfade, tag writing, visualizer, leaving folders out, lock screen, EQ, lyrics, menu, skins...). Group play and Auto-align were verified earlier on two phones.
- [ ] Lock screen on the **GT 30 Pro** did not show the player (it works on the Note 10 Pro); probably a phone setting, parked.
- [ ] Free space on the C: drive (it was nearly full).
- [ ] GitHub Pages: Settings > Pages > Source: GitHub Actions (once), for the web Controller.

### Known limits (built, but not as far as it could go)
- [ ] **True 10-band EQ needs Android 9 or newer** (it uses Android's `DynamicsProcessing`) and a phone that allows it; otherwise the ten sliders are blended onto the phone's ~5 bands, and the screen says which of the two is running. Other effects (stereo width, reverb) would need our own audio processing, which `just_audio` has no hook for.
- [ ] **Replay Gain** reads the tags only; *measuring* loudness for files that have none needs decoding every file.
- [ ] **Writing tags into files** depends on Android: files in shared folders are refused unless *All files access* is on (Settings). It writes title, artist, album and track number only (not genre, year, cover).
- [ ] **Visualizer** needs the microphone permission (Android's rule for reading the sound; nothing is recorded), works only for this phone's own playback, and some phones or outputs may refuse it.
- [ ] **Crossfade** works only between songs that are files on this phone (not internet tracks); songs shorter than about twice the fade just change.
- [ ] **Group play card** shows only while controlling another phone.

### Ideas not started
- [ ] A **user guide for friends** (a shorter, friendlier version of [22_USER_GUIDE.md](22_USER_GUIDE.md)). Wanted later; for now the app is for personal use only.
- [ ] Leave files out by pattern (for example "everything named *intro*"), or an exclude list you can edit by hand (today: untick folders and songs, and the *Excluded from library* screen).

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
- [x] **True 10-band equalizer** (built after `v1.0.0`, **not tried on a phone yet**): in the *10 bands* view the ten sliders (31 Hz to 16 kHz) are ten real filters, using Android's `DynamicsProcessing` effect on each player's audio session (so crossfade, gapless and the visualizer are untouched). *Limit* becomes a real limiter. The phone's own equalizer stays flat while it runs. If a phone refuses it (Android 8 or older, or a maker that blocks it), it falls back to blending onto the phone's bands, and the screen says which is in use.
- [x] **Replay Gain** from tags (Off / By song / By album); it never turns a song up.
- [x] **Visualizer** (Settings, off by default): 24 moving bars under the cover; follows whichever player is audible.
- [x] Lock screen / notification: cover, length, shuffle / repeat / speed, a heart for library songs; own channel; rebuilt only when something changes.

### Library and search
- [x] Categories: All Songs, Folders, **Folder tree**, Albums, Artists, Album Artists, **Composers**, Genres, Years, Favorites, Recent, Top, New, Playlists.
- [x] Search: sections, *See all*, history, Album Artists, Play / Shuffle, and **Select** (pick songs for the queue or a playlist).
- [x] Folders: multi-select to a playlist or the queue; Back returns to the same spot with the folder tinted.
- [x] **Edit info** (title, artist, album, track number) and **write into the music file** (read back to confirm; **All files access** switch in Settings for Android 11+).
- [x] **Adding music:** *Choose what to add* lets you untick folders (and single songs) to leave out; remembered; *Excluded from library* (Settings) lists them and lets them back in; a removed song does not return when its folder is added again; an optional *also remove their songs already in the library*; and every add ends with a **report** (found, added, already there, left out, removed, skipped with reasons). The screen stays on while it runs.
- [x] Album art finder (MusicBrainz + Cover Art Archive, on request); *Update tags from files* (genre, year, album artist, composer, Replay Gain).

### Lyrics
- [x] LRCLIB, then **Megalobiz** (timed lyrics when LRCLIB has none, credited), then lyrics.ovh; kept on the phone (30 days; a miss 1 day).
- [x] Redesign: the cover fades out and a lyrics card fades in at its size (gradient in the accent color, the sung line big and bright), tap a line to jump, **Show fullscreen**.

### One-tap rescan (built after `v1.0.10`; not tried on a phone yet)
- [x] The app **remembers the folders you add** (Settings > Library > *Music folders and rescan* lists them with how many songs and when they were scanned; the cross forgets one, the songs stay). **Rescan music folders** (in the Library + menu, first item, and on that screen) goes through all of them in one tap: new songs are added, songs whose file you **moved** are followed (playlists, hearts and counts kept), the left-out list is respected, and the report says how many folders were scanned.
- [x] **A folder that was not there last time** is asked about first (*A new folder*: the new folders, with how many songs, all ticked; the unticked are left out and remembered as left out, and are not asked about again). Everything else just happens.
- [x] **Missing songs** (their file is gone and was not found moved) are listed after the report: *Keep them* (the main button) or *Remove N from the library* (not put on the left-out list, so they come back if the file does). If **most** songs of a folder are missing, it asks whether the storage (an SD card, a drive) is connected, and a folder that cannot be reached is named in the report and its songs are not called missing.
- [x] A folder inside a remembered one is covered by it; adding a folder that holds remembered ones replaces them.

### Queue, cover buttons, backup and write-to-file (built after `v1.0.9`; not tried on a phone yet)
- [x] **Queue rows:** swipe **left** to remove (a message with **Undo** puts it back where it was; a link from the Online Library is removed without Undo), swipe **right** to add the song to a playlist (the row stays). The cross and the add-to-playlist buttons are gone from the rows. **Long-press** a row to pick several (tap picks more, *Select all*, *Cancel*): then **Add selected to a playlist** (links are left out of the list) or **Remove selected from the queue**. Swiping and dragging are off while picking.
- [x] **Cover buttons swap:** the *Add to a playlist* button on the cover (top left) gives that corner to *Show fullscreen* while the lyrics show, and comes back with the cover.
- [x] **Edit info:** *Also write into the music file* is **ticked from the start** (untick it to change the library listing only; if Android refuses the file, the change is still saved and the message says so).
- [x] **List options (first step, after `v1.0.12`):** a *List options* button (sliders icon, top right of every song list) opens a sheet named for the kind of list (All songs, Favorites, Most played, Album songs, Playlist songs...). *Show titles only* hides the artist line; *View as* picks List, List small, List compact, List no images, 1 line or Grid. A change applies at once and is remembered for every list of that kind (and goes in backups). The standard look is the list as before. Not on the web Controller.
- [x] **Visualizer on the cover (Settings > Visualizer > *Show it on the cover*, off by default):** the visualizer is drawn over the dimmed cover instead of under it. Opening the lyrics removes it and closing them brings it back, so the two are never shown together. Off: it behaves exactly as before. Saved in backups.
- [x] **Edit info for several songs (item 12) and *Look up this song* (item 11)** are built (see their items above); the look-up sends only title, artist, album and length (docs/21).
- [x] **Visualizer button on Now Playing:** in the row of quick actions (favorite, shuffle, repeat, speed, sleep timer), just to the **left of the volume button**: a tap shows or hides the visualizer (saved, same as the Settings switch; turning it on asks for the microphone permission first). On a narrow phone the seven buttons get a slightly smaller touch area so they all fit.
- [x] **Backup:** *Playlists, favorites and counts* is its own switch, and *Choose lyrics and album art only* sets the switches for a backup that holds just those two.

### Settings, grouped (built after `v1.0.7`)
- [x] Settings opens on a short list of **groups** (Playback and sound, Library, Look, Lyrics and online, Other phones and connection, Updates and about) plus a **Backup and restore** row; each group opens its own page. A **search box** at the top finds a setting by its name or by other words people use (vibration, replay gain, spotify, supabase...) and shows it in place, ready to change. Nothing about how settings are saved changed.

### Moved songs followed on rescan (built after `v1.0.7`)
- [x] Moving a song file to another folder and adding the folder again now **relinks** the song (playlists, hearts and counts kept) instead of skipping it as a duplicate; the report says *Moved*.

### Backup and restore (built after `v1.0.5`; not tried on a phone yet)
- [x] **Settings > Backup and restore.** *Back up to a file* makes `RemoteTunes-<date>.rtbackup` (compressed JSON, no audio) with: playlists (in order), favorites, play / skip counts and last played, the left-out list, lyrics found so far (switch), and the safe settings (switch: look, equalizer and its per-output memory, crossfade, visualizer style, list size...). Never in it: Jamendo ID, pairing, Supabase keys, device name.
- [x] **Restore** reads the file, shows what is in it, and asks *Where is your music on this phone?* (the old place is shown; if the same folder exists it is chosen). Songs are found by **path under the new root**, then by **title + artist + album + length** (one second either way), then by **title + artist** when only one song has them (said in the report). Songs not found are listed, never guessed. It only adds and merges: playlists of the same name are merged (nothing twice), counts keep the larger number, this phone's own lyrics are never replaced, settings can be skipped, and only the safe settings are ever written whatever the file says.
- [x] **Album art** (switch, shows how many covers and how big): one cover per album (the ones from the files and the ones the art finder found), saved inside the file, and put back on the matching albums of the new phone, **only where there is no picture yet** (yours are never replaced). The file is now a zip (`backup.json` + `art/`); backups from `v1.0.6` (gzipped JSON) are still read.
- [x] **Edited song info** (Edit info) is remembered from now on (a flag on the song, schema v11) and put on the same file on the new phone (title, artist, album, track number).
- Limits: songs added with **Add songs** are copies kept inside the app, so the backup cannot bring them back; add the music folder on the new phone before restoring.

### Built after `v1.0.4` (none of it tried on a phone yet)
- [x] **Shuffle keeps track of what has played:** a round plays every song once; a song that played (or was chosen) does not come up again until the round is over; with repeat on a new round starts and never opens with the song that just ended. Back and Next walk the same path, *Play next* joins right after the song playing, added songs join the round, removed songs leave it.
- [x] **Next and Previous crossfade** (when Crossfade is on, a song is playing and the next is a file on this phone): the screen switches at once and the old song fades out underneath. Paused, links, or a fade already running: the ordinary change. A seek during the fade seeks the new song.
- [x] **Visualizer:** tap it on Now Playing to go to the next style (the name shows for a moment; the choice is remembered). The Circle style is gone; there are six horizontal ones: Bars, Mirror, Wave, **LED**, **Spread**, **Dots**.
- [x] **Default pictures** (from `docs/arts`, cropped square into `assets/art`): songs without a cover show the default album art (lists, Now Playing, mini player, Online Library); artists show the default artist picture.
- [x] **Add to playlist everywhere:** artist, album, genre, year, album artist and composer rows have a menu (Play / Add to queue / Add to playlist) and the page of one of them has *Add all to a playlist*; search results (songs, albums, artists, album artists) and songs in the folder tree have a menu; every Queue row has an add-to-playlist button; Now Playing has one on the cover (top left). Inside a playlist you can also remove several songs at once (pick them, then the remove button).
- [x] **Counts:** the Library list shows how many are in each category (All Songs, Folders, Albums, Artists, Genres... Most played, Never played, Playlists), and Most played / Most skipped show the number in bold at the right of each song ("12 plays", "3 skips").
- [x] The Queue shows *Artist · Album* on each row (and the Up next sheet too).

### Most played, most skipped, never played (built after `v1.0.3`; schema v10)
- [x] Library > **Most played** (was *Top*; shows how many plays), **Most skipped** (how many skips) and **Never played**. A **skip** is leaving a song before 30 seconds of it were heard (or before half of a shorter song) by pressing next or choosing another song; finishing a song, seeking, and paused time are never skips; links and Online Library tracks are not counted. Counts start from zero now (older plays stay as they were). They also show on the other phone when controlling it.
- [x] Settings > *Reset play and skip counts* starts them again from zero.
- Not done: playlists cannot hold Online Library (Jamendo) tracks (they are not in the library); a menu for whole *folders* (the Folders list already has multi-select to a playlist); a play-by-play log, *plays this week*, *listening time*, header totals and charts (see Insights below).

### Visualizer, second version (built after `v1.0.2`)
- [x] The bars are smoothed at **60 frames a second** (Android's about 20 readings a second are eased between: quick rise, slow fall), with **caps** that hold a moment and then fall; the spectrum is **evened out** (bass eased, treble lifted), the song's loudness is followed (a quiet song fills the display like a loud one), and a noise gate keeps silence flat.
- [x] Four **styles** (Settings > Visualizer, then pick one): **Bars** (rounded, glow, caps), **Mirror**, **Circle** (a ring, taller area) and **Wave** (a glowing line). Colors from the skin and the cover's accent. The bars fall away smoothly when you pause.

### Version and updates (built after `v1.0.2`)
- [x] The installed version is shown in the **menu** (under the name), **Settings > App updates** (version and build) and **Diagnostics** (it used to say 0.1.0, the number in the source file). The automatic update check and the *newer version* card had stopped when the Home screen was retired: they are back (a card at the top of the app and a line in the menu).

### Online Library home (built after `v1.0.1`)
- [x] Before any search the Online Library shows shelves of covers: **Popular this week**, **Popular this month**, **Newest releases** (Jamendo sorts them: `popularity_week`, `popularity_month`, `releasedate_desc`), and genre chips (*Top tracks by genre*). Tap a cover to play on the Player, press and hold to queue it, *Play all* / *Add all* on each shelf. Shelves load one after another (Jamendo wants spaced requests), are kept for 15 minutes, pull down to refresh; no internet shows the usual message and *Try again*. Settings > *Suggestions in the Online Library* (on by default) switches it off; then the tab stays blank until a search.

### Remote playback, group play, web
- [x] Pairing with QR / nearby / code, trusted devices, reconnect; the web Controller on GitHub Pages; External App Control; the Online Library (Jamendo).
- [x] Group play and Auto-align (verified on two phones).

### Docs
- [x] [User guide for the owner](22_USER_GUIDE.md): where things are and how they work. It is also **inside the app** (Menu > Help > *The full guide*: sections that open, and a search box); it is the same file, bundled at build time.
- [x] [Privacy page](21_PRIVACY.md): everything that leaves the phone and how to switch it off. README updated.

---

## History of the releases (short)
`v0.2` updates, gapless, haptics, queue peek · `v0.3` lyrics, folders, edge swipes · `v0.4` lock screen, art finder, tag editor · `v0.5`–`v0.6` Now Playing v2, library list, search · `v0.7`–`v0.8` music player first, controller as a mode · `v0.9` crossfade, EQ, Replay Gain · `v0.10` pairing popup, folder multi-select, screen on · `v0.11` lyrics redesign · `v0.12` retired the classic screens, menu, privacy page, composers, folder tree, Megalobiz, skins, queue scroll, tag writing (`v0.12.1`: crossfade fix) · `v1.0.0` the guide inside the app (Help) · `v0.13` All files access, 10-band EQ, visualizer, leaving folders and songs out, the add report.
