import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/mono_clock.dart';
import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../../core/transport/remote_transport.dart';
import 'trusted_players.dart';

enum ControllerStatus {
  disconnected,
  connecting,
  awaitingCode,
  waitingForPlayer,
  connected,
  reconnecting,
}

class ControllerClientState {
  const ControllerClientState({
    this.status = ControllerStatus.disconnected,
    this.playerName,
    this.host,
    this.port,
    this.roomCode,
    this.route,
    this.mode = ConnectionMode.auto,
    this.message,
    this.playback = const PlaybackState(),
    this.codeExpiresAt,
    this.sessionInvalid = false,
  });

  final ControllerStatus status;
  final String? playerName;
  final String? host;
  final int? port;

  /// Online room code, when one was given.
  final String? roomCode;

  /// How the Controller is (or was last) connected: local network or online.
  final ConnectionType? route;
  final ConnectionMode mode;

  /// Plain-language error or info for the UI.
  final String? message;
  final PlaybackState playback;
  final DateTime? codeExpiresAt;

  /// The connection ended because the Player no longer accepts this session
  /// (it restarted, replaced or disconnected this Controller). A saved session
  /// should then be forgotten. False for ordinary network failures, where a
  /// saved session may still resume later.
  final bool sessionInvalid;

  bool get isConnected => status == ControllerStatus.connected;
}

/// Thrown for failures the UI can show directly to the user.
class ControllerException implements Exception {
  ControllerException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

class _NeedsPairing implements Exception {}

/// Everything needed to rejoin a paired Player over the online relay after the
/// Controller restarts (e.g. the browser page is reloaded) without pairing
/// again. The token is a secret: store it only on this device.
class ControllerSession {
  const ControllerSession({
    required this.roomCode,
    required this.sessionId,
    required this.token,
    required this.peerId,
    this.playerName,
  });

  final String roomCode;
  final String sessionId;
  final String token;

  /// This Controller's address in the room; kept so the Player recognises it.
  final String peerId;
  final String? playerName;

  Map<String, dynamic> toJson() => {
        'roomCode': roomCode,
        'sessionId': sessionId,
        'token': token,
        'peerId': peerId,
        if (playerName != null) 'playerName': playerName,
      };

  /// Null if [raw] is not a usable saved session (corrupt or old storage).
  static ControllerSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String? s(String k) => raw[k] is String && (raw[k] as String).isNotEmpty
        ? raw[k] as String
        : null;
    final room = s('roomCode');
    final sid = s('sessionId');
    final token = s('token');
    final peer = s('peerId');
    if (room == null || sid == null || token == null || peer == null) return null;
    return ControllerSession(
      roomCode: room,
      sessionId: sid,
      token: token,
      peerId: peer,
      playerName: s('playerName'),
    );
  }
}

/// Creates the local WebSocket transport for a Player's address.
typedef TransportFactory = RemoteTransport Function(String host, int port);

/// Creates the online relay transport for a room. [peerId] stays the same for
/// the whole session so the Player recognises the Controller when it resumes.
typedef OnlineTransportFactory = RemoteTransport Function(
    String roomCode, String peerId);

