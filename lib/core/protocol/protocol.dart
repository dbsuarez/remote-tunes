import 'dart:convert';

import '../models/enums.dart';

/// Wire protocol shared by the local WebSocket transport (and, in Phase 4,
/// the Supabase relay). See docs/04_NETWORK_PROTOCOL.md.
///
/// Phase 1 notes / extensions (all backward compatible, unknown fields are
/// ignored by the spec):
///  * The envelope has an optional top-level `token` (the session token).
///  * `pairing_result.payload.status` is one of: pending, waiting_for_player,
///    accepted, rejected, expired, too_many_attempts.
///  * `hello` may carry `sessionId` + `token` to resume a session; the reply
///    sets `payload.resumed`.
///  * A Controller that disconnects on purpose closes the socket with code
///    [CloseCodes.controllerDisconnected] so the Player can revoke the session.

class MessageType {
  MessageType._();

  static const hello = 'hello';
  static const pairingRequest = 'pairing_request';
  static const pairingCode = 'pairing_code';
  static const pairingResult = 'pairing_result';
  static const command = 'command';
  static const commandResult = 'command_result';
  static const state = 'state';
  static const libraryRequest = 'library_request';
  static const libraryResponse = 'library_response';
  static const error = 'error';
  static const ping = 'ping';
  static const pong = 'pong';

  /// A Controller telling the Player it disconnected on purpose, so the Player
  /// revokes the session. Needed on the online relay, which has no socket close
  /// code. (Local sockets still use [CloseCodes.controllerDisconnected].)
  static const bye = 'bye';

  // Group play (docs/16): a second phone plays the same song in sync.
  //  syncPing {t0}            Controller -> Player
  //  syncPong {t0, t1, t2}    Player -> Controller (its monotonic clock at
  //                           receiving the ping and at replying)
  //  groupSync {...}          Player -> Controller, once a second while the
  //                           Controller has joined: what is playing, where, and
  //                           the Player's clock at that instant
  static const syncPing = 'sync_ping';
  static const syncPong = 'sync_pong';
  static const groupSync = 'group_sync';
}

class RemoteActions {
  RemoteActions._();

  static const play = 'play';
  static const pause = 'pause';
  static const toggle = 'toggle';
  static const next = 'next';
  static const previous = 'previous';
  static const stop = 'stop';
  static const seek = 'seek';
  static const setVolume = 'setVolume';

  // Phase 2 (queue and library). `playQueueItem` is an addition to the
  // documented list: FR-50 needs a way to jump to a queue entry.
  static const playSong = 'playSong';
  static const queueSong = 'queueSong';
  static const getQueue = 'getQueue';
  static const removeQueueItem = 'removeQueueItem';
  static const moveQueueItem = 'moveQueueItem';
  static const clearQueue = 'clearQueue';
  static const playQueueItem = 'playQueueItem';
  static const setRepeatMode = 'setRepeatMode';
  static const setShuffle = 'setShuffle';

  // Phase 3 (internet audio).
  static const playUrl = 'playUrl';

  // Phase 5 (External App Control): `{"action":"setControlMode","mode":"local"|"external"}`.
  static const setControlMode = 'setControlMode';

  // Phase 7 (Polish): `{"action":"setSleepTimer","minutes":30}`; 0 cancels. The
  // Player pauses when it runs out, and reports the time left in
  // `state.sleepTimerSeconds`.
  static const setSleepTimer = 'setSleepTimer';

  // Phase 7 (Polish), all `command` actions:
  //  setFavorite {songId, favorite}; createPlaylist {name} -> {playlistId};
  //  renamePlaylist {playlistId, name}; deletePlaylist {playlistId};
  //  addToPlaylist {playlistId, songIds}; removeFromPlaylist {playlistId, songId};
  //  setSpeed {speed 0.5-2.0}; getArt {songId} -> {art: base64 JPEG thumbnail}.
  static const setFavorite = 'setFavorite';
  static const createPlaylist = 'createPlaylist';
  static const renamePlaylist = 'renamePlaylist';
  static const deletePlaylist = 'deletePlaylist';
  static const addToPlaylist = 'addToPlaylist';
  static const removeFromPlaylist = 'removeFromPlaylist';
  static const setSpeed = 'setSpeed';
  static const getArt = 'getArt';

