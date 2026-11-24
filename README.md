# RemoteTunes

## Purpose

RemoteTunes is an Android app (Flutter) in which **one phone controls music playback on another phone**.

- **Player** — hosts the connection, plays the audio, owns the library and queue.
- **Controller** — discovers/pairs with a Player, sends commands, shows playback state.

Target: Android 10+ (minSdk 29). Developed and tested on two Infinix phones, each in both roles.

## Core rule: offline-first, online-optional

- **Local mode must work with no internet** (same Wi‑Fi or hotspot): discovery, pairing, playback, remote commands.
- **Online mode is optional** (Supabase Realtime relay, Phase 4). It must never block or be required for local mode.
- **Do not remove online features.** Do not make online mandatory. Do not make local mode depend on Supabase.
- Do not store music files in Supabase. No forced login in v1. No analytics or telemetry.
- Both transports share one JSON protocol behind a `RemoteTransport` abstraction.
- Connection modes: **Auto** (prefer local, fall back to online), **Local only**, **Online only**.

## Phase roadmap

Build **one phase at a time**. Do not implement later phases early. The specs live in [`docs/`](docs/).

| Phase | Scope | Status |
|---|---|---|
| 0 | Foundation: Flutter project, dark Material 3, Riverpod, GoRouter, Drift, settings, Home, Android manifest | **Done** |
| 1 | Local remote control: WebSocket server, mDNS/NSD discovery, manual IP, pairing, commands, state sync | **Built; automated tests pass; needs two-phone device test** |
| 2 | Local MP3 player and queue, background playback, media notification | **Built; automated tests pass; needs device test (sound, notification, background)** |
| 3 | Online URL playback | **Built; automated tests pass; needs device test (real streams)** |
| 4 | Online remote control via Supabase Realtime | **Built; automated tests pass (fake relay); NOT yet tried against a real Supabase project** |
| 5 | Spotify / YouTube Music external control | **Built; Dart logic tested with a fake; the Android side compiles but has NEVER run on a phone** |
| 6 | Web Controller: browser Controller over Supabase Realtime ([docs/17](docs/17_WEB_CONTROLLER.md)) | **Built; verified in a real browser against a simulated Player on the real Supabase relay; NOT yet tried against a real phone Player** |
| 7 | Polish: album art, playlists, favorites, search, sleep timer, speed, diagnostics ([docs/14](docs/14_PHASE_7_POLISH.md)) | **Built:** search, sleep timer, shorter screens, favorites, recently played, playlists, playback speed, album art on the Controller, diagnostics, app icon. Not yet tried on phones: everything after the sleep timer |
| 8 | Online Library: search Jamendo's free Creative Commons music from the Controller (and web Controller) and play or queue it on the Player ([docs/18](docs/18_PHASE_8_ONLINE_LIBRARY.md)) | **Built; automated tests pass (fake Jamendo); NOT yet tried with a real Jamendo client ID or on phones** |
| 9 | Group Mode: same song in sync on several phones in one room ([draft spec](docs/16_GROUP_MODE.md), not approved) | Draft only |

Phase 0 deliberately does **not** initialize Supabase, audio, networking, or discovery.

Phase 1 is local Android-to-Android control only. Pairing tokens are kept in memory only (no token column in the schema), so restarting either app means pairing again. The Player server runs only while the Player screen is open.

Phase 2 replaces the Phase 1 silent simulated engine (kept for tests) with real audio:
- **Import:** "Add songs" uses the system picker and *copies* files into app-private storage (the picker only gives temporary cache copies). "Add folder" scans a folder and references files *in place* (needs the music permission). Missing files show as unavailable (checked at read time, no schema change).
- **Queue:** own queue controller (`features/player/queue`) plays one track at a time (not gapless), with shuffle and repeat. Queue is in memory only (FR-55).
- **Controller:** tabs Now Playing / Queue / Library. File paths never leave the Player; the Controller only gets ids and metadata. Album art is extracted on the Player; the Controller gets a small thumbnail (Phase 7).
- **Background:** an `audio_service` media session keeps a foreground service (and the network server) alive while Player mode is open. This is unverified on real phones; Wi-Fi sleep may still need native work.

