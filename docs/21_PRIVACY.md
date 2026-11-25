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
| **Insights and play history** | Nobody | Nothing leaves the phone: the numbers (and the play history, a note of each song played) are worked out and kept on the phone. Not in backups. | Menu > Insights |
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
