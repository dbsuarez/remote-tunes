import 'dart:convert';
import '../../core/theme/skin.dart';
import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/song_list_style.dart';
import '../../core/models/enums.dart';
import '../../core/online_defaults.dart';
import '../database/app_database.dart';

/// Keys from docs/03_DATA_MODEL.md.
class SettingKeys {
  SettingKeys._();

  static const deviceName = 'device_name';
  static const defaultVolume = 'default_volume';
  static const repeatMode = 'repeat_mode';
  static const shuffleEnabled = 'shuffle_enabled';
  static const externalAppControlEnabled = 'external_app_control_enabled';
  static const lastPlayerPort = 'last_player_port';
  static const connectionMode = 'connection_mode';
  static const onlineRelayEnabled = 'online_relay_enabled';
  static const supabaseUrl = 'supabase_url';
  static const supabaseAnonKey = 'supabase_anon_key';
  static const playerRoomCode = 'player_room_code';
  static const songListSize = 'song_list_size';
  static const hapticsEnabled = 'haptics_enabled';
  static const accentFromArt = 'accent_from_art';
  static const autoUpdateCheck = 'auto_update_check';
  static const lyricsEnabled = 'lyrics_enabled';
  static const pendingUpdate = 'pending_update';
  static const startMode = 'start_mode';
  static const replayGainMode = 'replay_gain_mode';
  static const crossfadeSeconds = 'crossfade_seconds';
  static const skinId = 'skin_id';
  static const queueScrollToCurrent = 'queue_scroll_to_current';
  static const visualizer = 'visualizer';
  static const visualizerStyle = 'visualizer_style';
  static const visualizerOnCover = 'visualizer_on_cover';
  static const onlineSuggestions = 'online_suggestions';
  static const customSkins = 'custom_skins';
  static const remoteAutoStart = 'remote_auto_start';
  static const searchHistory = 'search_history';
  static const lastUpdateCheck = 'last_update_check';
}

