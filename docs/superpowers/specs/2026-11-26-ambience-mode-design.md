# Ambience Mode: design

Starts from the owner's spec (`remotetunes-ambience-sounds.md`). The owner approved the plan on 2026-11-26.

## Intent
A parent sets up calming sound for their child (the parent uses it; the child only hears it), on the phone that plays or from the other phone. The owner now uses another ambience app with a saved mix of **12 sounds at once**; RemoteTunes should cover that use.

## Goals
- Many looping sounds together, each with its own volume; a master volume.
- Built-in white, pink and brown noise (made by the app). Other sounds are files the owner adds (MP3, OGG, WAV, FLAC), copied into the app.
- Sound slots by category, plus sounds with any name.
- The spec's six preset mixes, plus saving and deleting named mixes.
- Sleep timer (15, 30, 45 min, 1 h, 2 h, none) that fades out over the last 5 minutes.
- A maximum volume set on the playing phone only.
- Keeps playing with the screen locked; one notification with play/pause and stop.
- Control from the other phone.
- Music and ambience never play together: starting one stops the other.

## Non-goals
Downloadable sound packs, binaural beats, "8D" effects, the web page, child-facing controls, putting recordings in the repository or APK, copying another app's artwork or sounds.

## Constraints
The repository and releases are public, so no third-party recordings are shipped. Android 10+. Cloud work is paused.

## Approaches
- **Several `just_audio` players** (one per sound). No new dependency, reuses background playback. Poor fit for 12 sounds at once: 12 decoders, and loop gaps.
- **`flutter_soloud`** (chosen). Built to mix many looping voices; new native code, and background playback and audio focus must be wired by us. First approved plan was the other one; changed after seeing the 12-sound mix.

## How
- `AmbienceController` (plain Dart): sounds, mixes, volumes, timer; talks to an `AmbienceEngine` interface so the engine can be swapped and tests need no audio.
- The existing audio service shows the ambience notification and keeps the app alive; audio focus through `audio_session`.
- The other phone sends `ambience` commands and reads `getAmbience`; the playing phone enforces the maximum volume.
- Settings are kept on the playing phone. Not in backups (yet): the sound files would not travel with them.

## To check on a phone
Gaps when MP3 files loop, battery over a night with 12 sounds, and that Android keeps it running with the screen off.