/// The Controller side: connect (locally and/or online), pair, send commands,
/// track state, heartbeat, and automatic reconnect with the session token. In
/// Auto mode it prefers the local network and falls back to the online relay.
class ControllerClient {
  ControllerClient({
    TransportFactory? transportFactory,
    OnlineTransportFactory? onlineTransportFactory,
    MonoClock? clock,
    this.heartbeatInterval = AppConstants.heartbeatInterval,
    this.connectionTimeout = AppConstants.connectionTimeout,
    this.commandTimeout = const Duration(seconds: 5),
    this.localHelloTimeout = const Duration(seconds: 5),
    this.onlineHelloTimeout = const Duration(seconds: 10),
    this.reconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 8),
      Duration(seconds: 8),
      Duration(seconds: 10),
      Duration(seconds: 10),
      Duration(seconds: 10),
    ],
  })  : _transportFactory = transportFactory,
        _onlineFactory = onlineTransportFactory,
        _clock = clock ?? MonoClock.instance;

  final MonoClock _clock;

  final TransportFactory? _transportFactory;
  final OnlineTransportFactory? _onlineFactory;
  final Duration heartbeatInterval;
  final Duration connectionTimeout;
  final Duration commandTimeout;

  /// How long to wait for the Player's reply to `hello` (the relay is slower
  /// than the local network).
  final Duration localHelloTimeout;
  final Duration onlineHelloTimeout;
  final List<Duration> reconnectDelays;

  static const _uuid = Uuid();

  final StreamController<ControllerClientState> _stateController =
      StreamController<ControllerClientState>.broadcast();
  ControllerClientState _state = const ControllerClientState();

  ControllerClientState get current => _state;
  Stream<ControllerClientState> get stateStream => _stateController.stream;

  RemoteTransport? _transport;
  StreamSubscription<RemoteMessage>? _sub;
  Timer? _heartbeat;
  DateTime _lastMessageAt = DateTime.now();

  String _deviceName = '';
  String? _sessionId;
  String? _token;

  // Where to reach the Player.
  String? _host;
  int? _port;
  String? _roomCode;
  String? _ticket; // from a scanned pairing QR, used once
  ConnectionMode _mode = ConnectionMode.auto;

  /// This Controller's address on the online relay, stable for the session.
  String _peerId = 'c-${const Uuid().v4().substring(0, 8)}';

  bool get _localUsable =>
      _mode != ConnectionMode.onlineOnly &&
      _host != null &&
      _port != null &&
      _transportFactory != null;

  bool get _onlineUsable =>
      _mode != ConnectionMode.localOnly &&
      _roomCode != null &&
      _onlineFactory != null;

  /// Routes to try, best first: local network, then online.
  List<ConnectionType> get _routes => [
        if (_localUsable) ConnectionType.local,
        if (_onlineUsable) ConnectionType.online,
      ];

  /// Bumped whenever the whole session is started or ended; stops stale loops.
  int _epoch = 0;

  /// Bumped for every transport so callbacks from old sockets are ignored.
  int _generation = 0;
  bool _reconnecting = false;
  bool _disposed = false;

  final Map<String, Completer<RemoteMessage>> _waiters = {};

  void _emit(ControllerClientState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void _update({
    ControllerStatus? status,
    String? playerName,
    String? message,
    bool clearMessage = false,
    PlaybackState? playback,
    DateTime? codeExpiresAt,
    ConnectionType? route,
  }) {
    _emit(ControllerClientState(
      status: status ?? _state.status,
      playerName: playerName ?? _state.playerName,
      host: _state.host,
      port: _state.port,
      roomCode: _state.roomCode,
      route: route ?? _state.route,
      mode: _state.mode,
      message: clearMessage ? null : (message ?? _state.message),
      playback: playback ?? _state.playback,
      codeExpiresAt: codeExpiresAt ?? _state.codeExpiresAt,
    ));
  }

  // ------------------------------------------------------------------ connect

  /// The current paired session over the online relay, for saving so it can be
  /// resumed later with [resumeSession]. Null when not paired online.
  ControllerSession? get savedSession {
    final room = _roomCode;
    final sid = _sessionId;
    final token = _token;
    final online = _state.route == ConnectionType.online;
    final paired = _state.status == ControllerStatus.connected ||
        _state.status == ControllerStatus.reconnecting;
    if (room == null || sid == null || token == null || !online || !paired) {
      return null;
    }
    return ControllerSession(
      roomCode: room,
      sessionId: sid,
      token: token,
      peerId: _peerId,
      playerName: _state.playerName,
    );
  }

  /// The paired Player (on any route), for remembering it as trusted so this
  /// phone can reconnect later without pairing again. Null when not paired.
  TrustedPlayer? get trustedPlayer {
    final sid = _sessionId;
    final token = _token;
    final paired = _state.status == ControllerStatus.connected ||
        _state.status == ControllerStatus.reconnecting;
    if (sid == null || token == null || !paired) return null;
    final local = _host != null && _port != null;
    if (!local && _roomCode == null) return null;
    return TrustedPlayer(
      sessionId: sid,
      token: token,
      peerId: _peerId,
      name: _state.playerName ?? 'Player',
      host: local ? _host : null,
      port: local ? _port : null,
      roomCode: _roomCode,
      lastUsed: DateTime.now(),
    );
  }

  /// Reconnects to a trusted Player without pairing again. The local network
  /// is tried first, then the online room (per [mode]). [host]/[port]/[roomCode]
  /// override what was saved (e.g. a fresh address found by discovery). If the
  /// Player no longer trusts this phone, this ends disconnected with
  /// `sessionInvalid` set, and the caller should forget the saved Player.
  Future<void> resumeTrusted({
    required TrustedPlayer player,
    required String deviceName,
    ConnectionMode mode = ConnectionMode.auto,
    String? host,
    int? port,
    String? roomCode,
  }) async {
    await _teardown();
    final epoch = ++_epoch;
    _deviceName = deviceName;
    _host = host ?? player.host;
    _port = host != null ? port : (port ?? player.port);
    _roomCode = roomCode ?? player.roomCode;
    _mode = mode;
    _sessionId = player.sessionId;
    _token = player.token;
    _peerId = player.peerId;
    _emit(ControllerClientState(
      status: ControllerStatus.connecting,
      host: _host,
      port: _port,
      roomCode: _roomCode,
      mode: mode,
      playerName: player.name,
    ));
    final routes = _routes;
    if (routes.isEmpty) {
      await _failSession("Couldn't find a way to reach ${player.name} with this "
          "phone's connection mode.");
      return;
    }
    String? last;
    for (final route in routes) {
      try {
        await _open(route, resume: true);
        if (epoch != _epoch) return;
        return; // connected
      } on _NeedsPairing {
        if (epoch != _epoch) return;
        await _failSession(
            '${player.name} no longer trusts this phone. Scan its QR code to connect again.',
            sessionInvalid: true);
        return;
      } on ControllerException catch (e) {
        if (epoch != _epoch) return;
        last = e.message;
      } on TransportException catch (e) {
        if (epoch != _epoch) return;
        last = e.message;
      }
    }
    if (epoch == _epoch) {
      await _failSession("Couldn't reach ${player.name}. Is it running RemoteTunes "
          'in Player mode? ${last ?? ''}'.trim());
    }
  }

  /// Rejoins a Player using a previously saved session, without pairing again.
  /// If the Player no longer knows the session (it restarted, or the room
  /// changed), this ends disconnected with a message, and the caller should
  /// forget the saved session.
  Future<void> resumeSession({
    required ControllerSession session,
    required String deviceName,
  }) async {
    await _teardown();
    final epoch = ++_epoch;
    _deviceName = deviceName;
    _host = null;
    _port = null;
    _roomCode = session.roomCode;
    _mode = ConnectionMode.onlineOnly;
    _sessionId = session.sessionId;
    _token = session.token;
    _peerId = session.peerId;
    _emit(ControllerClientState(
      status: ControllerStatus.connecting,
      roomCode: session.roomCode,
      mode: ConnectionMode.onlineOnly,
      playerName: session.playerName,
    ));
    try {
      await _open(ConnectionType.online, resume: true);
    } on _NeedsPairing {
      if (epoch != _epoch) return;
      await _failSession(
        'That saved connection is no longer valid. Enter the room code shown '
        'on the Player and pair again.',
        sessionInvalid: true,
      );
    } on ControllerException catch (e) {
      if (epoch != _epoch) return;
      await _failSession(e.message);
    } on TransportException catch (e) {
      if (epoch != _epoch) return;
      await _failSession(e.message);
    }
  }

  /// Connects to a Player and starts pairing. Errors are reported through
  /// [current] (status disconnected + message), not thrown.
  ///
  /// Give a local address ([host]/[port]), an online [roomCode], or both. In
  /// [ConnectionMode.auto] the local network is tried first and the online
  /// relay is the fallback; [ConnectionMode.localOnly] and
  /// [ConnectionMode.onlineOnly] use just one.
  Future<void> connect({
    String? host,
    int? port,
    String? roomCode,
    required String deviceName,
    ConnectionMode mode = ConnectionMode.auto,
    String? pairingTicket,
  }) async {
    await _teardown();
    _ticket = pairingTicket;
    final epoch = ++_epoch;
    _deviceName = deviceName;
    _sessionId = null;
    _token = null;
    _host = host;
    _port = port;
    _roomCode = roomCode;
    _mode = mode;
    _peerId = 'c-${_uuid.v4().substring(0, 8)}';

    _emit(ControllerClientState(
      status: ControllerStatus.connecting,
      host: host,
      port: port,
      roomCode: roomCode,
      mode: mode,
    ));

    final routes = _routes;
    if (routes.isEmpty) {
      await _failSession(switch (mode) {
        ConnectionMode.localOnly =>
          "Choose a nearby Player or enter its address. (This phone is set to 'Local only'.)",
        ConnectionMode.onlineOnly =>
          "Enter the room code shown on the Player. (This phone is set to 'Online only'.)",
        ConnectionMode.auto =>
          'Choose a nearby Player, enter its address, or enter a room code.',
      });
      return;
    }

    final errors = <String>[];
    ConnectionType? opened;
    for (final route in routes) {
      try {
        await _open(route, resume: false);
        if (epoch != _epoch) return;
        opened = route;
        break;
      } on ControllerException catch (e) {
        if (epoch != _epoch) return;
        errors.add(e.message);
      } on TransportException catch (e) {
        if (epoch != _epoch) return;
        errors.add(e.message);
      }
    }
    if (opened == null) {
      await _failSession(errors.length > 1
          ? "Couldn't reach the Player on the local network or online. ${errors.last}"
          : errors.single);
      return;
    }

    try {
      final reply = await _request(RemoteMessage(
        type: MessageType.pairingRequest,
        requestId: _uuid.v4(),
        payload: {'controllerName': deviceName, 'connectionType': opened.name},
      ));
      if (epoch != _epoch) return;
      if (_state.status == ControllerStatus.connecting) {
        _onPairingResult(reply.payload);
      }
    } on ControllerException catch (e) {
      if (epoch != _epoch) return;
      await _failSession(e.message);
    } on TransportException catch (e) {
      if (epoch != _epoch) return;
      await _failSession(e.message);
    }
  }

  RemoteTransport _transportFor(ConnectionType route) => route ==
          ConnectionType.local
      ? _transportFactory!(_host!, _port!)
      : _onlineFactory!(_roomCode!, _peerId);

  Future<void> _open(ConnectionType route, {required bool resume}) async {
    final gen = ++_generation;
    final transport = _transportFor(route);
    await transport.connect();
    _transport = transport;
    _lastMessageAt = DateTime.now();
    _sub = transport.messages.listen(
      (m) => _onMessage(gen, m),
      onDone: () => _onTransportDone(gen),
      onError: (_) => _onTransportDone(gen),
    );
    _startHeartbeat(gen);

    final RemoteMessage reply;
    try {
      reply = await _request(
        RemoteMessage(
          type: MessageType.hello,
          requestId: _uuid.v4(),
          sessionId: resume ? (_sessionId ?? '') : '',
          token: resume ? _token : null,
          payload: {
            'protocolVersion': AppConstants.protocolVersion,
            'role': 'controller',
            'deviceName': _deviceName,
          },
        ),
        // Over the relay a reply takes a little longer than on the LAN.
        timeout: route == ConnectionType.online
            ? onlineHelloTimeout
            : localHelloTimeout,
      );
    } catch (_) {
      await _closeTransport(intentional: false);
      rethrow;
    }

    final name = reply.payload['deviceName'];
    if (name is String && name.isNotEmpty) _update(playerName: name);
    _update(route: route);

    if (resume) {
      if (reply.payload['resumed'] != true) {
        await _closeTransport(intentional: false);
        throw _NeedsPairing();
      }
      _update(
        status: ControllerStatus.connected,
        clearMessage: true,
      );
    }
  }

  // ----------------------------------------------------------------- pairing

  /// Sends the 6-digit code shown on the Player.
  Future<void> submitCode(String code) async {
    if (_state.status != ControllerStatus.awaitingCode) {
      throw ControllerException('There is no pairing in progress.');
    }
    final reply = await _request(RemoteMessage(
      type: MessageType.pairingCode,
      requestId: _uuid.v4(),
      payload: {'code': code.trim()},
    ));
    _onPairingResult(reply.payload);
  }

  Future<void> _submitTicket(String ticket) async {
    final epoch = _epoch;
    try {
      await submitCode(ticket);
    } on ControllerException catch (e) {
      // Fall back to typing the code shown on the Player.
      if (epoch == _epoch) {
        _update(message: "The scanned code didn't work (${e.message}). "
            'Enter the 6-digit code shown on the Player instead.');
      }
    } on TransportException catch (e) {
      if (epoch == _epoch) _update(message: e.message);
    }
  }

  void _onPairingResult(Map<String, dynamic> p) {
    switch (p['status']) {
      case PairingStatus.pending:
        final secs = p['expiresInSeconds'];
        final ticket = _ticket;
        _ticket = null; // sent at most once
        _update(
          status: ControllerStatus.awaitingCode,
          clearMessage: true,
          codeExpiresAt: secs is num
              ? DateTime.now().add(Duration(seconds: secs.toInt()))
              : null,
        );
        // Scanned a QR code: send its ticket instead of asking for the code.
        if (ticket != null) unawaited(_submitTicket(ticket));
      case PairingStatus.waitingForPlayer:
        _update(status: ControllerStatus.waitingForPlayer, clearMessage: true);
      case PairingStatus.accepted:
        final sid = p['sessionId'];
        final token = p['token'];
        if (sid is! String || token is! String) return;
        _sessionId = sid;
        _token = token;
        final name = p['playerName'];
        _update(
          status: ControllerStatus.connected,
          clearMessage: true,
          playerName: name is String ? name : null,
        );
      case PairingStatus.rejected:
        unawaited(_failSession('The Player rejected the pairing request.'));
      case PairingStatus.expired:
        unawaited(_failSession('The pairing code expired. Please try again.'));
      case PairingStatus.tooManyAttempts:
        unawaited(_failSession('Too many wrong codes. Please try again.'));
    }
  }

  // ---------------------------------------------------------------- commands

  /// Sends a command and completes when the Player confirms it. The UI should
  /// update from the following `state` message, not assume success (FR-68).
  Future<void> sendCommand(
    String action, [
    Map<String, dynamic> params = const {},
  ]) async {
    await sendCommandForResult(action, params);
  }

  /// Like [sendCommand] but returns the `command_result` payload (some
  /// commands, e.g. `getQueue`, return data).
  Future<Map<String, dynamic>> sendCommandForResult(
    String action, [
    Map<String, dynamic> params = const {},
    Duration? timeout,
  ]) async {
    final reply = await _authenticatedRequest(
      MessageType.command,
      {'action': action, ...params},
      timeout: timeout,
    );
    return reply.payload;
  }

  /// Switches what the Player controls: its own player, or another music app
  /// on the Player phone (External App Control, needs to be on at the Player).
  /// Pauses the Player after [minutes]; 0 cancels the timer.
  Future<void> setSleepTimer(int minutes) =>
      sendCommand(RemoteActions.setSleepTimer, {'minutes': minutes});

  Future<void> setControlMode(ControlMode mode) =>
      sendCommand(RemoteActions.setControlMode, {'mode': mode.name});

  /// Sends an internet audio link to the Player. The Player checks the link
  /// and buffers the stream, which can take several seconds, so this waits
  /// longer than normal commands.
  ///
  /// With [queue] the link is added to the end of the queue instead of playing
  /// at once. [artist] and [album] are shown on the Player and in the queue.
  Future<void> playUrl(
    String url, {
    String? title,
    String? artist,
    String? album,
    String? licenseUrl,
    String? imageUrl,
    bool queue = false,
  }) async {
    String? clean(String? v) => v != null && v.trim().isNotEmpty ? v.trim() : null;
    await sendCommandForResult(
      RemoteActions.playUrl,
      {
        'url': url,
        if (clean(title) != null) 'title': clean(title),
        if (clean(artist) != null) 'artist': clean(artist),
        if (clean(album) != null) 'album': clean(album),
        if (clean(licenseUrl) != null) 'license': clean(licenseUrl),
        if (clean(imageUrl) != null) 'art': clean(imageUrl),
        if (queue) 'queue': true,
      },
      const Duration(seconds: 30),
    );
  }

  Future<RemoteMessage> _authenticatedRequest(
    String type,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) {
    final sid = _sessionId;
    final token = _token;
    if (!_state.isConnected || sid == null || token == null) {
      throw ControllerException('Not connected to a Player.');
    }
    return _request(RemoteMessage(
      type: type,
      sessionId: sid,
      token: token,
      requestId: _uuid.v4(),
      payload: payload,
    ), timeout: timeout);
  }

  // ---------------------------------------------------------------- group play

  final StreamController<RemoteMessage> _groupMessages =
      StreamController<RemoteMessage>.broadcast();

  /// The Player's `group_sync` messages (only sent after [setGroupJoin]).
  Stream<RemoteMessage> get groupMessages => _groupMessages.stream;

  /// Joins or leaves group play: the Player starts (or stops) sending
  /// `group_sync` and lets this phone download the playing song. Needs the
  /// local network; the Player refuses over the internet.
  Future<void> setGroupJoin(bool enabled) =>
      sendCommand(RemoteActions.groupJoin, {'enabled': enabled});

  final Map<String, double> _syncArrivals = {};

  /// One clock probe: returns the four timestamps (t0 and t3 on this phone's
  /// monotonic clock, t1 and t2 on the Player's). Used by `ClockSync`.
  Future<({double t0, double t1, double t2, double t3})> syncProbe() async {
    final t0 = _clock.nowMs();
    final reply = await _authenticatedRequest(
        MessageType.syncPing, {'t0': t0},
        timeout: const Duration(seconds: 3));
    // The arrival time is taken when the message came in, not when this
    // continuation got to run.
    final t3 = _syncArrivals.remove(reply.requestId) ?? _clock.nowMs();
    final t1 = reply.payload['t1'];
    final t2 = reply.payload['t2'];
    if (t1 is! num || t2 is! num) {
      throw ControllerException('The Player sent an unreadable clock reply.');
    }
    return (t0: t0, t1: t1.toDouble(), t2: t2.toDouble(), t3: t3);
  }

  /// Where to download a song for group play: the Player's local address and
  /// the headers that prove this phone joined. Null unless connected over the
  /// local network.
  ({Uri uri, Map<String, String> headers})? groupAudioRequest(int songId) {
    final s = _state;
    final sid = _sessionId;
    final tok = _token;
    final host = s.host;
    final port = s.port;
    if (!s.isConnected ||
        s.route != ConnectionType.local ||
        sid == null ||
        tok == null ||
        host == null ||
        port == null) {
      return null;
    }
    return (
      uri: Uri(scheme: 'http', host: host, port: port, path: '/group/audio/$songId'),
      headers: {'x-rt-session': sid, 'x-rt-token': tok},
    );
  }

  // ------------------------------------------------------------ library/queue

  Future<Map<String, dynamic>> _library(
    String scope, {
    String query = '',
    String? artist,
    String? album,
    String? view,
    int? playlistId,
    int? folderId,
    String? kind,
    int? parentId,
    String? groupKind,
    String? groupValue,
    int offset = 0,
    int limit = 50,
  }) async {
    final reply = await _authenticatedRequest(MessageType.libraryRequest, {
      'scope': scope,
      'query': query,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (view != null) 'view': view,
      if (playlistId != null) 'playlistId': playlistId,
      if (folderId != null) 'folderId': folderId,
      if (kind != null) 'kind': kind,
      if (parentId != null) 'parentId': parentId,
      if (groupKind != null) 'groupKind': groupKind,
      if (groupValue != null) 'groupValue': groupValue,
      'offset': offset,
      'limit': limit,
    });
    return reply.payload;
  }

  LibraryPage<T> _page<T>(
    Map<String, dynamic> p,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = p['items'];
    return LibraryPage(
      items: raw is List
          ? [
              for (final e in raw)
                if (e is Map) parse(Map<String, dynamic>.from(e)),
            ]
          : <T>[],
      total: p['total'] is num ? (p['total'] as num).toInt() : 0,
      offset: p['offset'] is num ? (p['offset'] as num).toInt() : 0,
      totalSeconds: p['totalSeconds'] is num ? (p['totalSeconds'] as num).toInt() : 0,
    );
  }

  Future<LibraryPage<RemoteSong>> songs({
    String query = '',
    String? artist,
    String? album,
    String? view,
    int? playlistId,
    int? folderId,
    String? groupKind,
    String? groupValue,
    int offset = 0,
    int limit = 50,
  }) async =>
      _page(
        await _library(LibraryScope.songs,
            query: query,
            artist: artist,
            album: album,
            view: view,
            playlistId: playlistId,
            folderId: folderId,
            groupKind: groupKind,
            groupValue: groupValue,
            offset: offset,
            limit: limit),
        RemoteSong.fromJson,
      );

  Future<LibraryPage<RemotePlaylist>> playlists({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async =>
      _page(
        await _library(LibraryScope.playlists,
            query: query, offset: offset, limit: limit),
        RemotePlaylist.fromJson,
      );

  /// The Online Library history kept on the Player, newest first, and whether
  /// the Player is recording it.
  Future<({LibraryPage<RemoteHistoryItem> page, bool enabled})> onlineHistory({
    int offset = 0,
    int limit = 50,
  }) async {
    final p = await _library(LibraryScope.onlineHistory, offset: offset, limit: limit);
    return (page: _page(p, RemoteHistoryItem.fromJson), enabled: p['enabled'] != false);
  }

  /// Plays a history entry again (or queues it). The link stays on the Player.
  Future<void> playHistory(int historyId, {bool queue = false}) => sendCommandForResult(
        RemoteActions.playHistory,
        {'historyId': historyId, if (queue) 'queue': true},
        const Duration(seconds: 30),
      );

  Future<void> removeHistory(int historyId) =>
      sendCommand(RemoteActions.removeHistory, {'historyId': historyId});

  Future<void> clearHistory() => sendCommand(RemoteActions.clearHistory);

  Future<void> setHistoryEnabled(bool enabled) =>
      sendCommand(RemoteActions.setHistoryEnabled, {'enabled': enabled});

  /// Album art for a library song, as a small JPEG, or null if it has none.
  /// Remembered, so each song's art is fetched once.
  ///
  /// [size] is the longest side in pixels (48 to 256). Lists ask for small
  /// pictures, Now Playing for the big one.
  Future<Uint8List?> artFor(int songId, {int size = 256}) {
    final key = '$songId@$size';
    return _art.putIfAbsent(key, () async {
      // A long list asks for many pictures at once: do a few at a time so
      // playback commands are not stuck behind them.
      while (_artBusy >= _maxArtRequests) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      _artBusy++;
      try {
        final r = await sendCommandForResult(RemoteActions.getArt,
            {'songId': songId, 'size': size}, const Duration(seconds: 15));
        final a = r['art'];
        return a is String && a.isNotEmpty ? base64Decode(a) : null;
      } catch (_) {
        _art.remove(key); // Try again next time (e.g. after a reconnect).
        return null;
      } finally {
        _artBusy--;
      }
    });
  }

  static const _maxArtRequests = 3;
  int _artBusy = 0;
  final Map<String, Future<Uint8List?>> _art = {};

  /// Sets the playback speed (0.5 to 2.0).
  Future<void> setSpeed(double speed) =>
      sendCommand(RemoteActions.setSpeed, {'speed': speed});

  Future<void> setFavorite(int songId, bool favorite) => sendCommand(
      RemoteActions.setFavorite, {'songId': songId, 'favorite': favorite});

  Future<RemoteFolder?> folderRoot() async {
    final p = await _library(LibraryScope.folderRoot, limit: 1);
    final page = _page(p, RemoteFolder.fromJson);
    return page.items.isEmpty ? null : page.items.first;
  }

  Future<LibraryPage<RemoteFolder>> folderChildren({
    int? parentId,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async =>
      _page(
        await _library(LibraryScope.folderChildren,
            parentId: parentId, query: query, offset: offset, limit: limit),
        RemoteFolder.fromJson,
      );

  /// Genres, years or album artists ([GroupKind]) with their song counts.
  Future<LibraryPage<RemoteGroup>> groups({
    required String kind,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async =>
      _page(
        await _library(LibraryScope.groups,
            kind: kind, query: query, offset: offset, limit: limit),
        RemoteGroup.fromJson,
      );

  /// Lyrics for a library song. The Player may need a few seconds to look
  /// them up the first time.
  Future<RemoteLyrics> lyrics(int songId) async {
    final r = await sendCommandForResult(
        RemoteActions.getLyrics, {'songId': songId}, const Duration(seconds: 30));
    final l = r['lyrics'];
    return l is Map<String, dynamic> ? RemoteLyrics.fromJson(l) : const RemoteLyrics();
  }

  Future<LibraryPage<RemoteFolder>> folders({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async =>
      _page(
        await _library(LibraryScope.folders,
            query: query, offset: offset, limit: limit),
        RemoteFolder.fromJson,
      );

  Future<LibraryPage<RemoteArtist>> artists({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async =>
      _page(
        await _library(LibraryScope.artists,
            query: query, offset: offset, limit: limit),
        RemoteArtist.fromJson,
      );

  Future<LibraryPage<RemoteAlbum>> albums({
    String query = '',
    String? artist,
    int offset = 0,
    int limit = 50,
  }) async =>
      _page(
        await _library(LibraryScope.albums,
            query: query, artist: artist, offset: offset, limit: limit),
        RemoteAlbum.fromJson,
      );

  Future<QueueSnapshot> getQueue() async {
    final result = await sendCommandForResult(RemoteActions.getQueue);
    final q = result['queue'];
    return QueueSnapshot.fromJson(
        q is Map ? Map<String, dynamic>.from(q) : const {});
  }

  // ---------------------------------------------------------------- messages

  void _onMessage(int gen, RemoteMessage m) {
    if (gen != _generation) return;
    _lastMessageAt = DateTime.now();
    if (m.type == MessageType.syncPong && m.requestId.isNotEmpty) {
      _syncArrivals[m.requestId] = _clock.nowMs();
    }

    if (m.requestId.isNotEmpty) {
      final waiter = _waiters.remove(m.requestId);
      if (waiter != null && !waiter.isCompleted) {
        if (m.type == MessageType.error) {
          waiter.completeError(
              ControllerException(m.errorMessage, code: m.errorCode));
        } else {
          waiter.complete(m);
        }
      }
    }

    switch (m.type) {
      case MessageType.pong:
        // The Player answers but has forgotten this connection (it was dropped
        // as stale): reconnect and resume the session.
        if (m.payload['hello'] == false && _state.isConnected) {
          unawaited(_closeTransport(intentional: false).then((_) {
            _onTransportDone(gen);
          }));
        }
      case MessageType.pairingResult:
        // The first reply is handled by the awaiting caller; later results
        // (e.g. accepted after waiting_for_player) arrive here.
        if (_state.status == ControllerStatus.awaitingCode ||
            _state.status == ControllerStatus.waitingForPlayer) {
          _onPairingResult(m.payload);
        }
      case MessageType.groupSync:
        if (_state.isConnected && !_groupMessages.isClosed) _groupMessages.add(m);
      case MessageType.state:
        if (_state.isConnected) {
          _update(playback: PlaybackState.fromJson(m.payload));
        }
      case MessageType.error:
        final code = m.errorCode;
        if (code == ErrorCodes.sessionReplaced ||
            code == ErrorCodes.invalidSession) {
          unawaited(_failSession(
            code == ErrorCodes.sessionReplaced
                ? 'Another Controller took over this Player.'
                : 'The Player ended this connection.',
            // Not "invalid": the Player may still trust this phone (a trusted
            // Controller that is replaced can simply reconnect). Only a
            // refused reconnect, which is checked when trying, forgets it.
          ));
        }
    }
  }

  void _onTransportDone(int gen) {
    if (gen != _generation || _disposed) return;
    _stopHeartbeat();
    _failWaiters('The connection was lost.');
    // Leave the dead connection (for the relay: its channel) before any
    // reconnect, so lost connections never pile up.
    unawaited(_closeTransport(intentional: false));
    switch (_state.status) {
      case ControllerStatus.connected:
        _beginReconnect();
      case ControllerStatus.connecting:
      case ControllerStatus.awaitingCode:
      case ControllerStatus.waitingForPlayer:
        unawaited(_failSession('The connection to the Player was lost.'));
      case ControllerStatus.reconnecting:
      case ControllerStatus.disconnected:
        break;
    }
  }

  // --------------------------------------------------------------- reconnect

  void _beginReconnect() {
    if (_reconnecting || _disposed) return;
    _reconnecting = true;
    final epoch = _epoch;
    _update(
      status: ControllerStatus.reconnecting,
      message: 'Connection lost. Reconnecting…',
    );
    unawaited(_reconnectLoop(epoch));
  }

  Future<void> _reconnectLoop(int epoch) async {
    try {
      if (_routes.isEmpty) return;
      for (final delay in reconnectDelays) {
        await Future<void>.delayed(delay);
        if (epoch != _epoch || _disposed) return;
        // Each round tries every route, local first: in Auto mode a lost Wi‑Fi
        // link falls back to the online relay, and the same session token
        // resumes there without pairing again.
        for (final route in _routes) {
          try {
            await _open(route, resume: true);
            if (epoch != _epoch) return;
            return; // _open set status to connected.
          } on _NeedsPairing {
            if (epoch == _epoch) {
              await _failSession('Connection lost. Please pair again.',
                  sessionInvalid: true);
            }
            return;
          } on ControllerException {
            continue;
          } on TransportException {
            continue;
          } catch (_) {
            // Anything unexpected is just a failed attempt: try the next
            // route or round, never leave the screen stuck on "Reconnecting".
            continue;
          }
        }
      }
      if (epoch == _epoch) {
        await _failSession("Couldn't reconnect to the Player.");
      }
    } finally {
      _reconnecting = false;
    }
  }

  // --------------------------------------------------------------- heartbeat

  void _startHeartbeat(int gen) {
    _stopHeartbeat();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (gen != _generation) return;
      if (DateTime.now().difference(_lastMessageAt) > connectionTimeout) {
        // Nothing heard for too long: treat the link as lost.
        unawaited(_closeTransport(intentional: false).then((_) {
          _onTransportDone(gen);
        }));
        return;
      }
      final t = _transport;
      if (t != null) {
        t
            .send(RemoteMessage(type: MessageType.ping, requestId: _uuid.v4()))
            .catchError((_) {});
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  // ------------------------------------------------------------------ helpers

  Future<RemoteMessage> _request(RemoteMessage m, {Duration? timeout}) async {
    final t = _transport;
    if (t == null) throw ControllerException('Not connected to a Player.');
    final completer = Completer<RemoteMessage>();
    _waiters[m.requestId] = completer;
    try {
      await t.send(m);
      return await completer.future.timeout(timeout ?? commandTimeout);
    } on TimeoutException {
      throw ControllerException('The Player did not respond. Please try again.');
    } on TransportException catch (e) {
      throw ControllerException(e.message);
    } finally {
      _waiters.remove(m.requestId);
    }
  }

  void _failWaiters(String message) {
    final pending = _waiters.values.toList();
    _waiters.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(ControllerException(message));
    }
  }

  Future<void> _closeTransport({required bool intentional}) async {
    final t = _transport;
    _transport = null;
    await _sub?.cancel();
    _sub = null;
    if (t != null) await t.disconnect(intentional: intentional);
  }

  /// Closes everything without touching the visible state.
  Future<void> _teardown() async {
    _epoch++;
    _generation++;
    _reconnecting = false;
    _stopHeartbeat();
    _failWaiters('Disconnected.');
    await _closeTransport(intentional: true);
  }

  /// Ends the session and tells the user why. No automatic reconnect.
  Future<void> _failSession(String message, {bool sessionInvalid = false}) async {
    await _teardown();
    _sessionId = null;
    _token = null;
    _emit(ControllerClientState(
      status: ControllerStatus.disconnected,
      host: _state.host,
      port: _state.port,
      roomCode: _state.roomCode,
      mode: _state.mode,
      message: message,
      sessionInvalid: sessionInvalid,
    ));
  }

  /// User-initiated disconnect (tells the Player to revoke the session).
  Future<void> disconnect() async {
    await _teardown();
    _sessionId = null;
    _token = null;
    if (!_disposed) {
      _emit(const ControllerClientState());
    }
  }

  /// Test/diagnostic helper: drop the socket as if the network failed.
  Future<void> debugDropConnection() async {
    final gen = _generation;
    await _closeTransport(intentional: false);
    _onTransportDone(gen);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
    await _stateController.close();
    await _groupMessages.close();
  }
}
