# RemoteTunes Cloud — Handoff Plan

## Status

**Cloudflare R2 setup is complete and verified.**

- One Cloudflare account created
- R2 enabled
- One R2 bucket created: `remotetunes`
- Public development URL enabled
- Test MP3 uploaded and played successfully
- R2 API token created
- Next step: build Cloud Library v1 and connect it to Supabase

## Purpose

Add a **personal Cloud Library** to RemoteTunes as a new music source.

This feature must not replace or disrupt the existing app architecture. RemoteTunes remains offline-first, with local MP3s, direct URL playback, Jamendo Online Library, and existing local/Supabase Realtime remote control.

The Cloud Library lets the user upload and organize their own MP3 files, browse them by song, artist, album, genre, and playlist, then send a selected song to the Player for streaming playback.

## Current app assumption

The app is already built or near completion and already supports:

- Local MP3 library
- Direct online audio URL playback
- Local Android Player with WebSocket server
- Controller discovery and manual IP/port connection
- Pairing/session token
- Playback commands and playback-state sync
- Supabase Realtime for online Controller-to-Player control
- Jamendo Online Library as a separate online source
- Existing `playUrl` command

The Cloud Library is added as an additional source:

```text
Music Sources
├── Local Library
├── Online Library (Jamendo)
├── Cloud Library (personal R2 library)
└── External Apps (Spotify / YouTube Music)
```

## Core rule

Do **not** change the Player into a cloud-aware app.

The Player continues to receive a normal playable URL:

```json
{
  "type": "command",
  "sessionId": "session-id",
  "requestId": "request-id",
  "payload": {
    "action": "playUrl",
    "url": "https://pub-xxxxxxxxxxxxxxxx.r2.dev/songs/my-song.mp3",
    "title": "My Song",
    "artist": "Artist Name"
  }
}
```

The Controller fetches the Cloud Library catalog, obtains the MP3 URL, and sends `playUrl` to the Player.

## Architecture

```text
Controller phone / Web Controller
        |
        | Browse Cloud Library
        v
Supabase catalog
        |
        | Returns song metadata + R2 audio URL
        v
Cloudflare R2
        |
        | Streams MP3
        v
Player phone
        |
        | just_audio plays URL
        v
Speaker
```

### Responsibilities

| Component | Responsibility |
|---|---|
| Supabase | Song catalog, artists, albums, genres, playlists, Realtime control |
| Cloudflare R2 | Actual MP3 files and album artwork |
| Controller | Browse catalog, search, queue, send commands |
| Player | Stream and play the MP3 URL |
| Local library | Remains offline-first and unchanged |

## Cloudflare R2 setup

Use **one Cloudflare account** and **one R2 bucket** only.

Do not create multiple Cloudflare accounts to combine free storage allowances. That creates account-management, credential, billing, and terms-of-service risk.

### Confirmed setup

```text
Cloudflare account: One account only
R2 bucket name: remotetunes
Public development URL: Enabled
Test MP3: Uploaded and played successfully
R2 API token: Created
```

### R2 free tier

Cloudflare R2 free tier includes:

- 10 GB-month of Standard storage
- 1 million Class A operations per month
- 10 million Class B operations per month
- No egress fees
- S3-compatible API

R2 is preferred over Supabase Storage because Supabase Free only includes 1 GB file storage, which is too small for a few GB music library.

### Storage math

At 128 kbps, a typical MP3 is about 1 MB per minute.

| Library size | Approximate song capacity |
|---|---:|
| 1 GB | About 250 songs |
| 5 GB | About 1,250 songs |
| 10 GB | About 2,500 songs |
| 20 GB | About 5,000 songs |

Actual capacity depends on bitrate, song length, artwork, and duplicate files.

### R2 folder structure

Use this structure inside the `remotetunes` bucket:

```text
songs/
artwork/
```

Example:

```text
songs/song-id.mp3
artwork/album-id.jpg
```

Do not upload MP3s directly into the bucket root.

### Public URL format

The public bucket URL follows this format:

```text
https://pub-xxxxxxxxxxxxxxxx.r2.dev
```

A song URL will look like:

```text
https://pub-xxxxxxxxxxxxxxxx.r2.dev/songs/test-song.mp3
```

### Credentials

Store these privately in a password manager or secure note:

```text
R2 bucket name: remotetunes
R2 public URL: https://pub-xxxxxxxxxxxxxxxx.r2.dev
R2 Access Key ID: [stored privately]
R2 Secret Access Key: [stored privately]
R2 S3 endpoint: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

Never commit the Secret Access Key to GitHub, Flutter source code, or a public handoff document.

## Recommended services

| Service | Use |
|---|---|
| Cloudflare R2 | MP3 files and album artwork |
| Supabase | Song catalog, artists, albums, genres, playlists, Realtime control |
| Local device storage | Offline-first local MP3 library |
| Jamendo | Separate free online discovery source |

Do **not** use Supabase Storage for the full MP3 library unless the library remains under 1 GB.

## Database design

Create these Supabase tables:

```text
artists
albums
genres
songs
playlists
playlist_songs
```

### artists

```sql
create table artists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  artwork_url text,
  created_at timestamptz default now()
);
```

### albums

```sql
create table albums (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  artist_id uuid references artists(id) on delete set null,
  artwork_url text,
  release_year integer,
  created_at timestamptz default now()
);
```

### genres

```sql
create table genres (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  created_at timestamptz default now()
);
```

### songs

```sql
create table songs (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  artist_id uuid references artists(id) on delete set null,
  album_id uuid references albums(id) on delete set null,
  genre_id uuid references genres(id) on delete set null,
  duration_seconds integer,
  audio_url text not null,
  artwork_url text,
  is_public boolean default false,
  created_at timestamptz default now()
);
```

### playlists

```sql
create table playlists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  created_at timestamptz default now()
);
```

### playlist_songs

```sql
create table playlist_songs (
  id uuid primary key default gen_random_uuid(),
  playlist_id uuid references playlists(id) on delete cascade,
  song_id uuid references songs(id) on delete cascade,
  position integer not null,
  created_at timestamptz default now()
);
```

## Cloud Library data model

A Cloud Library song should map to this app-side model:

```dart
class CloudSong {
  final String id;
  final String title;
  final String? artistName;
  final String? albumName;
  final String? genreName;
  final int? durationSeconds;
  final String audioUrl;
  final String? artworkUrl;
}
```

## Controller UI

Add a new source tab:

```text
Music Sources

[ Local Library ]
[ Online Library ]
[ Cloud Library ]
```

### Cloud Library screen

```text
Cloud Library

[ Search songs, artists, genres ]

Genres:
[ All ] [ Rock ] [ OPM ] [ Acoustic ] [ Instrumental ]

Song title
Artist — Album
3:24
[ Play on Player ] [ Add to queue ]

Bottom tabs:
[ Cloud Library ] [ Playlists ] [ Recently Played ]
```

### Required actions

Each song should support:

- Play on Player
- Add to queue
- Add to playlist
- View artist
- View album
- Filter by genre
- Search by title, artist, or album

## Playback flow

1. Controller opens Cloud Library.
2. Controller requests songs from Supabase.
3. Supabase returns song metadata and R2 audio URL.
4. Controller displays the song.
5. User taps **Play on Player**.
6. Controller sends `playUrl` command to Player.
7. Player streams and plays the MP3.
8. Player reports playback state back to Controller.
9. Controller updates Now Playing UI.

## Queue behavior

Cloud songs must work with the existing queue.

When a user taps **Add to queue**, the Controller should add a queue item containing:

```dart
QueueItem(
  sourceType: QueueSourceType.cloud,
  title: song.title,
  artist: song.artistName,
  artworkUrl: song.artworkUrl,
  audioUrl: song.audioUrl,
  durationSeconds: song.durationSeconds,
)
```

The Player should treat a Cloud Library queue item the same as an online URL item.

## Auto-tagging

Add optional auto-tagging during Cloud Library upload. It should help fill missing metadata, but it must never silently overwrite good existing tags.

### Recommended flow

```text
User selects MP3
   |
   v
Read embedded ID3 tags
   |
   v
Detect duration and artwork
   |
   v
Parse filename if fields are missing
   |
   v
Optional AcoustID / MusicBrainz lookup
   |
   v
Show review screen
   |
   v
User approves or edits
   |
   v
Save metadata to Supabase
   |
   v
Upload MP3 and artwork to R2
```

### Fields to read

Read these from embedded MP3 metadata:

- Title
- Artist
- Album
- Album artist
- Track number
- Year
- Genre
- Embedded artwork
- Duration

### Filename fallback

If embedded tags are missing, parse the filename:

```text
Dante - My Song.mp3
```

Suggested result:

```text
Artist: Dante
Title: My Song
```

### AcoustID and MusicBrainz

Use AcoustID and MusicBrainz only for missing or uncertain metadata.

AcoustID identifies audio by fingerprint and links matches to MusicBrainz metadata. It is best for well-known commercial recordings, but it may not correctly identify personal recordings, remixes, live versions, or rare/local songs.

Always show AcoustID results as suggestions. The user must approve before the app saves them.

### Review screen

```text
Review song details

