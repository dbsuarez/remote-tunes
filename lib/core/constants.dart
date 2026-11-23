/// App-wide constants for RemoteTunes.
class AppConstants {
  AppConstants._();

  static const String appName = 'RemoteTunes';

  /// Default port the Player's local WebSocket server will use (Phase 1).
  static const int defaultPlayerPort = 8765;

  /// Network protocol version, checked in `hello` (Phase 1).
  static const int protocolVersion = 1;

  /// mDNS/NSD service type the Player advertises and the Controller browses.
  static const String serviceType = '_remotetunes._tcp';

  /// A connection with no traffic for this long is considered lost.
  static const Duration connectionTimeout = Duration(seconds: 15);

  /// Controller sends a ping this often.
  static const Duration heartbeatInterval = Duration(seconds: 5);

  /// Pairing codes expire after 5 minutes (docs/03_DATA_MODEL.md).
  static const Duration pairingCodeTtl = Duration(minutes: 5);

  /// A known-good direct MP3 link (128 kbps stereo, 60 s) that pre-fills the URL
  /// screens, so internet playback can be tried without hunting for a link.
  /// Checked: HTTP 200, audio/mpeg, supports seeking. Note the `/downloads/`
  /// part: the address without it is a 404 web page.
  static const String sampleAudioUrl =
      'https://sample-files.com/downloads/audio/mp3/music-sample-128kbps.mp3';

  /// Database file name (see docs/03_DATA_MODEL.md).
  static const String databaseFileName = 'remote_tunes.db';

  static const String defaultDeviceName = 'My Phone';
  static const double defaultVolume = 0.8;

  /// Minimum recommended tap target (docs/01_REQUIREMENTS.md: 48dp).
  static const double minTapTarget = 48;
}
