# Phone test checklist

Everything below is covered by automated tests, but most of it has **never been used by hand**. Tick each box when it behaves as written. If it doesn't, write what you saw next to it (a photo or screenshot helps) and send it over.

**Phones:** the Infinix X6873 (GT 30 Pro) and the X695. Both have the latest debug build. The X6873 has the most songs, so use it as the **Player** and the X695 as the **Controller** unless a step says otherwise. Both are currently named "My Phone": rename one in Settings > Device name (for example "GT30 Pro"), it makes the lists clearer.

Notation: **P** = on the Player phone, **C** = on the Controller phone, **W** = in a web browser.

---

## 1. Pairing and trust
- [ ] **P** Start as PLAYER. The **Connect** tab shows a QR code.
- [ ] **C** Start as CONTROLLER > **Scan QR code**. After scanning, **P** shows a pairing request. Tap **Accept**. **C** shows the dashboard.
- [ ] **C** Press back to leave the Controller screen, then open **Start as CONTROLLER** again. It reconnects **by itself, with no code and no Accept**.
- [ ] **P** Close the Player (back to home) and start it again. **C** reconnects with no code.
- [ ] **C** Close the app completely (swipe away) and reopen > Controller. It reconnects with no code.
- [ ] **C** Other ways to connect > **Nearby**: tap the Player in the list. It connects **with no code** (it is trusted).
- [ ] **P** Rename the Player in Settings, restart it. **C** > Nearby > tap it. Still no code.
- [ ] **P** Connect tab > **Forget** the Controller. **C** then needs the QR code again (and says so clearly).
- [ ] Typing the 6-digit code still works as a fallback (after a Forget).

## 2. Screens
- [ ] **P** Three tabs: **Player**, **Connect**, **Music**. The "who is connected" pill stays on top of all of them.
- [ ] **C** Five tabs: Now Playing, Queue, Library, URL, **Online**. They scroll sideways if needed.
- [ ] **C** On Queue, Library, URL and Online a small **mini bar** (title, previous, play/pause, next) sits under the tabs. Tapping its title goes to Now Playing.
- [ ] Both phones stay in portrait when you rotate them.

## 3. Basic playback
- [ ] **C** Library > tap a song. It plays on **P**, and **C**'s Now Playing shows title, artist and **album art**.
- [ ] **C** Play / pause / next / previous work.
- [ ] **C** **Progress bar:** tap a spot (say 70%). The thumb **goes straight there and stays**; it does not jump back to the old place first.
- [ ] **C** **Volume slider:** same. Release at 40% and it stays at 40%.
- [ ] **C** **Speed:** set 1.5x. The song audibly speeds up. Skip to the next song: it stays 1.5x. Set it back to Normal.
- [ ] **C** **Sleep timer:** set 15 minutes, check the countdown shows. Cancel it. (Optional: set it and wait to see the Player pause.)
- [ ] **P** The Android notification shows the song and its buttons work. Lock the screen: music keeps playing.

## 4. Library
- [ ] **C** Search box filters by title, artist and album.
- [ ] Chips: **Songs, Artists, Albums, Favorites, Recent, Playlists** all show something sensible.
- [ ] Song rows show **album art** (a music note where a song has none). Scrolling a long list stays smooth.
- [ ] **Heart** a song. It appears under **Favorites**. The heart also shows on Now Playing for the playing song.
- [ ] **Recent** lists songs you just played, newest first.
- [ ] **Playlists:** New playlist, add a song from its menu, open it, Play all, rename, remove a song, delete the playlist (songs stay in the library).
- [ ] **Multi-select:** long-press a song, tap two more, **Add to playlist**. Then again with **Select all** > **Add to queue**.
- [ ] Settings > **Song list > Text size** changes the song rows (Small is the default and the smallest).
- [ ] The same library features work on **P**'s own Music tab.

