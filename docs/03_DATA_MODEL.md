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