  // `{"action":"saveQueueAsPlaylist","name":"..."}` -> {playlistId, added, skipped}
  static const saveQueueAsPlaylist = 'saveQueueAsPlaylist';

  // Group play: `{"action":"groupJoin","enabled":true}` starts (or stops) the
  // Player sending `group_sync` messages to this Controller.
  static const groupJoin = 'groupJoin';

  // Online Library history (kept on the Player):
  //  playHistory {historyId, queue?}; removeHistory {historyId};
  //  clearHistory {}; setHistoryEnabled {enabled}.
  static const playHistory = 'playHistory';
  static const removeHistory = 'removeHistory';
  static const clearHistory = 'clearHistory';
  static const setHistoryEnabled = 'setHistoryEnabled';
}

class ErrorCodes {
  ErrorCodes._();

  static const invalidMessage = 'INVALID_MESSAGE';
  static const unsupportedProtocol = 'UNSUPPORTED_PROTOCOL';
  static const notPaired = 'NOT_PAIRED';
  static const invalidSession = 'INVALID_SESSION';
  static const sessionReplaced = 'SESSION_REPLACED';
  static const invalidAction = 'INVALID_ACTION';
  static const invalidCode = 'INVALID_CODE';
  static const invalidPosition = 'INVALID_POSITION';
  static const permissionDenied = 'PERMISSION_DENIED';
  static const invalidUrl = 'INVALID_URL';
  static const urlUnreachable = 'URL_UNREACHABLE';
  static const fileNotFound = 'FILE_NOT_FOUND';
  static const unsupportedFormat = 'UNSUPPORTED_FORMAT';
  static const queueEmpty = 'QUEUE_EMPTY';
  static const playbackFailed = 'PLAYBACK_FAILED';
  static const internalError = 'INTERNAL_ERROR';
}

class PairingStatus {
  PairingStatus._();

  static const pending = 'pending';
  static const waitingForPlayer = 'waiting_for_player';
  static const accepted = 'accepted';
  static const rejected = 'rejected';
  static const expired = 'expired';
  static const tooManyAttempts = 'too_many_attempts';
}

/// WebSocket close codes (application range 4000-4999).
class CloseCodes {
  CloseCodes._();

  /// The Controller user chose to disconnect: the Player revokes the session.
  static const controllerDisconnected = 4000;

  /// The Player user disconnected the Controller.
  static const playerDisconnected = 4001;

  /// A newer Controller replaced this one.
  static const sessionReplaced = 4002;

  /// No traffic for too long.
  static const timeout = 4003;

  /// The same session resumed on a newer connection.
  static const resumedElsewhere = 4004;

  static const unsupportedProtocol = 4005;

  /// The link was dropped without the user asking (network loss, etc.).
  /// Note: dart:io only allows 1000 or 3000–4999 for application closes.
  static const connectionLost = 4006;
}

class ProtocolException implements Exception {
  ProtocolException(this.message);
  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}

class RemoteMessage {
  const RemoteMessage({
    required this.type,
    this.sessionId = '',
    this.requestId = '',
    this.token,
    this.payload = const {},
  });

  final String type;
  final String sessionId;
  final String requestId;
  final String? token;
  final Map<String, dynamic> payload;

  factory RemoteMessage.error(
    String code,
    String message, {
    String requestId = '',
    String sessionId = '',
  }) =>
      RemoteMessage(
        type: MessageType.error,
        requestId: requestId,
        sessionId: sessionId,
        payload: {'code': code, 'message': message},
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'sessionId': sessionId,
        'requestId': requestId,
        if (token != null) 'token': token,
        'payload': payload,
      };

