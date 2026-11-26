# What RemoteTunes sends, and to whom

RemoteTunes has no account, no analytics and no advertising. Your music files stay on your phones: they are never uploaded anywhere. This page lists everything that leaves a phone over the internet, and how to turn it off.

## Between your own phones
- **Local network:** a Controller phone talks directly to the Player phone over Wi-Fi or a hotspot. Nothing goes through the internet.
- **Online relay (off by default):** if you turn it on, control messages (play, pause, titles, song lists) pass through a Supabase Realtime channel named by the room code. No audio and no files go through it. Anyone who knows the room code could join the channel, so the code is only shown on the Player and is long and random. See [docs/12](12_PHASE_4_ONLINE_REMOTE_CONTROL.md).
- **Group play:** the Controller downloads the song file *from the Player phone* (over the local network) to play along. It does not go to any server.

## Services contacted by the phone itself
Each one only when you use the feature, and each can be switched off or simply not used.

| Feature | Service | What is sent | Switch |
|---|---|---|---|
| **Lyrics** | LRCLIB (lrclib.net), then lyrics.ovh | The song's title, artist, album and length. Never file names or paths. The answer is kept on the Player. | Settings > Look and feel > Lyrics from the internet |
| **Look up this song** | MusicBrainz, the Cover Art Archive and the lyrics sources | The song's title, artist, album and length, for the one song, only when you tap the button in Edit info. | Only runs when you tap it |
| **Insights and play history** | Nobody | Nothing leaves the phone: the numbers (and the play history, a note of each song played) are worked out and kept on the phone. In a backup file only if you leave *Include play history* on. | Menu > Insights |
| **Ambience** | Nowhere | The sound files you add are copied into the app on this phone; your mixes and settings stay there. When you control another phone, only your commands and the list of sound names go to it. | Never goes online by itself |
| **Cloud Library** | Your own Cloudflare R2 bucket | Browsing reads one file (`catalog.json`) and playing streams a song from your bucket's public address. Uploading sends the song files, their covers and the catalog (titles, artists, albums, genres) to your bucket, signed with your R2 keys. The keys stay on the phone: never in a backup, never in the app's code. On the web page the keys are saved in that browser's storage only (not sent anywhere but Cloudflare). Anyone who knows a song's exact public link can fetch it (the bucket's public address is not private). Which cloud songs you started on this device (for *Recently played*) and your sort choice are kept on that device only. | Only when you open the Cloud Library, play from it, or upload; leave the address empty to switch it off |
| **Tag cleanup > Search online** | MusicBrainz | The title, artist, album and length of each music song that lacks an album or a year, one at a time (about one a second). File names and paths are never sent. | Only runs when you tap *Search online* |
| **Find missing album art** | MusicBrainz and the Cover Art Archive | The artist and album names, one album at a time, about once a second. | Only runs when you start it (Settings > Find missing album art) |
| **Online Library** | Jamendo (api.jamendo.com) | Your search words, and the Jamendo client ID of this build. Tracks stream from Jamendo. | Only when you open the Online Library |
| **Updates** | GitHub (api.github.com, github.com) | A request for the latest release of this app. Nothing about you or your phone. | Settings > App updates > Check automatically |
| **Play a link** | The address you type | A normal download request for that address. | Only when you play a link |

None of these receive your name, your device name, your account (there is none) or your location. Like any web request they can see your phone's IP address.

## Stored on the phone
- The library (titles, artists, albums, tags, play counts, favorites, playlists), the saved queue, settings, search history, lyrics and equalizer settings, and the trusted Controllers. All of it stays in the app's private storage and is removed when the app is uninstalled.
- **Microphone:** used only for Auto-align in group play, to hear a short click track. Nothing is recorded to a file or sent anywhere.
- **Camera:** only to scan the pairing QR code. Nothing is saved.
- **Notification access** (optional, off by default): lets the app control another music app on the Player phone. It reads that app's playback controls and song title, never the contents of notifications.

## Keys
The Supabase address and public (anon) key built into the app are meant to be public. The signing key and any secret keys are never in the repository.
