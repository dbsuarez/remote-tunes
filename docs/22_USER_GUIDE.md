# RemoteTunes: your own guide

For the owner, when you forget how something works. Plain words, no code. Where a part has **never been tried on a phone yet**, it says so (the full list is in [19_PHONE_TEST_CHECKLIST.md](19_PHONE_TEST_CHECKLIST.md)). What each feature does, and what it cannot do, is in [20_NEXT_TASKS.md](20_NEXT_TASKS.md). What leaves the phone is in [21_PRIVACY.md](21_PRIVACY.md).

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

| Choice | What it does | Good for |
|---|---|---|
| **Add songs** | Picks files and **copies** them into the app. | A few songs. They stay even if you delete the originals. |
| **Add a folder** | Reads a whole folder **where it is** (nothing is copied). Needs the music permission. | Your music folder. If you delete or move the files, the songs show as missing. |

### Leaving things out (adding a folder)
After you pick a folder, **Choose what to add** lists its folders, all ticked, with how many songs each holds.

- **Untick a folder** to leave it, and everything inside it, out.
- Tap the **arrow** beside a folder (or **its own songs** at the top) to list the songs, then untick single songs.
- Ticking a folder inside a left-out one brings its parent folders back.
- **Also remove their songs that are already in the library** (appears if you already added some): takes those out of the library.
- The button says how many songs it will add.

Your choice is **remembered**: adding the same folder again leaves the same things out. To undo it: **Settings > Left out of the library**, tap the undo arrow beside what you want back, then add that folder again.

Removing a song from the library (its menu) also puts it on that list, so it does not come back next time you add its folder.

### The report
Every add ends with a report: songs **found**, **added**, **already in your library**, **left out**, **removed**, and **skipped** with the reason for each. The screen stays on while it works, so a big folder is safe to leave.

### After adding
- **Settings > Update tags from files** reads genre, year, album artist, composer and Replay Gain from the files, so Genres, Years, Album Artists and Composers fill in. Run it once after adding a lot. It changes nothing in the files.
- **Settings > Find missing album art** looks up covers (needs internet; only names are sent).

---

## 4. Playing music

- **Tap a song** in a list to play it; the rest of that list becomes the queue.
- **Long-press a song** (or use *Select* in a search) to pick several, then add them to the queue or a playlist.
- A song's **menu** (three dots): add to queue, add to playlist, favorite, **Edit info**, remove from library.
- **Library categories:** All Songs, Folders, **Folder tree** (folders inside folders, arrow to go up), Albums, Artists, Album Artists, Composers, Genres, Years, Favorites, Recent, Top (most played), New, Playlists.
- **Back from a folder, album or artist** returns to the same spot in the list, with the one you came from lightly tinted.
- **Search:** songs, albums, artists, album artists and folders in sections; *See all* narrows to one kind; your recent searches are listed when the box is empty. *Play* and *Shuffle* work on the results.

---

## 5. Now Playing

- Big cover, title in the cover's color, then a row of: **favorite**, **shuffle**, **repeat**, **speed**, **sleep timer**, **volume** (the speaker button opens a small slider). Shuffle and repeat are remembered when you close the app.
- Round **play/pause**, previous, next, and **10-second back / forward**.
- The line between the times shows the file's quality (for example "44.1 kHz · 320 kbps · MP3").
- **Lyrics:** the button in the cover's top-right corner fades the cover into the lyrics. The line being sung is big and bright; tap any line to jump there; **Show fullscreen** opens a big version. The same button brings the cover back. Lyrics come from the internet (LRCLIB, then Megalobiz for timed lyrics, then lyrics.ovh) and are kept on the phone. Switch it off in Settings.

