# RemoteTunes Local Library — Auto-Tagging Handoff Plan

## Purpose

Add a **batch auto-tagging system** for the existing Local Library in RemoteTunes.

The user already has approximately **2,000 local songs** in the app. It is not practical to review every song manually. Therefore, the system must automatically clean and enrich metadata while preserving existing good information.

The core rule is:

```text
Trust existing good tags.
Auto-fill only missing fields.
Auto-correct only high-confidence matches.
Send uncertain or conflicting songs to a review queue.
```

This feature is for the **existing local songs already added to the Local Library**. It is separate from the future Cloud Library upload flow.

## Current app assumption

RemoteTunes is already built or near completion and has:

- Local MP3 library
- Local song metadata stored in local SQLite
- Playback through the Player phone
- Remote control from Controller phone
- Existing queue and playback-state sync
- Existing `playUrl` command
- Supabase Realtime for online control
- Cloudflare R2 bucket named `remotetunes` for a future Cloud Library

This feature updates the **local library metadata**, not the Player playback engine.

## Architecture

```text
Local MP3 files
        |
        | Scan and read existing ID3 tags
        v
Local SQLite metadata database
        |
        | Identify missing or uncertain metadata
        v
AcoustID / MusicBrainz lookup
        |
        | High-confidence match
        v
Update local SQLite metadata
        |
        | Optional later step
        v
Write cleaned tags back into MP3 files
```

## Important rule

Do **not** automatically overwrite existing non-empty metadata.

If a song already has a valid title, artist, album, genre, year, track number, or artwork, keep it.

Only fill fields that are missing. Only correct a field when the match confidence is high and the existing value is empty, invalid, or clearly conflicting.

## Three-tier tagging system

| Confidence | What the app does | User action |
|---|---|---|
| Existing tags are complete | Keep them | None |
| Tags are missing | Fill from embedded tags, filename, duration, and AcoustID/MusicBrainz | None if confidence is high |
| Tags conflict or match is uncertain | Keep current tags, add to review queue | Review later |
| No reliable match | Mark as “Needs info” | Review or edit manually |

## Fields to process

Read and manage these metadata fields:

```text
Title
Artist
Album
Album artist
Track number
Year
Genre
Artwork
Duration
```

## What should be automatic

For each local song, the app should automatically:

1. Read existing ID3 tags
2. Read duration and embedded artwork
3. Check whether title and artist already exist
4. Parse the filename if tags are missing
5. Generate an AcoustID fingerprint
6. Look up the best MusicBrainz match
7. Compare the match with the existing tags
8. Apply only safe, high-confidence updates
9. Save the result to the local SQLite metadata database
10. Add uncertain songs to a review queue

AcoustID identifies music by audio fingerprint and links results to MusicBrainz metadata. MusicBrainz Picard uses a similar fingerprint-and-metadata workflow for cleaning music libraries. [web:284][web:286]

## What should not be automatic

Do **not** automatically overwrite these fields if they already exist:

```text
Title
Artist
Album
Album artist
Track number
Year
Genre
Artwork
```

Use this rule:

```text
If existing value is present and non-empty:
    Keep it.

If existing value is missing:
    Fill it automatically if confidence is high.

If existing value conflicts with AcoustID:
    Keep existing value.
    Add song to review queue.
```

## Example: safe auto-fill

Suppose a local song has:

```text
Title: My Song
Artist: Dante
Album: [missing]
Year: [missing]
Artwork: [missing]
```

And AcoustID returns:

```text
Title: My Song
Artist: Dante
Album: Personal Mix
Year: 2024
Artwork: Available
```

The app should automatically save:

```text
Title: My Song       [kept]
Artist: Dante        [kept]
Album: Personal Mix  [filled]
Year: 2024           [filled]
Artwork: Added       [filled]
```

No user review is needed.

## Example: conflict handling

Suppose AcoustID returns:

```text
Title: Different Song
Artist: Different Artist
```

But the local song already has:

```text
Title: My Song
Artist: Dante
```

The app must **not** overwrite the existing tags.

Instead, add the song to the review queue:

```text
Possible mismatch

Current:
Title: My Song
Artist: Dante

Suggested:
Title: Different Song
Artist: Different Artist

Confidence: Medium

[ Keep current ] [ Use suggestion ] [ Ignore ]
```

## Batch Tag Cleanup screen

Add a **Tag Cleanup** screen to the Local Library.

```text
Local Library Tag Cleanup

Total songs: 2,000
Already tagged: 1,650
Missing title: 120
Missing artist: 95
Missing album: 310
Missing artwork: 420
Possible mismatches: 65
No match found: 38

[ Start auto-tagging ]

Progress:
Processed 312 / 2,000
High-confidence updates: 280
Needs review: 24
No match: 8
```

The process must show progress and remain usable while running.

## Background job design

Use a local SQLite table called `tag_jobs`.

```sql
create table tag_jobs (
  id text primary key,
  song_id text not null,
  status text not null,
  current_title text,
  current_artist text,
  current_album text,
  suggested_title text,
  suggested_artist text,
  suggested_album text,
  confidence real,
  error_message text,
  created_at text,
  updated_at text
);
```

### Job statuses

```text
pending
processing
tagged
needs_review
no_match
failed
skipped
```

The job queue must be resumable. If the app closes or the phone restarts, it should continue from where it left off.

## Safe auto-tag rules

Apply an update automatically only when:

