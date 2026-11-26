# RemoteTunes: your own guide

For you, when you forget how something works. Plain words, no code. Parts that were built recently may not have been tried on a phone yet: if one misbehaves, note what you saw (and Settings > Diagnostics > Copy) so it can be fixed.

---

## 1. What the app is

A **music player** for the songs on your phone. It can also **control another phone** that has RemoteTunes (so the second phone plays and you steer from the first), play along on both at once, and be driven from a web page.

Your phones: the **Infinix X6873 (GT 30 Pro)** is the main one (most songs, the "Player"). The **X695** is the other phone.

Every phone is its own music player first. "Controlling another phone" is a mode you switch on, not a separate app.

---

## 2. Finding your way around

- **Bottom bar:** *Now Playing*, *Library*, *Search*, *Queue*.
- **Under every tab except Now Playing:** a small player (title, buttons, a thin progress line). Tap it to go to Now Playing.
- **Menu button, top left:** Now Playing, Lyrics, Library, Playlists, Search, Queue, Equalizer, Skins, Remote playback, Settings, What's new, Help. This is the quickest way to anything.
- **The chip at the top** (it says *This phone*): which phone's music you are looking at and controlling. Tap it to switch.
- **Swipes on Now Playing:** from the **left edge** opens the Library; from the **right edge** raises the queue. (If Android's back gesture steals it, start a finger-width in from the edge.)

---

## 3. Getting music in

**Library tab > the + button** (top bar).

- **Add songs**: picks files and **copies** them into the app. Good for a few songs: they stay even if you delete the originals.
- **Add a folder**: reads a whole folder **where it is** (nothing is copied) and needs the music permission. Good for your music folder; if you delete or move the files, the songs show as missing.

### Leaving things out (adding a folder)
After you pick a folder, **Choose what to add** lists its folders, all ticked, with how many songs each holds.

- **Untick a folder** to leave it, and everything inside it, out.
- Tap the **arrow** beside a folder (or **its own songs** at the top) to list the songs, then untick single songs.
- Ticking a folder inside a left-out one brings its parent folders back.
- **Also remove their songs that are already in the library** (appears if you already added some): takes those out of the library.
- The button says how many songs it will add.

**Leave files out by name:** Settings > Library > *Excluded from library* > *Add a rule* (for example `intro`, `*.wav` or `track??.mp3`: `*` is any text, `?` one character, capitals do not matter). Files that match are left out whenever you add a folder or rescan, and it offers to take out the songs already in your library that match (their files stay). Remove the rule with its cross to let them in again.

Your choice is **remembered**: adding the same folder again leaves the same things out. To undo it: **Settings > Excluded from library**, tap the undo arrow beside what you want back, then add that folder again.

Removing a song from the library (its menu) also puts it on that list, so it does not come back next time you add its folder.

### The report
Every add ends with a report: songs **found**, **added**, **already in your library**, **left out**, **removed**, and **skipped** with the reason for each. The screen stays on while it works, so a big folder is safe to leave.

### Rescanning (when you put new songs in your music folder)
The app **remembers the folders you add**. After you put songs in the right folder, use **Library > + > Rescan music folders** (or Settings > Library > *Music folders and rescan*). One tap goes through all your folders:
- new songs are added;
- songs you **moved** to another folder are found again and keep their playlists, hearts and counts;
- a **new folder** is asked about first (untick it to leave it out; it is remembered as left out);
- songs whose file is **gone** are listed: *Keep them* or *Remove* them from the library;
- the report says how many folders were scanned. If a folder cannot be reached (an SD card that is not in), it says so and does not call its songs missing.
The first time, add your music folder once with **Add folder**; it is remembered from then on. Adding a folder (music or audiobooks) opens RemoteTunes' own folder screen: tap a folder to go in (it shows its folders and songs), then **Add this folder**. If a place cannot be reached from there, the menu has *Use Android's picker*.

### After adding
- **Settings > Update tags from files** reads genre, year, album artist, composer and Replay Gain from the files, so Genres, Years, Album Artists and Composers fill in. Run it once after adding a lot. It changes nothing in the files.
- **Settings > Find missing album art** looks up covers (needs internet; only names are sent).

---

## 4. Playing music

- **Tap a song** in a list to play it; the rest of that list becomes the queue.
- **Long-press a song** (or use *Select* in a search) to pick several, then add them to the queue or a playlist.
- A song's **menu** (three dots): add to queue, add to playlist, favorite, **Edit info**, remove from library.
- **List options:** the sliders button at the top right of a song list changes how that kind of list looks: *Show titles only*, and *View as* List, List small, List compact, List no images, 1 line or Grid. The top left of the list says how many songs it has and how long they play together. Each kind (All songs, an album, a playlist, Most played...) remembers its own. **Pinch** a song list (two fingers apart or together) to step the view bigger or smaller. In the Grid, tap plays a song, a long-press picks it, and the small menu in its corner has the same actions as a row. **Compact header** (in the sheet, for album, artist, playlist, folder and genre pages) makes the page header slimmer. The Folders list has a menu on each folder: *Play*, *Add to queue*, *Add to playlist* for everything in it.
- **Tag cleanup** (Settings > Library > Tag cleanup): shows what is missing in your music (artist, album, genre, year, cover) and fills it in, with you approving every change. *Fill in from the file names* reads names like "01 - Artist - Title". *Search online* asks MusicBrainz about songs that lack an album, a year or a genre (the review list can also fetch the cover for sure matches, and the screen has the album art finder) (about one song a second; you can stop and carry on later). Both give a **review list**: tick what you want and Apply (a good tag is never replaced). Changes can also be written into the music files (needs All files access). **Undo** is on the same screen: every batch you applied is listed with its own Undo button (newest first).
- **Audiobooks:** keep them in their own folders and add each one with **Library > + > Add audiobook folder** (as many places as you like: the phone, the SD card, anywhere). They are scanned apart from your music (**Rescan audiobook folders**) and kept out of All Songs, shuffle and the lists; they have their own **Audiobooks** category (one entry per book). An audiobook **remembers where you stopped** and carries on from there, and **Play all** on a book starts at the chapter you left. You can also mark any song with its menu (*Mark as audiobook*) or select several and use the book button; Settings > Audiobooks can find them by genre or folder name and switch the remembering off. Music is never affected. Each chapter shows how far you are (a thin bar, *40%*, *finished*) and the list of books shows how much of each you have heard. The **speed** you set while a book plays is kept for that whole book (music keeps its own). Audiobooks, where you stopped, and their speed are in backups too, and so are the places of your audiobook folders (a restore remembers again the ones that exist at the same place on the new phone).
- **Cloud Library:** your own songs in your own Cloudflare R2 bucket (free for the first 10 GB, roughly 2,500 songs). Only put up songs you own or may share.
  - *One-time set-up:* in Cloudflare, R2 > your bucket > Settings: turn on the **Public Development URL** and copy it. For uploading: R2 > **Manage API tokens** > Create API token with *Object Read & Write* for that bucket only, and copy the **Access Key ID** and **Secret Access Key** (shown once). In RemoteTunes: Settings > Lyrics and online > **Cloud Library**: paste the public address; for uploading paste the **S3 API** address from the bucket's page into *Account id* (it fills in the account and the bucket), then the two keys. *Test the address* and *Test the keys* tell you if they work. **Quicker:** save those details in a text file (the layout Cloudflare shows, e.g. `docs/cloudflare_r2.txt`), copy it to the phone, and tap **Import everything from a file** in the Cloud Library settings: it fills in every field and tries each pair of keys until Cloudflare accepts one. (The keys are deliberately not built into the app: the app's releases are public, and keys inside them would let anyone write to or delete from your bucket.) Only the phone you upload from needs the keys; the others need just the address.
  - *Putting songs up:* Library > long-press songs to pick them > the **cloud-upload button**. A list shows what will go (songs already there are unticked); fix tags first, because the cloud shows what the tags say. *Upload* shows progress and a *Stop*.
  - *Uploading from the web page (a computer):* open the web Controller, tap the **cloud button** in its top bar, then the gear: paste the public address, the account id (or the S3 address), the bucket and the two keys (kept in that browser only). Open **Using it from the web page** there and add the CORS rule it shows to the bucket in Cloudflare (R2 > your bucket > Settings > CORS Policy), once. Then the **upload button** opens your computer's file chooser: pick songs, and a list shows each with a title, artist, album and genre to edit (they start from the file name; *Artist / Album / Genre for all* fills them in together). The web page cannot read the tags inside a file or a song's length, and sends no cover; the phone upload does.
  - *Using it:* Library > **Cloud Library**. The **Songs** tab has the search box and genre chips; **Artists** and **Albums** open one artist or album (Back returns). Tap a song to play it (long-press to queue it), or *Play all*. When you control another phone, it plays there.
  - *Changing what is there* (only where the keys are): a song's menu has **Edit info** (title, artist, album, genre, year, track), **Add to playlist** and **Delete from the cloud**. *To a playlist* adds everything shown.
  - *Cloud playlists:* the **Playlists** tab: *New playlist*, open one to play it, take a song out from its menu, rename or delete the playlist from the menu at the top. They are saved in the cloud, so your other phones and the web page see them. They are not the same as the playlists in your Library.
  - *Finding and picking:* the **sort** button (Songs tab) orders by title, artist, date added or length, or shows **Recently played** (songs you started from this screen on this device). **Select** picks several songs to play or queue; with the keys also to add them to a playlist or edit their artist, album, genre or year together (only what you type changes).
  - *Covers and order* (with the keys): a song's menu > **Change cover** picks a JPG or PNG (up to 3 MB) for the whole album or just that song. In a playlist, **Reorder**, drag the handles, *Save*.