### The queue
- At the bottom of Now Playing, a thin **handle**: tap it or swipe it up to see **Up next** (the song playing and what follows); swipe up again for the whole list. Tap a row to jump to it. **Tap the player above the sheet to put it away.**
- The **Queue tab** is the full list: drag to reorder, remove, clear, search it. Opening it **scrolls to the song playing** (Settings > *Queue opens at the song playing*, on by default; switch it off if you don't like it).

---

## 6. Sound

### Equalizer (menu > Equalizer, play a song first)
- Switch it on, pick a **preset** (Bass boost, Vocal, Rock...), or move the sliders (then it says *Custom*).
- **Phone bands / 10 bands:** your phone's equalizer really has about 5 bands. The *10 bands* view gives ten sliders (31 Hz to 16 kHz) that are **blended onto** those 5, so it is not a true 10-band filter.
- **Preamp** (overall level), **Bass / Treble** (Tone), **Limit** (turns everything down by as much as you boosted, so loud parts don't distort).
- **Remember for this output:** speaker, wired headphones and Bluetooth each keep their own settings, applied when that output is in use.

### Crossfade (Settings > Crossfade, 0 to 12 seconds)
One song fades out while the next fades in. Works between songs that are files on this phone. **Off** gives normal gapless (no gap, no fade).

### Even out loudness (Settings)
Off / By song / By album. Turns loud songs **down** to the level in their Replay Gain tags (it never turns a song up). Run *Update tags from files* first; songs with no tags are unchanged.

### Visualizer (Settings, off by default)
Moving bars under the cover. Android needs the **microphone permission** to let the app see the sound's spectrum; **nothing is recorded**. It uses a little more battery and only works for this phone's own music.

---

## 7. Fixing a song's info

**Song menu > Edit info:** title, artist, album, track number.
- By default this only changes **how RemoteTunes lists the song**; the file is untouched.
- Tick **Also write into the music file** to change the file's tags too (so other players see it). Android may refuse files in shared folders. Then it says *Saved in RemoteTunes only*. Fix: **Settings > All files access**, which opens Android's page for the app; switch it on, come back (the row says Allowed), save again.

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

## 10. Other things

- **Online Library:** free music from Jamendo (search by keyword, genre, artist, album; licence shown). Needs internet and your Jamendo ID once.
- **Other music apps:** Settings > *External app control* lets RemoteTunes steer Spotify or YouTube Music on the phone (needs *Notification access*, off by default).
- **Play a link:** play an audio link from the internet.
- **Sleep timer:** under the title on Now Playing.
- **Updates:** Settings > *App updates* > Check. It downloads the newest version and Android asks you to confirm the install; your songs and playlists stay. **What's new** (menu) lists what changed.
- **Diagnostics** (Settings): numbers to send me if something is wrong; *Copy* puts them on the clipboard.

---

## 11. Settings, in one list

| Setting | What it does |
|---|---|
| Queue opens at the song playing | The Queue tab scrolls to what is playing. |
| Visualizer | Moving bars under the cover (microphone permission). |
| Skins (menu) | Colors and card roundness. |
| Crossfade | 0 to 12 seconds between songs. |
| Even out loudness | Replay Gain: Off / By song / By album. |
| Equalizer (menu) | Presets, sliders, 10-band view, Preamp, Tone, Limit. |
| Update tags from files | Fills Genres, Years, Album Artists, Composers, Replay Gain. |
| Find missing album art | Looks up covers online. |
| Left out of the library | Folders and songs not added; let them back in. |
| All files access | Lets the app write tags into files in any folder. |
| App updates | Check, download, install. |
| Lyrics from the internet | Switch lyrics on or off. |
| Haptics, colors from album art, song list text size | Small comforts. |
| When the app opens | This phone's music, or reconnect to the last Player. |
| Device name | What the other phone sees ("GT30 Pro"). |

---

## 12. When something is wrong

| What you see | Try |
|---|---|
| A song shows as missing | The file was moved or deleted. Re-add its folder, or remove the song. |
| Genres / Years / Composers lists are empty | Settings > **Update tags from files**. |
| A folder keeps skipping songs | Settings > **Left out of the library**; let the folder or song back in, add again. |
| "Saved in RemoteTunes only" when writing tags | Settings > **All files access**, switch it on, save again. |
| The first crossfade restarted a song | Fixed in `v0.12.1`. Update the app. |
| Visualizer bars are flat | Allow the microphone permission; some outputs or phones refuse it (tell me which). |
| The lock screen shows no player | Notification settings of the phone (it worked on the Note 10 Pro, not the GT 30 Pro). |
| The other phone can't find the Player | Both on the same Wi-Fi; Start remote playback is on; or scan the QR code. |
| No lyrics | The song may have none, you may be offline, or Lyrics from the internet is off. |
| The equalizer says play a song first | Android sets the equalizer up when the first song loads. |

If something is really wrong, send me the screen, what you tapped, which phone, and Settings > Diagnostics > Copy.