Title:    My Song
Artist:   Dante
Album:    Personal Mix
Genre:    Acoustic
Year:     2024
Track:    3
Artwork:  Found

[ Use suggested tags ]
[ Edit manually ]
[ Skip ]
```

### Flutter packages

Consider these Flutter packages for reading and writing audio metadata:

- `flutter_audio_tagger`
- `audiotags`

Choose one after testing Android MP3/ID3 support, artwork extraction, and write reliability.

### Rules

- Read existing tags automatically.
- Fill missing fields from filename when possible.
- Use AcoustID/MusicBrainz only as an optional lookup.
- Show all suggested changes for review.
- Do not overwrite good existing metadata automatically.
- Do not automatically download artwork from the internet in v1.
- Do not add AI genre, mood, BPM, or lyrics tagging in v1.

## Build phases

### 8.1 — Minimum Cloud Library

Build only this first:

- Cloud Library screen
- Song list
- Search by title
- Play on Player
- Add to queue
- Public R2 bucket
- Basic Supabase `songs` table
- Manual MP3 upload through Cloudflare dashboard or simple upload screen

At this stage, do not build playlists, albums, artists, or an admin panel.

### 8.2 — Better browsing

Add:

- Artists
- Albums
- Genres
- Album artwork
- Sort options
- Recently played
- Genre filters
- Artist and album pages

### 8.3 — Upload and management

Add:

- Upload MP3 from Controller phone or web app
- Enter title, artist, album, genre
- Upload album artwork
- Delete song
- Edit metadata
- Duplicate detection
- Auto-tagging:
  - Read embedded ID3 tags
  - Extract artwork
  - Detect duration
  - Parse filename for missing title/artist
  - Optional AcoustID/MusicBrainz lookup
  - User review before saving

### 8.4 — Private access

Add only if needed:

- Supabase Auth
- Private R2 bucket
- Signed URLs
- Owner-only access
- Short-lived playback URLs

## Public vs private R2 bucket

The current bucket is public. This is acceptable for the first personal-use version.

| Option | Best for | Notes |
|---|---|---|
| Public bucket | Simplest initial version | Anyone with the exact URL can access the file |
| Private bucket + signed URLs | Personal/private library | Requires backend or Edge Function to generate temporary URLs |

Later, move to private bucket + signed URLs for stronger privacy.

## Important legal rule

Only upload songs that the user owns, created, or has permission to host and stream.

Do **not** upload copyrighted Spotify or YouTube songs to R2, Supabase, or any personal cloud storage.

Use only:

- Songs the user created
- Songs the user purchased with hosting/streaming rights
- Creative Commons tracks with terms permitting the intended use
- Public-domain tracks
- Jamendo tracks only according to their individual license

## What not to build yet

Do not build these in the first Cloud Library version:

- Multi-user accounts
- Friend sharing
- Public music catalog
- DRM
- Music recommendations
- Social features
- Full Spotify-style catalog
- Complex royalty/licensing system
- Offline caching of every cloud song
- Background sync engine
- Automatic uploads
- Full admin dashboard
- AI genre, mood, BPM, or lyrics tagging

## Success criteria

The Cloud Library is successful when:

- User can browse their own cloud songs.
- User can search by title.
- User can filter by genre.
- User can tap Play on Player and hear the song.
- User can add a cloud song to the queue.
- Player reports correct playback state.
- Existing local library and Jamendo source remain unaffected.
- No monthly cost is required for the initial personal library.
- MP3s stream directly from R2 without downloading the entire file first.
- Auto-tagging suggests metadata but requires user approval before saving.

## Implementation notes for coding agent

- Add Cloud Library as a new source, not a replacement for local playback.
- Reuse the existing `playUrl` command.
- Reuse existing queue and playback-state sync.
- Store MP3s in Cloudflare R2.
- Store catalog metadata in Supabase.
- Do not store full MP3 files in Supabase.
- Use the existing public R2 bucket named `remotetunes`.
- Add private signed URLs later.
- Keep the Cloud Library UI separate from Local Library and Jamendo.
- Do not break offline-first behavior.
- Do not add user accounts, sharing, recommendations, or DRM in v1.
- Do not create multiple Cloudflare accounts to increase storage.
- Implement auto-tagging as review-before-save, not silent overwrite.