  String encode() => jsonEncode(toJson());

  /// Decodes a text frame. Unknown fields are ignored.
  factory RemoteMessage.decode(Object? raw) {
    if (raw is! String) {
      throw ProtocolException('Messages must be text.');
    }
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw ProtocolException('Message is not valid JSON.');
    }
    if (json is! Map<String, dynamic>) {
      throw ProtocolException('Message must be a JSON object.');
    }
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw ProtocolException('Message has no type.');
    }
    final payload = json['payload'];
    final token = json['token'];
    return RemoteMessage(
      type: type,
      sessionId: json['sessionId'] is String ? json['sessionId'] as String : '',
      requestId: json['requestId'] is String ? json['requestId'] as String : '',
      token: token is String && token.isNotEmpty ? token : null,
      payload: payload is Map ? Map<String, dynamic>.from(payload) : const {},
    );
  }

  /// Error code/message helpers for `error` messages.
  String get errorCode => payload['code'] is String
      ? payload['code'] as String
      : ErrorCodes.internalError;
  String get errorMessage =>
      payload['message'] is String ? payload['message'] as String : '';
}

/// Playback state sent from Player to Controller (docs/04, "State").
class PlaybackState {
  const PlaybackState({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.isPlaying = false,
    this.queueIndex = 0,
    this.queueLength = 0,
    this.volume = 0.8,
    this.repeatMode = RepeatMode.off,
    this.shuffleEnabled = false,
    this.source = 'none',
    this.songId,
    this.queueRevision = 0,
    this.isLoading = false,
    this.error = '',
    this.externalApp = '',
    this.externalEnabled = false,
    this.canSeek = true,
    this.canSkip = true,
    this.localArtPath,
    this.sleepTimerSeconds = 0,
    this.speed = 1.0,
    this.favorite = false,
  });

  /// Playback speed (1.0 = normal).
  final double speed;

  /// The current library song is a favorite.
  final bool favorite;

  /// Seconds until the Player's sleep timer pauses playback; 0 when off.
  final int sleepTimerSeconds;

  final String title;
  final String artist;
  final String album;
  final int positionSeconds;
  final int durationSeconds;
  final bool isPlaying;
  final int queueIndex;
  final int queueLength;

  /// 0.0–1.0
  final double volume;
  final RepeatMode repeatMode;
  final bool shuffleEnabled;
  final String source;

  /// Library id of the current song, if any.
  final int? songId;

  /// Bumps whenever the queue changes so Controllers know to refetch it.
  final int queueRevision;

  /// True while the Player is opening a track (e.g. buffering an internet
  /// stream).
  final bool isLoading;

  /// Plain-language playback problem (e.g. an internet stream that dropped),
  /// or empty when everything is fine.
  final String error;

  bool get isInternetStream => source == 'url';

  /// The Player is controlling another music app (Spotify, YouTube Music, …),
  /// not RemoteTunes' own player.
  bool get isExternal => source == 'external';

  /// Name of the other app being controlled (e.g. "Spotify"); empty if none is
  /// playing yet.
  final String externalApp;

  /// The Player has External App Control turned on, so a Controller may switch
  /// to it.
  final bool externalEnabled;

  /// In external mode, whether that app allows seeking / skipping tracks.
  /// (Always true for RemoteTunes' own player.)
  final bool canSeek;
  final bool canSkip;

  /// Path of the current album art on the Player. **Local only: never
  /// serialized or sent to a Controller** (FR-46, files stay on the Player).
  final String? localArtPath;

  bool get hasTrack => title.isNotEmpty;

