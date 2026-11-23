// Enums from docs/03_DATA_MODEL.md. Persisted by their `name`.

enum SongSource { localFile, url }

enum RepeatMode { off, one, queue }

enum ConnectionMode { auto, localOnly, onlineOnly }

enum ConnectionType { local, online }

/// What the Player is controlling: RemoteTunes' own player, or another music
/// app on the Player phone (Spotify, YouTube Music, ...). Phase 5.
enum ControlMode { local, external }

extension ConnectionModeX on ConnectionMode {
  String get label => switch (this) {
        ConnectionMode.auto => 'Auto',
        ConnectionMode.localOnly => 'Local only',
        ConnectionMode.onlineOnly => 'Online only',
      };

  String get description => switch (this) {
        ConnectionMode.auto => 'Prefer local Wi‑Fi or hotspot, fall back to online.',
        ConnectionMode.localOnly => 'Same Wi‑Fi or hotspot. No internet needed.',
        ConnectionMode.onlineOnly => 'Over the internet via relay. Internet required.',
      };

  static ConnectionMode parse(String? v) => ConnectionMode.values
      .firstWhere((e) => e.name == v, orElse: () => ConnectionMode.auto);
}

extension RepeatModeX on RepeatMode {
  String get label => switch (this) {
        RepeatMode.off => 'Off',
        RepeatMode.one => 'One',
        RepeatMode.queue => 'Queue',
      };

  static RepeatMode parse(String? v) => RepeatMode.values
      .firstWhere((e) => e.name == v, orElse: () => RepeatMode.off);
}
