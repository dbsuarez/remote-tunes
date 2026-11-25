# Phone test checklist

Everything below is covered by automated tests, but most of it has **never been used by hand**. Sections 1 to 13 were ticked on the phones; **sections 14 to 19 are what is left to try** (14 first). Tick each box when it behaves as written. If it doesn't, write what you saw next to it (a photo or screenshot helps) and send it over.

**Phones:** the Infinix X6873 (GT 30 Pro) and the X695. Both have the latest debug build. The X6873 has the most songs, so use it as the **Player** and the X695 as the **Controller** unless a step says otherwise. Both are currently named "My Phone": rename one in Settings > Device name (for example "GT30 Pro"), it makes the lists clearer.

Notation: **P** = on the Player phone, **C** = on the Controller phone, **W** = in a web browser.

---

## 1. Pairing and trust
- [x] **P** Start as PLAYER. The **Connect** tab shows a QR code.
- [x] **C** Start as CONTROLLER > **Scan QR code**. After scanning, **P** shows a pairing request. Tap **Accept**. **C** shows the dashboard.
- [x] **C** Press back to leave the Controller screen, then open **Start as CONTROLLER** again. It reconnects **by itself, with no code and no Accept**.
- [x] **P** Close the Player (back to home) and start it again. **C** reconnects with no code.
- [x] **C** Close the app completely (swipe away) and reopen > Controller. It reconnects with no code.
- [x] **C** Other ways to connect > **Nearby**: tap the Player in the list. It connects **with no code** (it is trusted).
- [x] **P** Rename the Player in Settings, restart it. **C** > Nearby > tap it. Still no code.
- [x] **P** Connect tab > **Forget** the Controller. **C** then needs the QR code again (and says so clearly).
- [x] Typing the 6-digit code still works as a fallback (after a Forget).

## 2. Screens
- [x] **P** Three tabs: **Player**, **Connect**, **Music**. The "who is connected" pill stays on top of all of them.
- [x] **C** Five tabs: Now Playing, Queue, Library, URL, **Online**. They scroll sideways if needed.
- [x] **C** On Queue, Library, URL and Online a small **mini bar** (title, previous, play/pause, next) sits under the tabs. Tapping its title goes to Now Playing.
- [x] Both phones stay in portrait when you rotate them.

## 3. Basic playback
- [x] **C** Library > tap a song. It plays on **P**, and **C**'s Now Playing shows title, artist and **album art**.
- [x] **C** Play / pause / next / previous work.
- [x] **C** **Progress bar:** tap a spot (say 70%). The thumb **goes straight there and stays**; it does not jump back to the old place first.
- [x] **C** **Volume slider:** same. Release at 40% and it stays at 40%.
- [x] **C** **Speed:** set 1.5x. The song audibly speeds up. Skip to the next song: it stays 1.5x. Set it back to Normal.
- [x] **C** **Sleep timer:** set 15 minutes, check the countdown shows. Cancel it. (Optional: set it and wait to see the Player pause.)
- [x] **P** The Android notification shows the song and its buttons work. Lock the screen: music keeps playing.

## 4. Library
- [x] **C** Search box filters by title, artist and album.
- [x] Chips: **Songs, Artists, Albums, Favorites, Recent, Playlists** all show something sensible.
- [x] Song rows show **album art** (a music note where a song has none). Scrolling a long list stays smooth.
- [x] **Heart** a song. It appears under **Favorites**. The heart also shows on Now Playing for the playing song.
- [x] **Recent** lists songs you just played, newest first.
- [x] **Playlists:** New playlist, add a song from its menu, open it, Play all, rename, remove a song, delete the playlist (songs stay in the library).
- [x] **Multi-select:** long-press a song, tap two more, **Add to playlist**. Then again with **Select all** > **Add to queue**.
- [x] Settings > **Song list > Text size** changes the song rows (Small is the default and the smallest).
- [x] The same library features work on **P**'s own Music tab.

## 5. Queue
- [x] Play a song, add two more with **Add to queue**. Now tap a **different single song** in the Songs list: it plays **now**, and the earlier queue is still there after it.
- [x] Tapping a song **inside an album or playlist** (or **Play all**) replaces the queue with that list.
- [x] Reorder by dragging, remove one, clear the queue.
- [x] **Restart test:** line up 4 songs, play the 2nd, then close the Player app completely and start it again. The same queue is there, **paused on the same song**. Play starts it.

