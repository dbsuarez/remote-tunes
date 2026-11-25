// Enums from docs/03_DATA_MODEL.md. Persisted by their `name`.

enum SongSource { localFile, url }

enum RepeatMode { off, one, queue }

enum ConnectionMode { auto, localOnly, onlineOnly }

enum ConnectionType { local, online }

/// Evening out loudness between songs from the Replay Gain tags in the files.
enum ReplayGainMode { off, track, album }

/// What the app shows when it opens.
enum StartMode {
  /// A music player for this phone's own music (the default).
  thisPhone,

  /// The same, and it reconnects to the last Player and controls it.
  lastPlayer,
}

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

extension ReplayGainModeX on ReplayGainMode {
  String get label => switch (this) {
        ReplayGainMode.off => 'Off',
        ReplayGainMode.track => 'By song',
        ReplayGainMode.album => 'By album',
      };

  static ReplayGainMode parse(String? v) =>
      ReplayGainMode.values.firstWhere((e) => e.name == v, orElse: () => ReplayGainMode.off);
}

extension StartModeX on StartMode {
  String get label => switch (this) {
        StartMode.thisPhone => 'This phone\'s music',
        StartMode.lastPlayer => 'Control my last Player',
      };

  String get description => switch (this) {
        StartMode.thisPhone => 'Opens as a music player for the songs on this phone.',
        StartMode.lastPlayer =>
          'Opens and reconnects to the Player you used last, so you control it straight away.',
      };

  static StartMode parse(String? v) =>
      StartMode.values.firstWhere((e) => e.name == v, orElse: () => StartMode.thisPhone);
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