- **Ambience** (menu > Ambience): calming sounds layered together, for sleep or quiet time.
  - *Sounds:* tap to switch one on or off; each has its own volume. White, pink and brown noise are ready. For the others, tap the sound and pick your own audio file (MP3, OGG, WAV or FLAC; the app keeps a copy). *Add a sound* makes one with any name. Long-press a sound to change or remove its file.
  - *Import a folder:* put your sound files in one folder (not inside your music folders, or a rescan would add them as songs), tap *Import a folder* and pick it. Files named like a sound ("Light Rain.wav") go to it; the others become your own sounds. Check the list, change any, then *Import*.
  - *Mixes* (heart button): ready-made ones, and *Save what is on as a mix* for your own.
  - *Timer:* 15 minutes to 2 hours; the sound fades out over the last 5 minutes.
  - *Maximum volume* (ear button, on the playing phone): the ambience never plays louder than this, even from the other phone. The phone's volume buttons still apply.
  - It keeps playing with the screen locked (pause and stop are in the notification). Starting music stops it, and starting it pauses the music. While controlling another phone, menu > Ambience controls that phone; files are added on the phone that plays.
- **Insights** (menu > Insights): what your library says about itself: how many songs, hours and gigabytes; your genres and top artists; how many songs you added each month; and your most played, most skipped and recent songs. It also shows **Listening**: how long you listened this week, plays and minutes per day for the last 14 days, and where your time went (genres, artists). That comes from a **play history** the app keeps on the phone from now on (Settings > Library > *Play history* switches it off, *Clear play history* empties it). The play history is also in backups (switch *Include play history*, on by default), so it moves to another phone with you. It is worked out on the phone; nothing is sent.
- **Backup: songs you edited long ago.** Edits made with Edit info before version 1.0.7 were not flagged, so a backup would miss them. On the Backup screen, *Find songs I edited before* compares each song with the tags in its file and flags the ones that differ, so the next backup carries them.
- **Backup, when songs are not found:** the report after a restore has **Match by hand**: for each song the backup knew but this phone did not find, pick the song here that it is, and its playlists, heart and counts go to that song. **Export copied songs** (Backup screen) copies the songs you added with *Add songs* into a folder you choose, so they exist outside the app.
- **Rescan when the app opens:** Settings > Library has a switch (off by default). When on, RemoteTunes checks your remembered music folders for new songs each time it starts, without any window, and tells you only if it added something. It never removes songs, and a brand-new folder is left for *Rescan music folders* to ask you about.
- **Add to playlist is nearly everywhere:** on artist, album, genre and year rows (their menu adds all their songs), at the top of an album or artist page, in search results, in the folder tree, on every Queue row, and on the cover on Now Playing. Inside a playlist, pick several songs and use the remove button to take them out.
- The Library list shows **how many** are in each category.
- **Library categories:** All Songs, Folders, **Folder tree** (folders inside folders, arrow to go up), Albums, Artists, Album Artists, Composers, Genres, Years, Favorites, Recent, **Most played** (with how many plays), **Most skipped** (how many times you moved on before 30 seconds), **Never played**, New, Playlists. Settings > *Reset play and skip counts* starts the counts again.
- **Back from a folder, album or artist** returns to the same spot in the list, with the one you came from lightly tinted.
- **Search:** songs, albums, artists, album artists and folders in sections; *See all* narrows to one kind; your recent searches are listed when the box is empty. *Play* and *Shuffle* work on the results.