## 6. Online Library (Jamendo)
The Controller build already has your Jamendo ID. If the tab asks for one, paste it.
- [x] **C** Online tab > search "piano". Results show **art, title, artist, album, length and licence**.
- [x] Try all four modes: **Keyword, Genre** (tap the "jazz" chip), **Artist** (type a name), **Album**.
- [x] Wait a few seconds between searches: results should come back every time. (Jamendo drops searches sent too fast; the app spaces them, so a search may take a moment.)
- [x] Tap **Play on Player**. After a few seconds of buffering **P** plays it, with the right title and artist.
- [x] **Seek** inside the Jamendo track works.
- [x] **Add to queue** on two other tracks. They join the end of the queue and don't interrupt.
- [x] Tap a **licence** (for example "CC BY-NC-ND 3.0"). The licence text and link appear.
- [x] **History** (clock button): the tracks you played are listed, newest first, with the time. **Play** an entry again. **Remove** one. Turn **Keep history** off, play something: it is not added. Turn it on again. **Clear** empties it after asking.
- [x] **Restart test:** queue two Jamendo tracks and one of your own, close and reopen the Player. All three are still in the queue, in order.
- [x] **No internet:** on **C**, turn on airplane mode (or Wi-Fi and data off) and search. You get "No internet connection…" with **Try again**. Your own Library still lists songs (reconnect Wi-Fi to the Player if needed).
- [x] Jamendo tracks you play do **not** appear under Favorites or Recent songs (they are history only).

## 7. Web Controller
First switch on GitHub Pages (repo Settings > Pages > Source: **GitHub Actions**) and wait for the workflow to finish. Then:
- [x] **W** Open https://dbsuarez.github.io/remote-tunes/ . It loads.
- [x] **P** is in **Auto** or **Online** mode and shows a room code. **W** Enter it, type a name, Connect. **P** shows the request. Accept. The web dashboard appears.
- [x] **W** Reload the page. It reconnects by itself ("Reconnecting to your Player…").
- [x] **W** Disconnect, reload: the **name you typed is still in the box**.
- [x] **W** The dashboard has the same tabs. Play a song from the Library; progress bar and volume don't snap back.
- [x] **W** Online tab: paste your Jamendo ID **once**, search, **Play on Player**. Artwork shows (or a music note).
- [x] **QR to web:** point the **stock camera app** (not RemoteTunes) at **P**'s QR code. It opens the web page, which connects by itself. Tap **Accept** on **P**.
- [x] **QR in the app** still works after that (scan it with **C**).
- [x] While **W** is connected, connect **C** by tapping its saved Player: it takes over, and **C** can reconnect later with one tap and no code.

## 8. Other apps (Phase 5, never run on a phone)
- [x] **P** Settings > External app control > turn on, read the explanation, grant Notification access.
- [x] Start Spotify or YouTube Music on **P**. **C** Now Playing > **Other music app**. Play/pause/next/seek work as far as that app allows. Switch back to RemoteTunes.

## 9. Odds and ends
- [x] Settings > **Diagnostics** opens, shows sensible numbers and **Copy** works.
- [x] Switch **C** to mobile data only, keep **P** on Wi-Fi, mode **Auto**: it should still connect via the online room (needs online mode on **P**).
- [x] Turn **C**'s screen off for a minute and back on: it reconnects.

## 10. Group play (the Controller plays along with the Player)
Put the two phones side by side, same Wi-Fi, music with a clear beat. **C** is connected to **P** locally (not via the internet).
- [x] **C** Now Playing > **Play on this phone too** > switch on. The status goes "Joining…", then "Getting the song from the Player…", then **"Playing in sync"**.
- [x] You hear the song from **both** phones, and it sounds like **one** song (no echo or flam). It may take a few seconds to settle after starting.
- [x] The card shows **Off by** a small number (ideally under 30 ms, shown in teal) and a connection delay of a few ms.
- [x] **Fine-tune:** if one phone is consistently ahead, move the slider (+ if **C** sounds late, - if early) until they line up by ear. Close the app and reopen it: the setting is remembered.
- [x] **P** pause and play: **C** pauses and resumes with it.
- [x] Drag the progress bar on **C** (a seek): both phones jump and stay together within a couple of seconds.
- [x] Next song: **C** keeps up (it fetched the next song ahead of time, so there should be no gap).
- [x] Play on **P** at 1.5x speed: both follow.
- [x] Walk the phones to different rooms, or put **C** in your pocket with the screen on: it stays in step. (Screen off or app in the background may stop it: tell me what happens.)
- [x] Switch the Wi-Fi off on **C**: the card shows reconnecting and **C** goes quiet. Switch it back on: it rejoins by itself.
- [x] Play a **Jamendo** track: **C** says it can't follow ("Waiting for the Player to play a song from its library"), the Player plays alone. Back to a library song: it rejoins the sound.
- [x] Switch it off: **C** goes silent. (It also deletes the temporary song files.)
- [x] **C** connected through the internet only (mobile data, Auto mode): the switch is disabled and says it needs the same Wi-Fi.
- [x] Note the **round-trip** and **clock spread** numbers and whether the sound ever drifts apart over a whole song. This is the most useful thing to report.