- Existing field is empty
- AcoustID confidence is high
- Filename and audio fingerprint agree, or filename is not contradictory
- The song duration is reasonably close to the matched recording
- The artist/title match is strong
- The match has a MusicBrainz recording ID

Do **not** auto-apply when:

- Existing title and suggested title differ
- Existing artist and suggested artist differ
- Confidence is low or medium
- Multiple plausible matches exist
- The file is a remix, live version, or cover
- The duration differs significantly

## Review queue

Only uncertain songs should require review.

```text
Needs Review: 65 songs

Song 1
Current: Unknown Title — Unknown Artist
Suggested: My Song — Dante
Confidence: Medium
Duration match: Yes

[ Use suggestion ] [ Keep current ] [ Skip ]

[ Approve all high-confidence ]
[ Review later ]
```

The goal is to reduce the review queue to a manageable number, not to force the user to inspect all 2,000 songs.

## Where metadata is saved

For existing local songs, save cleaned metadata in the app’s local SQLite database first.

```text
Local MP3 file stays on phone
Local SQLite metadata gets updated
Cloud Library catalog gets created later
```

Do **not** rewrite all 2,000 MP3 files immediately.

Use this sequence:

```text
Phase A: Update local SQLite metadata only
Phase B: Optionally write tags back into MP3 files
Phase C: Upload selected songs to Cloud Library
```

Writing ID3 tags can require modifying the MP3 file, so it should be optional and performed only after the user chooses to apply cleaned tags to the actual files.

## Recommended workflow

```text
1. Scan 2,000 local songs
2. Read existing tags
3. Identify missing fields
4. Generate fingerprints only for songs that need help
5. Query AcoustID/MusicBrainz
6. Auto-fill safe missing fields
7. Keep existing good tags
8. Put conflicts in review queue
9. Save cleaned metadata to local SQLite
10. Later, optionally write tags back to MP3s
11. Later, upload selected songs to R2 Cloud Library
```

## Flutter packages

Consider these Flutter packages for reading and writing audio metadata:

- `flutter_audio_tagger`
- `audiotags`

Choose one after testing Android MP3/ID3 support, artwork extraction, duration handling, and write reliability.

`audiotags` is a Flutter package for reading and writing audio metadata across multiple formats. [web:283]

## AcoustID and MusicBrainz

Use AcoustID and MusicBrainz for songs with missing or uncertain metadata.

AcoustID identifies audio by fingerprint and returns matches linked to MusicBrainz metadata. It works best for well-known commercial recordings, but it may not correctly identify personal recordings, remixes, live versions, covers, or rare/local songs. [web:284][web:286]

Always treat lookup results as suggestions. The app may auto-apply only high-confidence matches that do not conflict with existing metadata.

## Build phases

### Phase 1 — Scan and report

Build only this first:

- Scan all local songs
- Read existing ID3 tags
- Detect duration and artwork
- Show summary:
  - Total songs
  - Complete tags
  - Missing title
  - Missing artist
  - Missing album
  - Missing artwork
  - Possible mismatches
  - No match found

Do not modify any metadata in this phase.

### Phase 2 — Safe auto-fill

Add:

- Filename parsing
- Fill only missing fields
- Preserve existing non-empty values
- Save cleaned metadata to local SQLite
- Show progress
- Make the job resumable

### Phase 3 — AcoustID/MusicBrainz matching

Add:

- Audio fingerprint generation
- AcoustID lookup
- MusicBrainz metadata enrichment
- Confidence scoring
- Conflict detection
- Review queue
- Bulk approval for high-confidence suggestions

### Phase 4 — Optional MP3 tag writing

Add:

- Write cleaned tags back into MP3 files
- User chooses whether to apply changes to actual files
- Backup or undo strategy
- Batch processing with progress

### Phase 5 — Cloud Library preparation

Add:

- Select cleaned local songs
- Upload selected songs to R2
- Create Supabase catalog entries
- Reuse cleaned metadata for Cloud Library

## What not to build yet

Do not build these in the first version:

- AI genre classification
- Mood detection
- BPM detection
- Lyrics tagging
- Automatic artwork downloading from the internet
- Bulk tag rewriting without user choice
- Silent overwriting of existing metadata
- Cloud Library upload during auto-tagging
- Multi-user libraries
- Social features
- DRM

## Success criteria

The Local Library auto-tagging feature is successful when:

- The app can scan all local songs.
- Existing good metadata is preserved.
- Missing metadata is automatically filled when confidence is high.
- Conflicting or uncertain songs go to a review queue.
- The user does not need to review all 2,000 songs.
- The process can run in the background and resume after interruption.
- The local SQLite metadata database is updated safely.
- MP3 files are not rewritten unless the user explicitly chooses that option.
- The cleaned metadata can later be reused for Cloud Library uploads.

## Implementation notes for coding agent

- Build this for the existing Local Library, not the Cloud Library upload flow.
- Process songs in batches.
- Preserve existing non-empty metadata.
- Auto-fill only missing fields.
- Use filename parsing before network lookups.
- Use AcoustID/MusicBrainz only when needed.
- Save cleaned metadata to local SQLite first.
- Do not rewrite MP3 files automatically.
- Make the background job resumable.
- Show clear progress and summary statistics.
- Send only uncertain or conflicting songs to review.
- Allow bulk approval only for high-confidence suggestions.
- Do not break existing playback, queue, or remote-control features.
- Do not create multiple Cloudflare accounts or upload the full library automatically.