List<Skin> _decodeSkins(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return const [];
    final out = <Skin>[];
    for (final e in v) {
      if (e is! String) continue;
      try {
        out.add(Skin.parse(e));
      } on SkinException {
        // A damaged one is skipped.
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

List<String> _decodeList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final v = jsonDecode(raw);
    return v is List ? [for (final e in v) if (e is String) e] : const [];
  } catch (_) {
    return const [];
  }
}

/// Immutable snapshot of all settings, with defaults for missing keys.
class AppSettings {
  const AppSettings({
    this.deviceName = AppConstants.defaultDeviceName,
    this.connectionMode = ConnectionMode.auto,
    this.onlineRelayEnabled = false,
    this.supabaseUrl,
    this.supabaseAnonKey,
    this.defaultVolume = AppConstants.defaultVolume,
    this.repeatMode = RepeatMode.off,
    this.shuffleEnabled = false,
    this.externalAppControlEnabled = false,
    this.lastPlayerPort = AppConstants.defaultPlayerPort,
    this.songListSize = SongListSize.small,
    this.hapticsEnabled = true,
    this.accentFromArt = true,
    this.autoUpdateCheck = true,
    this.lyricsEnabled = true,
    this.pendingUpdate = false,
    this.startMode = StartMode.thisPhone,
    this.replayGainMode = ReplayGainMode.off,
    this.crossfadeSeconds = 0,
    this.skinId = Skin.defaultId,
    this.queueScrollToCurrent = true,
    this.visualizerEnabled = false,
    this.visualizerStyle = 'bars',
    this.visualizerOnCover = false,
    this.onlineSuggestions = true,
    this.customSkins = const [],
    this.remoteAutoStart = false,
    this.searchHistory = const [],
    this.lastUpdateCheck = 0,
  });

  final String deviceName;
  final ConnectionMode connectionMode;
  final bool onlineRelayEnabled;
  final String? supabaseUrl;
  final String? supabaseAnonKey;

  /// 0.0–1.0 (displayed as 0–100% in the UI).
  final double defaultVolume;
  final RepeatMode repeatMode;
  final bool shuffleEnabled;
  final bool externalAppControlEnabled;
  final int lastPlayerPort;
  final SongListSize songListSize;

  /// A short vibration on taps (play, skip, picking things).
  final bool hapticsEnabled;

  /// Tint the Controller with a color from the album art.
  final bool accentFromArt;

  /// Look for a newer version on GitHub now and then (about once a day).
  final bool autoUpdateCheck;

  /// Look up lyrics on the internet (sends the song's title and artist to
  /// LRCLIB / lyrics.ovh). Lives on the Player.
  final bool lyricsEnabled;

  /// An update install was started and is waiting for Android's "allow
  /// installs" switch.
  final bool pendingUpdate;

  /// What the app shows when it opens.
  final StartMode startMode;

  /// Lower loud songs to the level in their Replay Gain tags (it can only turn
  /// songs down, never up).
  final ReplayGainMode replayGainMode;

  /// Seconds one song fades into the next (0: off, up to 12).
  final int crossfadeSeconds;

  /// The skin in use (a built-in one or one that was added).
  final String skinId;

  /// Going to the Queue scrolls to the song that is playing (on unless switched
  /// off).
  final bool queueScrollToCurrent;

  /// Moving bars under the cover while music plays.
  final bool visualizerEnabled;

  /// How the visualizer is drawn (a `VisualizerStyle` name).
  final String visualizerStyle;

  /// The visualizer is drawn over the (dimmed) cover instead of under it; the lyrics and the
  /// visualizer then never show together.
  final bool visualizerOnCover;

  /// Popular and newest tracks on the Online Library home screen.
  final bool onlineSuggestions;

  /// Skins added by pasting their JSON.
  final List<Skin> customSkins;

  /// The look to draw the app with.
  Skin get skin => Skin.byId(skinId, customSkins);

  /// Start remote playback (let other phones control this one) when the app
  /// opens.
  final bool remoteAutoStart;

  /// What was searched for lately, newest first (kept on this phone).
  final List<String> searchHistory;

  /// When that was last done (milliseconds since 1970; 0 = never).
  final int lastUpdateCheck;

  factory AppSettings.fromMap(Map<String, String> m) {
    final name = m[SettingKeys.deviceName]?.trim();
    return AppSettings(
      deviceName: (name == null || name.isEmpty)
          ? AppConstants.defaultDeviceName
          : name,
      connectionMode: ConnectionModeX.parse(m[SettingKeys.connectionMode]),
      onlineRelayEnabled: m[SettingKeys.onlineRelayEnabled] == 'true',
      // What the user entered wins; otherwise this build's own project.
      supabaseUrl: _orDefault(m[SettingKeys.supabaseUrl], OnlineDefaults.supabaseUrl),
      supabaseAnonKey:
          _orDefault(m[SettingKeys.supabaseAnonKey], OnlineDefaults.supabaseAnonKey),
      defaultVolume: (double.tryParse(m[SettingKeys.defaultVolume] ?? '') ??
              AppConstants.defaultVolume)
          .clamp(0.0, 1.0),
      repeatMode: RepeatModeX.parse(m[SettingKeys.repeatMode]),
      shuffleEnabled: m[SettingKeys.shuffleEnabled] == 'true',
      externalAppControlEnabled:
          m[SettingKeys.externalAppControlEnabled] == 'true',
      lastPlayerPort: int.tryParse(m[SettingKeys.lastPlayerPort] ?? '') ??
          AppConstants.defaultPlayerPort,
      songListSize: SongListSize.parse(m[SettingKeys.songListSize]),
      // On unless switched off.
      hapticsEnabled: m[SettingKeys.hapticsEnabled] != 'false',
      accentFromArt: m[SettingKeys.accentFromArt] != 'false',
      autoUpdateCheck: m[SettingKeys.autoUpdateCheck] != 'false',
      lyricsEnabled: m[SettingKeys.lyricsEnabled] != 'false',
      pendingUpdate: m[SettingKeys.pendingUpdate] == 'true',
      startMode: StartModeX.parse(m[SettingKeys.startMode]),
      replayGainMode: ReplayGainModeX.parse(m[SettingKeys.replayGainMode]),
      crossfadeSeconds: (int.tryParse(m[SettingKeys.crossfadeSeconds] ?? '') ?? 0).clamp(0, 12),
      skinId: m[SettingKeys.skinId] ?? Skin.defaultId,
      queueScrollToCurrent: m[SettingKeys.queueScrollToCurrent] != 'false',
      visualizerEnabled: m[SettingKeys.visualizer] == 'true',
      visualizerStyle: m[SettingKeys.visualizerStyle] ?? 'bars',
      visualizerOnCover: m[SettingKeys.visualizerOnCover] == 'true',
      onlineSuggestions: m[SettingKeys.onlineSuggestions] != 'false',
      customSkins: _decodeSkins(m[SettingKeys.customSkins]),
      remoteAutoStart: m[SettingKeys.remoteAutoStart] == 'true',
      searchHistory: _decodeList(m[SettingKeys.searchHistory]),
      lastUpdateCheck: int.tryParse(m[SettingKeys.lastUpdateCheck] ?? '') ?? 0,
    );
  }
}

String? _orDefault(String? stored, String fallback) {
  final v = stored?.trim();
  if (v != null && v.isNotEmpty) return v;
  return fallback.isEmpty ? null : fallback;
}

/// Drift is the single source of truth for settings.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<AppSettings> watch() => _db.select(_db.settings).watch().map(
        (rows) => AppSettings.fromMap({for (final r in rows) r.key: r.value}),
      );

  Future<AppSettings> load() async {
    final rows = await _db.select(_db.settings).get();
    return AppSettings.fromMap({for (final r in rows) r.key: r.value});
  }

  Future<void> _put(String key, String value) {
    return _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _remove(String key) =>
      (_db.delete(_db.settings)..where((t) => t.key.equals(key))).go();

  /// The Player's online room code, kept between runs so trusted Controllers
  /// can find it again. Null until the first online Player session.
  Future<String?> loadPlayerRoomCode() async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(SettingKeys.playerRoomCode)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> savePlayerRoomCode(String code) =>
      _put(SettingKeys.playerRoomCode, code);

  /// A new room code is made at the next Player start.
  Future<void> clearPlayerRoomCode() => _remove(SettingKeys.playerRoomCode);

  Future<void> setDeviceName(String v) {
    final name = v.trim();
    if (name.isEmpty) return Future.value();
    return _put(SettingKeys.deviceName, name);
  }

  Future<void> setConnectionMode(ConnectionMode v) =>
      _put(SettingKeys.connectionMode, v.name);

  Future<void> setOnlineRelayEnabled(bool v) =>
      _put(SettingKeys.onlineRelayEnabled, v.toString());

  /// Stored only when the user enters a value; blank removes it.
  Future<void> setSupabaseUrl(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? _remove(SettingKeys.supabaseUrl) : _put(SettingKeys.supabaseUrl, t);
  }

  /// Stored only when the user enters a value; blank removes it.
  Future<void> setSupabaseAnonKey(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty
        ? _remove(SettingKeys.supabaseAnonKey)
        : _put(SettingKeys.supabaseAnonKey, t);
  }

  Future<void> setDefaultVolume(double v) =>
      _put(SettingKeys.defaultVolume, v.clamp(0.0, 1.0).toString());

  Future<void> setRepeatMode(RepeatMode v) =>
      _put(SettingKeys.repeatMode, v.name);

  Future<void> setShuffleEnabled(bool v) =>
      _put(SettingKeys.shuffleEnabled, v.toString());

  Future<void> setExternalAppControlEnabled(bool v) =>
      _put(SettingKeys.externalAppControlEnabled, v.toString());

  Future<void> setHapticsEnabled(bool v) =>
      _put(SettingKeys.hapticsEnabled, v.toString());

  Future<void> setSearchHistory(List<String> items) =>
      _put(SettingKeys.searchHistory, jsonEncode(items));

  Future<void> setOnlineSuggestions(bool v) => _put(SettingKeys.onlineSuggestions, v.toString());

  Future<void> setVisualizerStyle(String v) => _put(SettingKeys.visualizerStyle, v);

  Future<void> setVisualizerOnCover(bool v) => _put(SettingKeys.visualizerOnCover, v.toString());

  Future<void> setVisualizerEnabled(bool v) => _put(SettingKeys.visualizer, v.toString());

  Future<void> setQueueScrollToCurrent(bool v) =>
      _put(SettingKeys.queueScrollToCurrent, v.toString());

  Future<void> setSkinId(String id) => _put(SettingKeys.skinId, id);

  Future<void> setCustomSkins(List<Skin> skins) => _put(
      SettingKeys.customSkins, jsonEncode([for (final s in skins) s.toJson()]));

  Future<void> setCrossfadeSeconds(int v) =>
      _put(SettingKeys.crossfadeSeconds, v.clamp(0, 12).toString());

  Future<void> setReplayGainMode(ReplayGainMode v) =>
      _put(SettingKeys.replayGainMode, v.name);

  Future<void> setStartMode(StartMode v) => _put(SettingKeys.startMode, v.name);

  Future<void> setRemoteAutoStart(bool v) =>
      _put(SettingKeys.remoteAutoStart, v.toString());

  /// A saved text value by key (for things like the equalizer settings).
  Future<String?> readValue(String key) async {
    final row = await (_db.select(_db.settings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeValue(String key, String value) => _put(key, value);

  Future<void> removeValue(String key) => _remove(key);

  Future<void> setPendingUpdate(bool v) =>
      _put(SettingKeys.pendingUpdate, v.toString());

  Future<void> setLyricsEnabled(bool v) =>
      _put(SettingKeys.lyricsEnabled, v.toString());

  Future<void> setAutoUpdateCheck(bool v) =>
      _put(SettingKeys.autoUpdateCheck, v.toString());

  Future<void> setLastUpdateCheck(int ms) =>
      _put(SettingKeys.lastUpdateCheck, ms.toString());

  Future<void> setAccentFromArt(bool v) =>
      _put(SettingKeys.accentFromArt, v.toString());

  Future<void> setSongListSize(SongListSize v) =>
      _put(SettingKeys.songListSize, v.name);

  Future<void> setLastPlayerPort(int v) =>
      _put(SettingKeys.lastPlayerPort, v.toString());

  /// Most recently seen paired controllers (empty until pairing exists, Phase 1).
  Stream<List<PairedController>> watchConnectionHistory({int limit = 10}) {
    final q = _db.select(_db.pairedControllers)
      ..orderBy([(t) => OrderingTerm.desc(t.lastSeenAt)])
      ..limit(limit);
    return q.watch();
  }
}