## 5. Queue
- [ ] Play a song, add two more with **Add to queue**. Now tap a **different single song** in the Songs list: it plays **now**, and the earlier queue is still there after it.
- [ ] Tapping a song **inside an album or playlist** (or **Play all**) replaces the queue with that list.
- [ ] Reorder by dragging, remove one, clear the queue.
- [ ] **Restart test:** line up 4 songs, play the 2nd, then close the Player app completely and start it again. The same queue is there, **paused on the same song**. Play starts it.

## 6. Online Library (Jamendo)
The Controller build already has your Jamendo ID. If the tab asks for one, paste it.
- [ ] **C** Online tab > search "piano". Results show **art, title, artist, album, length and licence**.
- [ ] Try all four modes: **Keyword, Genre** (tap the "jazz" chip), **Artist** (type a name), **Album**.
- [ ] Wait a few seconds between searches: results should come back every time. (Jamendo drops searches sent too fast; the app spaces them, so a search may take a moment.)
- [ ] Tap **Play on Player**. After a few seconds of buffering **P** plays it, with the right title and artist.
- [ ] **Seek** inside the Jamendo track works.
- [ ] **Add to queue** on two other tracks. They join the end of the queue and don't interrupt.
- [ ] Tap a **licence** (for example "CC BY-NC-ND 3.0"). The licence text and link appear.
- [ ] **History** (clock button): the tracks you played are listed, newest first, with the time. **Play** an entry again. **Remove** one. Turn **Keep history** off, play something: it is not added. Turn it on again. **Clear** empties it after asking.
- [ ] **Restart test:** queue two Jamendo tracks and one of your own, close and reopen the Player. All three are still in the queue, in order.
- [ ] **No internet:** on **C**, turn on airplane mode (or Wi-Fi and data off) and search. You get "No internet connection…" with **Try again**. Your own Library still lists songs (reconnect Wi-Fi to the Player if needed).
- [ ] Jamendo tracks you play do **not** appear under Favorites or Recent songs (they are history only).

## 7. Web Controller
First switch on GitHub Pages (repo Settings > Pages > Source: **GitHub Actions**) and wait for the workflow to finish. Then:
- [ ] **W** Open https://dbsuarez.github.io/remote-tunes/ . It loads.
- [ ] **P** is in **Auto** or **Online** mode and shows a room code. **W** Enter it, type a name, Connect. **P** shows the request. Accept. The web dashboard appears.
- [ ] **W** Reload the page. It reconnects by itself ("Reconnecting to your Player…").
- [ ] **W** Disconnect, reload: the **name you typed is still in the box**.
- [ ] **W** The dashboard has the same tabs. Play a song from the Library; progress bar and volume don't snap back.
- [ ] **W** Online tab: paste your Jamendo ID **once**, search, **Play on Player**. Artwork shows (or a music note).
- [ ] **QR to web:** point the **stock camera app** (not RemoteTunes) at **P**'s QR code. It opens the web page, which connects by itself. Tap **Accept** on **P**.
- [ ] **QR in the app** still works after that (scan it with **C**).
- [ ] While **W** is connected, connect **C** by tapping its saved Player: it takes over, and **C** can reconnect later with one tap and no code.

## 8. Other apps (Phase 5, never run on a phone)
- [ ] **P** Settings > External app control > turn on, read the explanation, grant Notification access.
- [ ] Start Spotify or YouTube Music on **P**. **C** Now Playing > **Other music app**. Play/pause/next/seek work as far as that app allows. Switch back to RemoteTunes.

## 9. Odds and ends
- [ ] Settings > **Diagnostics** opens, shows sensible numbers and **Copy** works.
- [ ] Switch **C** to mobile data only, keep **P** on Wi-Fi, mode **Auto**: it should still connect via the online room (needs online mode on **P**).
- [ ] Turn **C**'s screen off for a minute and back on: it reconnects.

---

## How to report
For each failure send: the **step number**, **which phone**, what you expected, what happened, and a screenshot if you can. For anything that looks like a crash, tell me roughly when it happened so I can read the phone's log.