  PlaybackState copyWith({
    String? title,
    String? artist,
    String? album,
    int? positionSeconds,
    int? durationSeconds,
    bool? isPlaying,
    int? queueIndex,
    int? queueLength,
    double? volume,
    RepeatMode? repeatMode,
    bool? shuffleEnabled,
    String? source,
    int? songId,
    int? queueRevision,
    bool? isLoading,
    String? error,
    String? externalApp,
    bool? externalEnabled,
    bool? canSeek,
    bool? canSkip,
    String? localArtPath,
    int? sleepTimerSeconds,
    double? speed,
    bool? favorite,
  }) =>
      PlaybackState(
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        positionSeconds: positionSeconds ?? this.positionSeconds,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        isPlaying: isPlaying ?? this.isPlaying,
        queueIndex: queueIndex ?? this.queueIndex,
        queueLength: queueLength ?? this.queueLength,
        volume: volume ?? this.volume,
        repeatMode: repeatMode ?? this.repeatMode,
        shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
        source: source ?? this.source,
        songId: songId ?? this.songId,
        queueRevision: queueRevision ?? this.queueRevision,
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        externalApp: externalApp ?? this.externalApp,
        externalEnabled: externalEnabled ?? this.externalEnabled,
        canSeek: canSeek ?? this.canSeek,
        canSkip: canSkip ?? this.canSkip,
        localArtPath: localArtPath ?? this.localArtPath,
        sleepTimerSeconds: sleepTimerSeconds ?? this.sleepTimerSeconds,
        speed: speed ?? this.speed,
        favorite: favorite ?? this.favorite,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'isPlaying': isPlaying,
        'queueIndex': queueIndex,
        'queueLength': queueLength,
        'volume': volume,
        'repeatMode': repeatMode.name,
        'shuffleEnabled': shuffleEnabled,
        'source': source,
        if (songId != null) 'songId': songId,
        'queueRevision': queueRevision,
        if (isLoading) 'isLoading': true,
        if (error.isNotEmpty) 'error': error,
        // Phase 5: only sent when they differ from the defaults.
        if (externalApp.isNotEmpty) 'externalApp': externalApp,
        if (externalEnabled) 'externalEnabled': true,
        if (!canSeek) 'canSeek': false,
        if (!canSkip) 'canSkip': false,
        if (sleepTimerSeconds > 0) 'sleepTimerSeconds': sleepTimerSeconds,
        if (speed != 1.0) 'speed': speed,
        if (favorite) 'favorite': true,
        // localArtPath is intentionally NOT included.
      };

  /// Tolerant parser: missing or wrongly-typed fields fall back to defaults.
  factory PlaybackState.fromJson(Map<String, dynamic> j) {
    int i(String k) => j[k] is num ? (j[k] as num).toInt() : 0;
    return PlaybackState(
      title: j['title'] is String ? j['title'] as String : '',
      artist: j['artist'] is String ? j['artist'] as String : '',
      album: j['album'] is String ? j['album'] as String : '',
      positionSeconds: i('positionSeconds'),
      durationSeconds: i('durationSeconds'),
      isPlaying: j['isPlaying'] == true,
      queueIndex: i('queueIndex'),
      queueLength: i('queueLength'),
      volume: j['volume'] is num
          ? (j['volume'] as num).toDouble().clamp(0.0, 1.0)
          : 0.8,
      repeatMode: RepeatModeX.parse(
          j['repeatMode'] is String ? j['repeatMode'] as String : null),
      shuffleEnabled: j['shuffleEnabled'] == true,
      source: j['source'] is String ? j['source'] as String : 'none',
      songId: j['songId'] is num ? (j['songId'] as num).toInt() : null,
      queueRevision: i('queueRevision'),
      isLoading: j['isLoading'] == true,
      error: j['error'] is String ? j['error'] as String : '',
      externalApp: j['externalApp'] is String ? j['externalApp'] as String : '',
      externalEnabled: j['externalEnabled'] == true,
      canSeek: j['canSeek'] != false,
      canSkip: j['canSkip'] != false,
      sleepTimerSeconds: i('sleepTimerSeconds'),
      speed: j['speed'] is num
          ? (j['speed'] as num).toDouble().clamp(0.5, 2.0)
          : 1.0,
      favorite: j['favorite'] == true,
    );
  }
}
