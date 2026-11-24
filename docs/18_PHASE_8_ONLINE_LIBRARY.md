# Phase 8 — Online Library (Jamendo)

> Numbering: Polish is Phase 7 (docs/14) and Group Mode is Phase 9 (docs/16).

## Goal
Let the user find free, legally shareable music online from the Controller and play it on the Player, with no change to local mode.

## Provider
[Jamendo](https://developer.jamendo.com) API v3.0, `GET https://api.jamendo.com/v3.0/tracks/`. Creative Commons music, streamed. The user supplies their own free `client_id`.

## Requirements
1. **Client ID:** entered by the user in the Online tab, stored locally (shared preferences, on that device only). Never in the repository, never sent to the Player, never uploaded except to Jamendo as the `client_id` of a search. It can be changed or removed.
2. **Search** by keyword (`search`), genre (`tags`), artist (`artist_name`) and album (`album_name`). If an artist or album search finds nothing, it falls back to a wider keyword search filtered by name. Genres are single words on Jamendo ("hiphop"), so spaces are removed.
3. **Each result shows** title, artist, album, duration, artwork and licence (a short name such as "CC BY-NC-SA 3.0" derived from `license_ccurl`; tapping it shows the licence link).
4. **Play on Player:** the track's `audio` stream URL goes to the Player with the existing `playUrl` command (with optional `title`, `artist`, `album`). The Player runs its normal URL checks and streams it.
5. **Add to queue:** the same command with `queue: true`; the track joins the end of the queue and does not interrupt playback (if nothing is loaded it is lined up, not started).
6. **No internet:** a clear message ("No internet connection. The Online Library needs the internet on this phone. Your own music still works.") with Try again. Other Jamendo problems (server error, refused client ID) are explained in plain words.
7. **No downloads:** nothing is downloaded or saved, and there is no download feature. (If one is ever added it must be an explicit user action per licensed track.)
8. **No telemetry; history stays local.** Nothing is sent anywhere but to Jamendo itself (search request, artwork images). Searches are not recorded. What was *played* is kept in an **online history on the Player** (see below), on the device only.
8a. **Online history:** each Jamendo track that starts playing is recorded on the Player (title, artist, album, licence link, artwork link, stream link, time; never audio), newest first, one entry per track (playing it again moves it up), at most 200. The user can switch recording off (default on), remove one entry, or clear all. A Controller lists it with `library_request` scope `onlineHistory` (no stream links in the answer) and plays an entry again with `playHistory {historyId, queue?}`. Only tracks from jamendo.com are recorded. History is shown in the Online tab (clock button).
8b. **Queued Jamendo tracks survive restarts.** The queue store keeps internet tracks (link, title, artist, album, licence and artwork links) in `queue_streams`, sharing one position numbering with `queue_items`, so the mixed order is kept. Jamendo's `from=` token in a stream link is not checked by Jamendo (tested: a made-up or missing token still streams), so a saved link stays usable; if one ever fails, the Player skips it like any unplayable track.
9. **Local mode is unaffected:** without a client ID or internet the rest of the app behaves exactly as before.
10. **Safety:** only `https` links on `jamendo.com` are accepted from Jamendo's answers (stream and artwork); anything else is dropped.
11. **Controller and web:** the tab is part of the shared Controller dashboard, so the phone app and the web Controller both have it. (Jamendo's API allows browser requests.)
12. **UX:** follows docs/15. It uses RemoteTunes' own colours and layout (violet marks "online"), not Spotify's.

## Protocol additions (additive)
- `playUrl {url, title?, artist?, album?, license?, art?, queue?}`. `queue: true` appends instead of replacing the queue. Text fields are limited to 200 characters. `license` must be a creativecommons.org link and `art` an https link on jamendo.com, otherwise they are ignored.
- `library_request` scope `onlineHistory` returns `{items:[{id,title,artist,album,licenseUrl?,imageUrl?,playedAt}], total, offset, enabled}`.
- Commands `playHistory {historyId, queue?}`, `removeHistory {historyId}`, `clearHistory`, `setHistoryEnabled {enabled}`.

## Code
- `lib/features/online_library/jamendo_api.dart`: search, parsing, errors (pure Dart + `http`, web-safe).
- `lib/features/online_library/jamendo_key_store.dart`: local client ID storage and providers.
- `lib/features/online_library/online_library_view.dart`: the Online tab.
- Player: `QueueAwareEngine.enqueueUrl`, `PlayableSong.stream(artist, album, licenseUrl, imageUrl)`, `PlayerServer` `playUrl` and history handling.
- History: `data/repositories/online_history_repository.dart`, `online_library/online_history_view.dart`, `online_history_source.dart`. Queue: `data/repositories/drift_queue_store.dart`. Database schema v4 (`queue_streams`, `online_history`).

## Acceptance
- [x] Search by keyword, genre, artist, album (tests with a fake Jamendo).
- [x] Results show title, artist, album, duration, artwork, licence.
- [x] Play on Player and Add to queue work end to end over the protocol.
- [x] Offline and refused-ID messages; local features untouched.
- [x] Client ID kept locally; no request is made before the user searches.
- [x] History recorded on the Player, replayable by id, removable, clearable, switchable off; queued online tracks survive a restart in order.
- [x] Tried with a real client ID against the live API (keyword, genre, artist, album; real tracks, licences and stream links; the Player's own pre-flight check accepts a real stream).
- [ ] Used on two phones and in the web Controller.
- [ ] A real Jamendo stream played to the end on a real Player (sound, seeking).

## Jamendo quirk found by testing
Jamendo silently answers `success` with 0 results when searches arrive within a couple of seconds of each other. The app therefore spaces its requests at least 3 seconds apart and asks once more when a first page comes back empty, instead of reporting a false "no tracks found". (`JamendoApi.minGap`, `retryDelay`.)

## Not in this phase
Downloading tracks, favourites/playlists for online tracks, other providers, syncing history between Players.
