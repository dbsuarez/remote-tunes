# RemoteTunes — Data Model (v2)

Use Drift/SQLite. DB: remote_tunes.db.

## Tables
### songs
id, title, artist, album, duration_seconds, track_number, file_path, url, album_art_path, file_size_bytes, mime_type, source(local_file|url), added_at.

Rule: song has file_path or url, not both.

### queue_items
id, song_id, position, source, added_at, added_by(player|controller).

### settings
key, value, updated_at.

Keys: device_name, default_volume, repeat_mode, shuffle_enabled, external_app_control_enabled, last_player_port, connection_mode, online_relay_enabled, supabase_url, supabase_anon_key.

### paired_controllers
session_id, controller_name, controller_address, connection_type(local|online), paired_at, last_seen_at, active.

### recent_urls
id, url, title, last_used_at.

## Schema changes after v1 (current version: 4)
- **v2:** `paired_controllers.token_hash` (SHA-256 of the session token) and `trusted`, for trusted devices.
- **v3:** `songs.favorite`, `songs.last_played_at`; tables `playlists(id, name, created_at)` and `playlist_songs(id, playlist_id, song_id, position)` (both cascade on delete).
- **v5:** `songs.play_count` (default 0; +1 each time a song starts; feeds the Top list). Existing songs keep their data and start at 0.
- **v4:** `queue_streams(id, position, url, title, artist, album, license_url, image_url)` holds internet tracks in the saved queue; its `position` shares one numbering with `queue_items.position`. `online_history(id, url UNIQUE, title, artist, album, license_url, image_url, played_at)` is the Online Library history (max 200 rows, text and links only). Settings keys added: `queue_current_index`, `queue_position_seconds` (the spot in the current song), `online_history_enabled`, `player_room_code`, `song_list_size`.
- Upgrades add columns and tables and keep the library (tested for v2 to v3 and v3 to v4).

## Dart models
```dart
enum SongSource { localFile, url }
enum RepeatMode { off, one, queue }
enum ConnectionMode { auto, localOnly, onlineOnly }
enum ConnectionType { local, online }
```

Song, QueueItem, PlaybackState, ControllerSession models as in spec.

## Rules
- Queue positions sequential.
- One current playing item.
- Tokens not plaintext in DB.
- Pairing code expires 5 min.
- Missing files marked unavailable.
- Drift migrations preserve library.