Phase order follows `docs/17` §12: Web Controller is Phase 6, Polish is Phase 7, Online Library is Phase 8 and Group Mode is Phase 9. Do not implement Phase 9 early. Shared Controller code (`core/protocol`, `core/transport/remote_transport.dart`, `features/controller/controller_client.dart`) is deliberately kept free of `dart:io` so a web Controller could reuse it.

## Phase 6: Web Controller

A browser page that controls a Player phone over the online relay. Controller only: no audio plays in the browser, no music is stored, no login.

- **Entry point:** `lib/main_web.dart` (the phone app is still `lib/main.dart`). It shares the Controller screens (`features/controller/controller_views.dart`), protocol and client with the phone app; `test/web_safety_test.dart` fails if phone-only code (database, audio, Wi-Fi discovery) becomes reachable from the web entry.
- **Use:** on the Player phone choose Start as PLAYER with mode Online or Auto; it shows a room code. Enter it in the page, then confirm the 6-digit code with Accept on the Player.
- **Browser storage:** the session token, recent rooms (max 8), recent links and device name are kept in the browser's local storage. Reloading resumes without pairing again. **Disconnect** removes the session (recent rooms stay). A Player that no longer accepts the token also clears it.
- **Web is online-only** (browsers cannot reach a phone's local server).

```bash
fvm flutter run -d chrome -t lib/main_web.dart          # develop
fvm flutter build web -t lib/main_web.dart --release    # output in build/web
cd build/web && python -m http.server 8099              # serve over http, open http://127.0.0.1:8099
```

The build embeds the Supabase URL and **publishable** key from `lib/core/online_defaults.dart` (override with `--dart-define`). Anyone who can open the hosted page can see them; that is what the publishable key is for, but treat the room code and pairing as the real protection.

Checklist (real phone Player): 1. Enter the room code, Connect. 2. Accept on the Player. 3. Play/pause/seek/volume. 4. Browse Library, queue a song, play all. 5. URL tab plays the sample link. 6. Reload the page: still connected. 7. Disconnect, reload: asks for a room code again. 8. Try from a different network (mobile data).

## QR pairing and trusted devices

- **QR pairing:** the Player shows a QR code; on the Controller tap **Scan QR code**. The code is a link to the web Controller (`https://dbsuarez.github.io/remote-tunes/#/pair?...`) carrying the Player's address, its online room and a one-time ticket that replaces typing the 6-digit code. The app's scanner reads it, and any phone camera opens it as the web Controller, which connects on its own (needs the Player in online mode). Everything is after the `#`, so it never reaches the web server. The Player user still taps Accept. Typing the code, the Nearby list, manual IP and the room code remain as fallbacks. The phone app is locked to portrait.
- **Trusted devices:** accepting a Controller also trusts it. The Player keeps only a SHA-256 hash of its token (database schema v2); the Controller keeps its token in the app's private storage. Next time, **Your Players** on the Controller screen reconnects in one tap, and the Player used last reconnects automatically when the Controller screen opens, locally or online, with no pairing. The Player lists trusted Controllers and can **Forget** one (or all); the Player's Disconnect button also forgets. A Controller that was forgotten gets a clear message and is asked to scan the QR code again. Picking a trusted Player in the Nearby list, or typing its address or room code, also reconnects without a code (matched by room code, address or a unique name, so renaming the Player is fine). If another Controller (for example the web page) takes over the Player, this phone keeps the saved Player and can take it back with one tap.
- **Stable room code:** because trusted phones must find the Player online again, the Player now keeps its room code between runs (it used to change at every start). **Forget all** makes a new one. Pairing still needs Accept, and reconnecting needs the secret token, so knowing the room code alone gets nobody in.
- **Limits:** the token on the Controller is not in the Android Keystore (plain app-private storage, like the web version in browser storage). One Controller at a time: a trusted phone coming back replaces the connected one.

## Web Controller on GitHub Pages

The web Controller is published automatically from `main` by `.github/workflows/pages.yml` to **https://dbsuarez.github.io/remote-tunes/**.

One-time setup in the repository: **Settings → Pages → Build and deployment → Source: GitHub Actions**. After that every push that changes `lib/`, `web/` or `pubspec.*` rebuilds the page (Actions tab shows progress; you can also run the workflow by hand). The page uses the same Supabase defaults as the phone app, so it works with no setup. Local build with the same path: `fvm flutter build web -t lib/main_web.dart --release --base-href /remote-tunes/`.

## Shorter screens (Phase 7)

- **Player screen** has three tabs: *Player* (now playing and controls), *Connect* (QR code, room code, address, trusted Controllers) and *Music* (add songs, library, queue, URL). Who is connected, errors and a pairing request stay pinned on top of every tab.
- **Controller** keeps a mini control bar (title, previous, play/pause, next) under the Queue, Library and URL tabs, so there is no going back to Now Playing to pause. The "Other ways to connect" fallbacks are folded away under the Scan QR button.
- **Sleep timer:** on the Controller's Now Playing tab pick 15 min to 2 hours; the Player pauses when it runs out (even if the Controller has gone), and the Controller shows the countdown. Protocol: `setSleepTimer {minutes}` (0 cancels), `state.sleepTimerSeconds`.

## Favorites, playlists, speed, art (Phase 7)

- **Library chips:** Songs, Artists, Albums, **Favorites**, **Recent**, **Playlists**. The heart on a song toggles a favorite; the song menu has *Add to playlist*. A playlist opens like an album (Play all, Rename, Delete, remove a song). Deleting a playlist keeps the songs.
- **Now Playing (Controller):** a heart for the current song, a **Speed** picker (0.5x to 2x, kept for the next songs) and the album art.
- **Album art** is sent as a small JPEG thumbnail (at most 256 px and 60 KB), never the file or its path. Now Playing and the mini bar use the big one; song rows (Library, Queue, Favorites, playlists, on both phones) ask for a 96 px one, a few at a time, and show a music note when the song has no art.
- **Settings > Diagnostics:** version, network addresses, library counts, with a Copy button. It holds no keys, tokens, room codes or file names.
- The database moved to version 3; upgrading keeps the library.
- **Multi-select:** long-press a song to start selecting; tap to pick more, then *Select all*, *Add to queue* or *Add to playlist*.
- **Song list text size:** Settings > Song list > Small (default), Normal or Large.
- **Play now keeps the queue:** tapping a single song inserts it after the current one and plays it, leaving the rest of the queue. *Play all*, and tapping a song inside an album, playlist, Favorites or Recent, still replace the queue.
- **The queue survives restarts:** library songs are saved in `queue_items` and Online Library tracks in `queue_streams` (links and text only), in their mixed order; the Player comes back paused on the same song.
- The web Controller remembers its name as you type it (per browser) and says which name it is connecting as.
- Sliders (progress bar, volume) hold the released value until the Player confirms, so they no longer snap back.

## Online Library (Phase 8)

The Controller (phone and web) has an **Online** tab that searches [Jamendo](https://www.jamendo.com)'s free, Creative Commons catalogue by keyword, genre, artist or album. Each result shows title, artist, album, length, artwork and its licence (tap the licence to read it). **Play on Player** sends the track's stream link to the Player with the existing `playUrl` command; **Add to queue** is the same command with `queue: true`.

- **Needs your own free Jamendo client ID** (developer.jamendo.com > create an application). Paste it in the Online tab. It is kept on that device only (never in the repository, never sent to the Player).
- **Presetting the ID for your own builds:** put `{"JAMENDO_CLIENT_ID": "<your id>"}` in `docs/jamendo.json` (git-ignored, so it never reaches the public repository) and build with `fvm flutter build apk --debug --dart-define-from-file=docs/jamendo.json`. The app then has the ID built in; an ID pasted in the Online tab always wins. The GitHub Pages web build has no ID (it is built on GitHub), so the web page asks once per browser.
- **The search runs on the Controller**, so that device needs internet; with none, the tab says so and nothing else is affected. The Player needs internet to stream. Local mode and your own music work without Jamendo or any ID.
- **Nothing is downloaded or stored** (no download button), and there is no telemetry. The only network calls are to `api.jamendo.com` (and Jamendo's image server for artwork).
- **Online history:** every Jamendo track played is remembered on the **Player** phone (title, artist, album, licence and links only, never audio), newest first, up to 200. Open it with the clock button in the Online tab: play again, add to the queue, remove one, **Clear**, or switch **Keep history** off. It is never sent anywhere; a Controller plays an entry again by id and never sees the stream link.
- **Queued Jamendo tracks survive restarts** (their link and text are saved with the queue, in order among your own songs; Jamendo's links keep working because only the track id matters).

## Testing on the phones

Most features were verified by automated tests only. [docs/19_PHONE_TEST_CHECKLIST.md](docs/19_PHONE_TEST_CHECKLIST.md) is a tick-box list for trying everything by hand on two phones and the web page.

## License

MIT, see [LICENSE](LICENSE).

### Testing Phase 1 on two phones

1. Phone A: Home → **Start as PLAYER**. Note the address shown (e.g. `192.168.1.20 : 8765`).
2. Phone B: Home → **Start as CONTROLLER**. Pick Phone A from "Nearby Players", or connect manually with the address.
3. Phone A shows a 6-digit code with Accept/Reject. Enter the code on Phone B and tap **Accept** on Phone A.
4. Phone B can now play/pause, skip, seek and change volume; state updates appear on both phones.
5. Repeat on a hotspot and in airplane mode with Wi‑Fi/hotspot on. On hotspots, mDNS often fails, so use manual IP.

Phase 3 adds direct internet audio (http/https links to an audio file):
- **Player:** "Play URL" screen. **Controller:** a URL tab that sends the link to the Player. The audio always plays on the Player, which needs internet; local music still works offline.
- Links are validated (`core/url_validation.dart`), then the Player runs a quick pre-flight check (`HttpUrlChecker`: HEAD, falling back to a 1-byte GET) so failures are explained: no internet, not found, access refused, timeout, or "this is a web page, not audio".
- A played link replaces the queue and is shown as "Internet audio". It is not added to the library. Its address is never sent back to Controllers.
- Recent links (max 20) are kept per phone in the existing `recent_urls` table.
- `android:usesCleartextTraffic="true"` is set so plain `http://` links work (FR-57). Streaming apps' and video pages' links (YouTube, Spotify, etc.) will not work; those need a direct audio file link.

Phase 4 adds optional online control through **Supabase Realtime Broadcast** (no tables, no login, no music):
- **Modes** (Home screen / Settings): *Local only* (never touches Supabase), *Online only* (the Player opens no local server; Controllers join with a room code), *Auto* (the Player does both; a Controller tries the local network first and falls back to online).
- **Room code:** the Player shows an 8-character code (e.g. `ABCD-2345`), new every time Player mode starts. Channel name: `remotetunes:<room-code>`. Pairing is the same as locally (6-digit code + Accept), and a paired session can move between Wi‑Fi and online without pairing again (same token).
- **Auto fallback:** a Player on the local network also advertises its room code, so choosing it in "Nearby Players" gives the Controller both routes. If Wi‑Fi drops, it reconnects over the relay on its own.
- **Setup (Settings → Online relay):** this build already knows its Supabase project (`lib/core/online_defaults.dart`: the Project URL and the *publishable* key, which is meant to be public). You only need to turn the relay **on** (it stays off by default) and can tap **Test online relay**. What you type in Settings always overrides the defaults; clearing the fields goes back to them. To build for another project without editing code: `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_KEY=…`. Never put the `service_role` key or a database password in the app. In the Supabase dashboard, Realtime settings must allow public access (Broadcast without sign-in).
- **Same protocol over a different transport:** `OnlineRelayHost` (Player) turns each Controller on the relay into a virtual connection for the existing server; `OnlineTransport` (Controller) implements `RemoteTransport`. All of it is tested against an in-memory relay (`test/helpers/in_memory_relay.dart`).
- **Security model (v1, no login):** anyone who knows the room code can join the room, so the code is random (about 40 bits) and short-lived, and commands still need pairing + the Player user tapping Accept. Messages on the relay are not encrypted at the application level; Supabase can see command and status traffic, never music or file paths. Hardening (e.g. encrypting messages with a key derived from the room code) is a possible later step.
- **Limits:** a message over ~200 KB is refused; over the relay `getQueue` returns at most 250 items (with the real total).

Phase 5 adds **External App Control**: a Controller can play, pause, skip, seek and set volume in Spotify, YouTube Music or another music app running on the Player phone. It does **not** promise full control (docs/13, FR-82).
- **Opt-in:** Settings → External app control (off by default, with a consent explanation). With it off, no other app is ever looked at, and Controllers are not offered it.
- **How it works:** Android lets an app with *Notification access* read other apps' media sessions. A small Kotlin service (`MediaListenerService`, deliberately empty: it never reads notification contents) plus `ExternalMediaBridge.kt` expose the active session over a platform channel. Dart side: `ExternalAppEngine` (controls the other app) and `ControlModeEngine` (switches between RemoteTunes' own player and the other app, pausing the one being left so two apps never play at once).
- **Switching:** on the Player card, or remotely from the Controller's Now Playing tab (new `setControlMode` command), once the Player has opted in. In external mode the queue, library and URL tabs are replaced by an explanation, and seek/skip are disabled when the other app does not allow them.
- **Privacy:** only app name, title, artist, album, position and play state are read; nothing is stored; package names and notification text never leave the Player.
- **Sideloaded builds on Android 13+:** the Notification access switch is greyed out until you open App info → ⋮ → "Allow restricted settings". The Player card explains this and has a button for it.
- **RemoteTunes' own media session is ignored**, so it never controls itself.

### Testing Phase 5 (needs Spotify or YouTube Music on the Player phone)

1. Player phone: Settings → turn on External app control (read the explanation).
2. Player phone: Home → Start as PLAYER. In the **External App Control** card choose **Other music app**. If asked, follow the steps: (Android 13+: App info → ⋮ → Allow restricted settings), then Allow notification access for RemoteTunes, then come back.
3. Start a song in Spotify / YouTube Music on the Player phone. The card should say "Controlling Spotify" (or the app's name).
4. Controller: pair as usual. On **Now Playing**, the "Other music app" switch should be there. Try play/pause, next, previous, seek, volume. Title and artist should follow the other app.
5. Check the limits: with an ad or a podcast, skipping or seeking may be disabled (the buttons grey out). Queue/Library/URL tabs should say they are unavailable.
6. Switch back to RemoteTunes: the other app should pause and RemoteTunes' queue works again. Starting external mode while RemoteTunes plays should pause RemoteTunes.
7. Close the other app: the Player should say no music app is playing, not crash. Turn Notification access off in Android: switching should explain what to do.
8. Try both phones as Player (the X695 is Android 11, the X6873 is Android 16: the permission steps differ).

### Testing Phase 4 (needs a Supabase project)

1. Nothing to set up in Supabase: the real relay was checked against this build's project (connect, two-way messages, and a full Player/Controller session over it). No tables, triggers or policies are needed.
2. On **both** phones: Settings → Online relay: turn it **on** (URL and key are pre-filled), tap **Test online relay** (should say "Connected").
3. Player phone: Home → mode **Online only** (or Auto) → **Start as PLAYER**. Note the room code.
4. Controller phone: switch **its** Wi‑Fi off (mobile data only) or use another network. Mode **Online only** → **Start as CONTROLLER** → enter the code → pair → play, seek, volume, queue, library, URL.
5. Auto: both phones on Wi‑Fi in Auto. Pick the Player under Nearby Players (it says "also online"), pair, then turn the Controller's Wi‑Fi off: it should reconnect online (pill turns violet) without re-pairing. Turn Wi‑Fi back on and drop the connection: it should prefer local again.
6. Local only with Wi‑Fi but **no internet**, and Airplane mode + hotspot: local control must still work (no Supabase involved).
7. Wrong URL/key, wrong room code, offline phone: each should show a clear message.

### Testing Phase 3 on two phones

Use a direct link to an MP3 (for example from your own server or a public sample). Both phones need Wi‑Fi or mobile data on the **Player**.
1. Player: **Play URL**, paste a link, tap Play. It says "Checking the link…", then plays. "Internet audio" shows on the card.
2. Controller: **URL** tab, send a link. The Player plays it, and state (title, pause/resume, volume) follows.
3. Try bad input: a web-page link (e.g. a YouTube page), a wrong address (404), `ftp://…`, and a link with the Player in Airplane mode with Wi‑Fi for the local connection only. Each should show a clear message and leave playback unchanged.
4. Switch the Player to Airplane mode (keep the local Wi‑Fi link) during a stream: you should see an error in the Now Playing card, and Play should work again once internet is back.
5. Recent links: re-play, remove, clear. Local songs must still play with no internet.

### Testing Phase 2 on two phones

Test phones: **Infinix X6873 = Player**, **Infinix X695 = Controller** (the other phone).

On the Player (X6873):
1. Open Player mode, allow notifications when asked. Tap **Add songs**, pick a few MP3s. Check the summary, then open **Library**: titles, artists, album art.
2. Tap **Add folder** (allow music access) and pick a music folder. Re-adding the same folder must add nothing.
3. Tap a song: sound plays. Check the queue, shuffle, repeat, drag-reorder and remove.
4. Lock the screen and open another app: music must keep playing, and the notification must show title, art and working play/pause/next/previous.

On the Controller (X695): pair as in Phase 1, then
5. **Library** tab: search, browse Artists and Albums, tap a song, use "Play next" and "Add to queue", and "Play all" on an album.
6. **Queue** tab: reorder with the handle, remove, clear, shuffle, repeat. Changes made on the Player appear here, and vice versa.
7. With the Player's screen off for several minutes, the Controller must still be able to pause and skip. If it disconnects, note how long it took (battery/Wi‑Fi sleep).
8. Delete one imported folder file on the Player: it must show "File missing" and be skipped, not crash.

## Design guardrail: do not copy Spotify branding or UI

> RemoteTunes may use familiar music-player interaction patterns, but must not copy Spotify's exact visual identity, logo, color palette, icons, artwork, typography, screen layouts, or branding. The app must have its own distinct visual identity and prioritize remote-control status, connection state, and two-phone workflow.

- Use Spotify as a UX *reference*, not a visual template.
- No Spotify green (`#1DB954`), logo, or lookalike marks. No "Spotify Remote"-style names.
- Identity: dark charcoal + electric teal (local) with violet reserved for online mode.
- Connection state is the differentiator: persistent connection pill, Player name shown prominently, reconnecting banner.

Include the quote above in **every UI implementation prompt**. Full details: [`docs/15_UX_DESIGN_GUARDRAILS.md`](docs/15_UX_DESIGN_GUARDRAILS.md).

## Tech notes

- State: Riverpod. Routing: GoRouter. Storage: **Drift/SQLite is the single source of truth for settings** (no `shared_preferences` for settings).
- Database `remote_tunes.db`, schema v1 contains all five tables (`songs`, `queue_items`, `settings`, `paired_controllers`, `recent_urls`). Future migrations must preserve the library.
- `default_volume` is stored as `0.0–1.0` and displayed as `0–100%`.
- Flutter is pinned with **fvm** (see `.fvmrc`).
- `permission_handler` is held at 12.x: the 13.x/14.x Android plugin ships a Gradle script this project's Android toolchain cannot compile.
- `build_runner` is pinned to `2.4.15`: newer versions fail on Dart 3.10 because `objective_c` (pulled in by `path_provider_foundation`) uses build hooks, which `dart compile` rejects.

## How to run

Prerequisites: [fvm](https://fvm.app), Android SDK, a device or emulator running Android 10+ (API 29+).

```bash
fvm install            # installs the version pinned in .fvmrc
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs   # generates Drift code
fvm flutter run        # run on a connected device/emulator
```

Other commands:

```bash
fvm flutter analyze
fvm flutter test
fvm flutter build apk --debug
```

Re-run `build_runner` whenever `lib/data/database/tables.dart` or `app_database.dart` changes.
Generated `*.g.dart` files are not committed-by-hand; regenerate them as above.