## 11. Group play hardening and Auto-align (new)
Same setup as section 10 (**P** = Player, **C** = the phone that plays along, side by side, same Wi-Fi).
- [x] **C** switches on **Play on this phone too**. The **screen stays on** by itself while it is on (it does not dim and lock). Switch it off: the screen behaves normally again.
- [x] While it is on, the card shows **"This phone's own audio delay"** with a number (some phones don't report it; then the line is missing).
- [x] Turn **P**'s music to a Bluetooth speaker or earbuds, or connect **C**'s to one: the card shows an **orange warning about Bluetooth**. Back to the phone speaker: the warning goes away.
- [x] Move **C** far from the Wi-Fi router: a warning about an **uneven Wi-Fi** may appear. Move back: it goes.
- [x] Let it play a whole song **without touching anything**. The **Off by** number should stay small and steady. Note its typical size, and how often you hear it correct itself (a hard jump is a click or skip; a speed nudge should not be audible).
- [x] Seek on **C**, pause/play, next: after each, **C** is back in step within a couple of seconds and **does not keep jumping around**.
- [x] **Auto-align** (the microphone button): put the phones about 10 cm apart, volumes up, quiet room. Tap it, read the box, **Start**. The Player plays a short series of clicks, first alone (about 5 s), then **this phone alone** (about 5 s). Keep quiet.
- [x] A permission box asks for the **microphone**: allow it.
- [x] A message tells you what it found, for example **"This phone was 37.0 ms late. Fine-tune set to +37 ms."** **Write down the number it reports and the phones' names.**
- [x] **Run Auto-align a second time.** It should now say it is **already lined up** (within a few ms). If it reports a big number again, tell me both numbers.
- [x] After Auto-align the **Player is back to what it was**: the same song, queue and volume (it was silenced for a few seconds in the middle).
- [x] While Auto-align runs, tap **Cancel**: it stops, and the Player's volume and queue are back to normal.
- [x] In a noisy room, or with the volume very low, Auto-align says it **could not hear the clicks** and changes nothing.
- [x] After Auto-align the song really **sounds together** now. If it doesn't, nudge it by ear and tell me how far off it still was, and which way (this tells me how accurate the measurement is on your phones).
- [x] Deny the microphone permission: Auto-align says so and changes nothing.

## 12. Smaller new things
Both phones now run the **release build** (faster than debug; same app).
- [x] The app opens quickly and your data is all still there (songs, playlists, trusted devices).
- [x] **Queue search:** Queue tab > the search button. Type part of a title, an artist or an album: the list narrows and says "N of M". Tap an entry to play it, tap the cross to remove it. Close the search: the whole queue is back and dragging works again.
- [x] **Carry on where it was:** play a song to about the middle, pause, close the app completely and open it as Player. The bar shows where it was. Press Play: it continues from there, not from the start. A different song chosen instead starts from its beginning.
- [x] Play a song, close the app **without pausing**, reopen: it is within about 10 seconds of where you left it.
- [x] **Settings > Diagnostics:** there are now sections for the saved queue, Online Library, and **Group play** (sound output, the phone's own audio delay, microphone permission). While playing along, it also shows the live "Off by", round trip and fine-tune numbers. **Copy** works, and the text contains no Jamendo ID.
- [x] Auto-align (section 11) works on the release build too. If it is **muted at the wrong time** (the Player goes quiet before the first clicks finish, or this phone never gets loud), tell me what you heard.

## 13. Feel and color (docs/handoff.md)
- [x] **Haptics:** on the Controller, Play/Pause gives a firmer tap; Previous/Next a light one; letting go of the volume or seek slider, hearts, long-press to select and picking a song give a small click. **Settings > Look and feel > Haptic feedback** off: all silent.
- [x] **Album-art colors:** play songs with different covers. The Controller's accent (progress bar, play button, highlights) fades to the cover's color in about half a second. Covers that are grey or missing keep the normal teal. The accent is never Spotify-green and stays readable on the dark background. **Colors from album art** off: always teal.
- [x] **Queue Peek:** on Now Playing a small sheet rests at the bottom showing the song playing. Drag it up: the next 3 songs appear, further up the whole queue. Tap a song: it plays. Drag down: it tucks away. The player controls above are never covered, and you can still scroll the page to its last card.
- [x] Nothing queued, or playing an internet track: no sheet is shown.

## 14. Start here: the new things most likely to behave differently on a phone
These were built after `v0.7.0` and have **never been tried on a phone**. Do them in this order (the riskiest first). Tick the box, or write what you saw next to it.

- [ ] **Crossfade:** Settings > Crossfade, set 5 s. Play an album from the phone: near the end of each song it fades out while the next fades in. **The first change after opening the app fades once and the next song does not start over** (this was a bug in `v0.12.0`, fixed in `v0.12.1`). Skipping and pausing during a fade behave. Off gives normal gapless.
- [ ] **Write tags into files:** Edit info on a song > *Also write into the music file*. Tick it and save: the message says whether the file was changed. If Android refuses it says *Saved in RemoteTunes only*; then Settings > *All files access* opens Android's page for the app: switch it on, come back (the row shows Allowed) and save again. Report which phone and which folder if it still refuses.
- [ ] **Visualizer:** Settings > Visualizer on; allow the microphone permission. Under the cover bars move with the music, stop when paused, keep moving after a song change and during a crossfade. If you refuse the permission, it says so. Report if the bars stay flat on any phone or output (speaker / Bluetooth).
- [ ] **Leave folders out:** add a folder that has subfolders: *Choose what to add* appears. Untick one, add: the report shows Added and Left out counts. Add the same folder again: the unticked one stays out. Settings > *Left out of the library* lists it; the undo arrow lets it back in. With a folder already added, untick one and tick *Also remove their songs*: the report shows Removed. Remove one song from the library, add its folder again: it does not return.
- [ ] **Leave single songs out:** in *Choose what to add*, the arrow beside a folder (and *its own songs* at the top) lists its songs; untick one and add: the report counts it as left out, and adding the folder again leaves it out.
- [ ] **Online Library home:** Online Library tab (your Jamendo ID entered): with nothing searched, three shelves of covers appear (Popular this week / this month, Newest releases) one after another (a few seconds), and genre chips. Tap a cover: it plays on the Player; press and hold: it queues; *Play all* plays the first and queues the rest. Pull down to refresh. In airplane mode: the usual no-internet message and *Try again*. Settings > *Suggestions in the Online Library* off: the tab is blank until you search.
- [ ] **Report:** adding files or a folder ends with a report (found, added, already in the library, left out, removed, skipped with reasons). The progress card keeps the same size while file names change, and the screen does not lock while it runs.
- [ ] **Lock screen:** start a song, lock the phone: the player (title, cover, buttons, a heart for library songs) shows on the lock screen. If it does not, tell me what you see (nothing at all, or a notification without buttons). The GT 30 Pro did not show it earlier (probably a phone setting).

## 15. Sound
- [ ] **Gapless:** queue two songs that flow into each other (an album or a live recording), crossfade off. Let the first end: the second starts with no gap or click. Skip, repeat-one, shuffle and removing the next song still work.
- [ ] **Equalizer:** the equalizer icon in the top bar (or Menu > Equalizer). Play a song first. Bass boost: the bass is clearly stronger; switch it off: normal again. *Remember for ...*, change the output (headphones / Bluetooth) and back: the settings follow the output.
- [ ] **EQ extras:** the curve moves with the sliders; Preamp changes the overall loudness; Bass / Treble (Tone) and Limit work (Limit turns the music down when you boost).
- [ ] **10-band EQ:** on the EQ screen switch to *10 bands*. Ten sliders (31 to 16k) with a note about the phone's real bands. Bass sliders change the sound as you expect; a preset fills all ten; switching back works; it is still there after closing the app.
- [ ] **True 10-band EQ (new, riskiest of the sound items):** EQ screen > *10 bands*, switch the Equalizer on, then pick a preset or move a slider. The note under the switch should say **"Ten real filters"**. If it says *blended onto them*, this phone refused real filters: tell me the phone and Android version. With real filters: raise only the 31 Hz slider, you should hear **only the deepest bass** change (the old blended view moved a wider part); raise only 16k and only the highest treble changes. Turn *Limit* on, boost two sliders by +10: loud music should not crackle. Play two songs with crossfade on: the EQ still applies to both, with no jump at the change. Switch back to the phone's bands: it still works. Turn the visualizer on at the same time: bars still move.
- [ ] **Even out loudness:** Settings > Update tags from files, then Even out loudness > By song. Songs from albums with Replay Gain tags are turned down to about the same level (untagged songs are unchanged).

## 16. Now Playing and the menu
- [ ] **Music player first:** the app opens on Now Playing for this phone's songs (bottom bar Now Playing / Library / Search / Queue, chip *This phone* on top). Switch tabs: the mini player shows under every tab but Now Playing. With nothing playing there is **no** RemoteTunes notification.
- [ ] **Now Playing:** the cover is big (never more than about 40% of the screen), the title is in the accent color; favorite / shuffle / repeat / speed / sleep timer / volume (a speaker button with a small vertical slider) sit under it; the 10-second buttons jump; the format line ("44.1 kHz · 320 kbps · MP3") shows for local songs. On your smallest phone nothing is cut off.
- [ ] **Queue sheet:** only a thin handle rests at the bottom; tap it or swipe it up (middle, then full); a swipe in from the right edge does the same. **Tapping the player above the raised sheet puts it away.** Tapping a row jumps to it.
- [ ] **Queue tab:** opening it scrolls to the song playing. Settings > *Queue opens at the song playing* off keeps the list where it was.
- [ ] **Lyrics:** the button in the cover's top-right corner fades the cover out, then the lyrics card fades in at the cover's size; the line being sung is big and bright, the rest dimmer, fading at the top and bottom; tap a line to jump; *Show fullscreen* opens the big view; the button brings the cover back. A song with no lyrics says so; offline says it can't reach the service; Settings > Lyrics from the internet off says they are switched off. Timed lyrics also come from Megalobiz when LRCLIB has none (credited on the card).
- [ ] **Menu** (top-left button): Now Playing, Lyrics (shows them on Now Playing), Library, Playlists, Search, Queue, Equalizer, Skins, Remote playback, Settings, What's new, Help. A swipe in from the left edge still opens the Library, not the menu.
- [ ] **Skins:** Menu > Skins lists 7 looks; tapping one changes the colors at once and it is remembered. Add (+) accepts pasted JSON (copy one to see the format), explains mistakes; an added skin can be removed.

## 17. Library and search
- [ ] **Library list:** the Library tab opens on a list of categories (All Songs, Folders, Folder tree, Albums, Artists, Album Artists, Composers, Genres, Years, Favorites, Recent, Top, New, Playlists); each opens with a back arrow to the list.
- [ ] **Genres / Years / Album Artists / Composers:** Settings > Update tags from files, then those lists fill in.
- [ ] **Folder tree:** starts at the top of your music folders; tap folders to go in, the up arrow to come back (the folder you left is tinted); songs in a folder play from the one you tap.
- [ ] **Folders:** long-press a folder, tap more, add them to a playlist or the queue; open a folder far down the list, press Back: same spot, that folder tinted.
- [ ] **Search:** the search button opens it. Songs, albums, artists, album artists and folders in sections; *See all* narrows; recent searches show when the box is empty and survive closing the app. **Select** (or a long-press) picks several songs for the queue or a playlist; Play / Shuffle work on the results.
- [ ] **Edit info:** a song's menu > Edit info; change the title, Save: the list shows it.
- [ ] **Album art finder:** Settings > Find missing album art says how many albums lack a cover, finds some; they show on the next song played from those albums.
- [ ] **Shuffle and repeat:** switch both on, close the app completely, open it: both are still on.

## 18. The other phone (remote playback)
- [ ] **Start remote playback:** the chip > Start remote playback; the pairing / QR page opens; the notification stays while nothing plays. On the other phone: chip > Control another phone > pick it. That phone's music shows in the same tabs and the buttons control it. Stop remote playback on the first phone: the other phone shows it disconnected and falls back to its own music.
- [ ] **Pairing request** pops up over whatever screen is open on the Player.
- [ ] **Now Playing is the same** on both phones: cover, accent title, quick row, 10-second jumps, lyrics, queue sheet, edge swipes.
- [ ] **When the app opens** (Settings): *Control my last Player* reconnects by itself (chip says Controlling ...); *Start remote playback when the app opens* starts it at once.

## 19. Updates
- [x] **Updates:** Settings > App updates > Check for updates says "newest version" or offers the new one. Android asks to allow installs from RemoteTunes once, downloads, shows its install screen; afterwards your songs, playlists and trusted devices are still there.
- [ ] **What's new** (Menu) lists the release notes from GitHub.
- [ ] **Help > The full guide:** the quick start is on top, then the guide's sections (tap to open). Type "crossfade" in the search box: only the matching sections show, already open. Clear it and the quick start returns. It works with no internet.

---

## How to report
For each failure send: the **step number**, **which phone**, what you expected, what happened, and a screenshot if you can. For anything that looks like a crash, tell me roughly when it happened so I can read the phone's log.