---

## 5. Now Playing

- Big cover, title in the cover's color, then a row of: **favorite**, **shuffle**, **repeat**, **speed**, **sleep timer**, **volume** (the speaker button opens a small slider). Shuffle and repeat are remembered when you close the app. **Shuffle never repeats a song until all of them have played** (then a new round starts if Repeat is on). With Crossfade on, **Next and Previous fade too**.
- Round **play/pause**, previous, next, and **10-second back / forward**.
- The line between the times shows the file's quality (for example "44.1 kHz · 320 kbps · MP3").
- **Lyrics:** the button in the cover's top-right corner fades the cover into the lyrics. The line being sung is big and bright; tap any line to jump there; **Show fullscreen** opens a big version. The same button brings the cover back. Lyrics come from the internet (LRCLIB, then Megalobiz for timed lyrics, then lyrics.ovh) and are kept on the phone. Switch it off in Settings.

### The queue
- At the bottom of Now Playing, a thin **handle**: tap it or swipe it up to see **Up next** (the song playing and what follows); swipe up again for the whole list. Tap a row to jump to it. **Tap the player above the sheet to put it away.**
- The **Queue tab** is the full list: drag the handle to reorder, **swipe a song left to remove it** (a message offers *Undo*), **swipe it right to add it to a playlist**, **long-press to pick several** and add them to a playlist or remove them together, clear, search it. Opening it **scrolls to the song playing** (Settings > *Queue opens at the song playing*, on by default; switch it off if you don't like it).

---

## 6. Sound

### Equalizer (menu > Equalizer, play a song first)
- Switch it on, pick a **preset** (Bass boost, Vocal, Rock...), or move the sliders (then it says *Custom*).
- **Phone bands / 10 bands:** your phone's own equalizer has about 5 bands. The *10 bands* view gives ten sliders (31 Hz to 16 kHz). On Android 9 or newer they are **ten real filters**, each changing only its own part of the sound, and the note under the switch says *Ten real filters*. If your phone refuses that, the ten sliders are **blended onto** the phone's 5 bands instead, and the note says so.
- **Preamp** (overall level), **Bass / Treble** (Tone), **Limit** (stops loud parts from distorting after a boost: with the ten real filters it is a true limiter; with the phone's bands it turns everything down by as much as you boosted).
- **Remember for this output:** speaker, wired headphones and Bluetooth each keep their own settings, applied when that output is in use.

### Crossfade (Settings > Crossfade, 0 to 12 seconds)
One song fades out while the next fades in. Works between songs that are files on this phone. **Off** gives normal gapless (no gap, no fade).

### Even out loudness (Settings)
Off / By song / By album. Turns loud songs **down** to the level in their Replay Gain tags (it never turns a song up). Run *Update tags from files* first; songs with no tags are unchanged.

### Visualizer (Settings, off by default)
Moving bars under the cover. **Show or hide them with the button just left of the volume button on Now Playing** (no need to open Settings), and **tap the bars to change the style** (its name shows for a moment). Six styles, all horizontal: **Bars** (rounded, with small caps that fall slowly), **Mirror** (growing up and down from the middle), **Wave** (a glowing line), **LED** (columns of lit squares), **Spread** (the bass in the middle, spreading out to both sides) and **Dots** (a row of glowing dots). You can also pick one in Settings. **Settings > Visualizer > Show it on the cover** draws it over the dimmed cover instead of under it (and you can choose where on the cover: **Top, Middle or Bottom**, bottom by default); then the lyrics and the visualizer never show together (opening the lyrics hides it). Off, it stays under the cover. Android needs the **microphone permission** to let the app see the sound's spectrum; **nothing is recorded**. It uses a little more battery and only works for this phone's own music.

---

## 7. Fixing a song's info

**Song menu > Edit info:** title, artist, album, track number. **Look up this song** (one button there) asks MusicBrainz for the details, the Cover Art Archive for the cover and the lyrics sources for the lyrics, and lets you choose what to use; only the title, artist, album and length are sent. To fix many songs at once, pick several and choose Edit info: only the fields they share (artist, album, album artist, genre, year, composer) can be changed.
- By default this only changes **how RemoteTunes lists the song**; the file is untouched.
- **Also write into the music file** is ticked from the start, so the file's tags change too (so other players see it). Android may refuse files in shared folders. Then it says *Saved in RemoteTunes only*. Fix: **Settings > All files access**, which opens Android's page for the app; switch it on, come back (the row says Allowed), save again.

---

## 8. Looks

**Menu > Skins:** seven looks (RemoteTunes, Midnight, Ember, Forest, Rose, Pure black, Mono). Tap to switch. **+** adds your own from pasted JSON; the copy button on a skin shows the format and lets you share it. Skins are dark only, and the cover's color still tints the player.

---

## 9. Two phones

### Controlling another phone
1. **On the phone that plays** (say the GT 30 Pro): tap the chip > **Start remote playback**. A QR code page opens. (It stays quiet until you do this; nothing listens on the network before.)
2. **On the other phone:** tap the chip > **Control another phone**, scan the QR code (or pick it from *Nearby*, or type the 6-digit code). The first time, the playing phone asks you to **accept**.
3. Now the library, search, queue and Now Playing on the second phone show and control the first phone's music. The chip says *Controlling ...*.
4. To go back: tap the chip > **This phone**. If the other phone goes away, you fall back to your own music.

Next times it **reconnects by itself** (trusted devices). **Remote playback** (menu) manages paired phones: rename, forget.

Settings > *When the app opens*: *This phone's music* (default) or *Control my last Player*; and *Start remote playback when the app opens*.

### Play on both phones at once (group play)
While controlling, Now Playing has **Play on this phone too**. Both phones play the same song in step. **Auto-align** (the microphone button) measures the little delay between them with clicks and sets it for you: phones about 10 cm apart, volume up, quiet room. **Fine-tune** by ear with the slider if needed.

### From a web page
https://dbsuarez.github.io/remote-tunes/ : on the playing phone use remote playback in *Auto* or *Online* mode, enter its room code on the page.

---

## Moving to another phone (backup and restore)

A backup is a file with your **playlists, favorites, play and skip counts, song info you edited, the folders you left out, lyrics, album art and settings**. The album art switch shows how many covers there are and how big the file will be; turn it off for a small file. It does **not** contain your music, so the new phone needs the same music (copy your music folder over first).

1. **Old phone:** Settings > **Backup and restore** > **Back up to a file**. Choose where to save it, then copy it to the new phone (cable, cloud, Bluetooth, anything).
2. **New phone:** add your music folder (Library > **Add folder**). Wait for the report.
3. Settings > **Backup and restore** > **Choose a backup file**. It shows what is inside.
4. **Where is your music on this phone?** Tap **Choose** and pick the folder that holds your music (the same one you added). The old place is shown for reference. The folder layout does not have to be the same: songs that are not at the same place are found by their title, artist, album and length.
5. **Restore.** A report says how many songs were found and lists the ones that were not. Album covers are only put on albums that have no picture yet.

Good to know: restoring only **adds**. Nothing on the new phone is deleted; a playlist with the same name gets the missing songs; play counts keep the bigger number. Run it again any time: nothing is added twice. Songs you added with **Add songs** are copies kept inside the app, so a backup cannot bring those songs back: add them again, then restore. The backup never contains your Jamendo ID, pairing or keys.

---

## 10. Other things

- **Online Library:** free music from Jamendo (search by keyword, genre, artist, album; licence shown). Needs internet and your Jamendo ID once. Before you search it shows **Popular this week**, **Popular this month** and **Newest releases** as rows of covers: tap one to play it, press and hold to queue it, or use *Play all* / *Add all* on a row. The genre chips open the top tracks of that genre, and under the shelves **Top this week by genre** shows the best of the week in a genre you pick. The shelves refresh by themselves while the tab is open. Pull down to refresh at once. Switch it off in Settings > *Suggestions in the Online Library*.
- **Other music apps:** Settings > *External app control* lets RemoteTunes steer Spotify or YouTube Music on the phone (needs *Notification access*, off by default).
- **Play a link:** play an audio link from the internet.
- **Sleep timer:** under the title on Now Playing.
- **Updates:** Settings > *App updates* > Check. It downloads the newest version and Android asks you to confirm the install; your songs and playlists stay. **What's new** (menu) lists what changed.
- **Diagnostics** (Settings): numbers to send me if something is wrong; *Copy* puts them on the clipboard.

---

## 11. Settings, in one list

Settings has a **search box at the top**: type a word ("crossfade", "lyrics", "vibration", "backup") and the setting shows up right there, ready to change. Without searching, the front page is a short list of **groups**, each opening its own page:

- **Playback and sound:** default volume, repeat and shuffle, crossfade, even out loudness, equalizer, visualizer, queue opens at the song playing.
- **Library:** find missing album art, update tags from files, left out of the library, reset play and skip counts, all files access.
- **Look:** skins, song list text size, haptic feedback, colors from album art.
- **Lyrics and online:** lyrics from the internet, Online Library suggestions.
- **Other phones and connection:** device name, when the app opens, connection mode, online relay, external app control, player port.
- **Updates and about:** app updates (and the installed version), diagnostics.
- **Backup and restore** has its own row.

The list below says what each one does. (Where other parts of this guide say "Settings > Crossfade" and the like, open the group above that holds it, or just search for it.)

- **Queue opens at the song playing**: The Queue tab scrolls to what is playing.
- **Visualizer**: Moving bars under the cover (microphone permission).
- **Suggestions in the Online Library**: Popular and newest Jamendo tracks before you search.
- **Skins (menu)**: Colors and card roundness.
- **Crossfade**: 0 to 12 seconds between songs.
- **Even out loudness**: Replay Gain: Off / By song / By album.
- **Equalizer (menu)**: Presets, sliders, 10-band view, Preamp, Tone, Limit.
- **Update tags from files**: Fills Genres, Years, Album Artists, Composers, Replay Gain.
- **Find missing album art**: Looks up covers online.
- **Excluded from library**: Folders and songs not added; let them back in.
- **All files access**: Lets the app write tags into files in any folder.
- **App updates**: Check, download, install.
- **Lyrics from the internet**: Switch lyrics on or off.
- **Haptics, colors from album art, song list text size**: Small comforts.
- **When the app opens**: This phone's music, or reconnect to the last Player.
- **Device name**: What the other phone sees ("GT30 Pro").

---

## 12. When something is wrong

- **A song shows as missing**: The file was moved or deleted. Re-add its folder, or remove the song.
- **Genres / Years / Composers lists are empty**: Settings > **Update tags from files**.
- **A folder keeps skipping songs**: Settings > **Excluded from library**; let the folder or song back in, add again.
- **"Saved in RemoteTunes only" when writing tags**: Settings > **All files access**, switch it on, save again.
- **The first crossfade restarted a song**: Fixed in `v0.12.1`. Update the app.
- **Visualizer bars are flat**: Allow the microphone permission; some outputs or phones refuse it (tell me which).
- **The lock screen shows no player**: Notification settings of the phone (it worked on the Note 10 Pro, not the GT 30 Pro).
- **The other phone can't find the Player**: Both on the same Wi-Fi; Start remote playback is on; or scan the QR code.
- **No lyrics**: The song may have none, you may be offline, or Lyrics from the internet is off.
- **The equalizer says play a song first**: Android sets the equalizer up when the first song loads.

If something is really wrong, send me the screen, what you tapped, which phone, and Settings > Diagnostics > Copy.
