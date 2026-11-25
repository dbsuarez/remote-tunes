import 'dart:async';
import '../sleep_timer.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/constants.dart';
import '../../../core/jamendo_url.dart';
import '../../../core/mono_clock.dart';
import '../../../core/models/enums.dart';
import '../../../core/protocol/protocol.dart';
import '../../../data/repositories/paired_controllers_store.dart';
import '../../../core/protocol/library_models.dart';
import '../../external/control_mode_engine.dart';
import '../../online/online_status.dart';
import '../../group/calibration_track.dart';
import '../group_sync_source.dart';
import '../playback_engine.dart';
import '../queue/playable_song.dart';
import '../queue_aware_engine.dart';
import '../save_queue.dart';
import 'player_advertiser.dart';
import 'player_library.dart';
import 'server_channel.dart';

/// A Controller asking to pair, shown to the Player user.
class PendingPairingInfo {
  const PendingPairingInfo({
    required this.controllerName,
    required this.address,
    required this.connectionType,
    required this.code,
    required this.expiresAt,
    required this.codeVerified,
    this.replacesController,
  });

  final String controllerName;
  final String address;
  final ConnectionType connectionType;
  final String code;
  final DateTime expiresAt;

  /// The Controller already typed the right code and is waiting for Accept.
  final bool codeVerified;

  /// Name of the currently paired Controller that accepting would replace.
  final String? replacesController;
}

/// A Controller this Player trusts (it can reconnect without pairing again).
class TrustedDeviceInfo {
  const TrustedDeviceInfo({
    required this.sessionId,
    required this.name,
    required this.lastSeen,
  });

  final String sessionId;
  final String name;
  final DateTime lastSeen;
}

class ControllerInfo {
  const ControllerInfo({
    required this.name,
    required this.address,
    required this.connectionType,
    required this.connected,
  });

  final String name;
  final String address;
  final ConnectionType connectionType;

  /// False while the paired Controller is temporarily offline (it may resume).
  final bool connected;
}

/// Immutable snapshot for the UI.
class PlayerServerState {
  const PlayerServerState({
    this.running = false,
    this.port,
    this.addresses = const [],
    this.error,
    this.advertisingWarning,
    this.pending,
    this.controller,
    this.online,
    this.pairingTicket,
    this.trusted = const [],
    this.groupJoined = false,
  });

  /// A Controller has joined group play (the Player should stay awake and keep
  /// its Wi-Fi in a fast mode).
  final bool groupJoined;

  /// Controllers that may reconnect without pairing, newest first.
  final List<TrustedDeviceInfo> trusted;

  /// One-time ticket for the pairing QR code (replaces typing the code).
  /// Changes after each use and every few minutes.
  final String? pairingTicket;

  /// True once the Player accepts Controllers (on the local network, online,
  /// or both).
  final bool running;

  /// Local WebSocket port; null when the local server is off (online-only).
  final int? port;
  final List<String> addresses;

  /// Online relay status; null when online is not in use.
  final OnlineRelayInfo? online;

  /// Plain-language reason the server could not start.
  final String? error;

  /// Set when mDNS advertising failed; manual IP/port still works.
  final String? advertisingWarning;
  final PendingPairingInfo? pending;
  final ControllerInfo? controller;
}

class _Conn {
  _Conn(this.channel) : lastSeen = DateTime.now();

  final ServerChannel channel;
  String get address => channel.address;
  ConnectionType get type => channel.type;
  String deviceName = 'Unknown device';
  bool helloDone = false;

  /// The Controller sent `bye`: it disconnected on purpose.
  bool byeReceived = false;
  DateTime lastSeen;
  StreamSubscription<dynamic>? sub;
}

class _Session {
  _Session({
    required this.sessionId,
    required this.token,
    required this.controllerName,
    required this.address,
    required this.type,
    required this.conn,
  });

  final String sessionId;
  final String token;
  final String controllerName;

  /// This Controller joined group play: it gets `group_sync` messages and may
  /// download the audio of the playing song.
  bool group = false;

  /// Where the Controller last connected from (updated when it resumes on a
  /// different route, e.g. local Wi‑Fi -> online).
  String address;
  ConnectionType type;
  _Conn? conn;
}

class _Pending {
  _Pending({
    required this.conn,
    required this.code,
    required this.expiresAt,
  });

  final _Conn conn;
  final String code;
  final DateTime expiresAt;
  Timer? timer;
  int failedAttempts = 0;
  bool accepted = false;
  bool codeVerified = false;
  String codeRequestId = '';
}

/// The Player side of local control: a WebSocket server with pairing, session
/// tokens and playback commands. Pure Dart (no Flutter) so it can be tested
/// over loopback.
class PlayerServer {
  PlayerServer({
    required this.engine,
    required this.deviceName,
    this.port = AppConstants.defaultPlayerPort,
    this.bindAddress,
    this.store,
    this.advertiser,
    this.library,
    this.enableLocal = true,
    this.continueWithoutLocal = false,
    this.pairingTtl = AppConstants.pairingCodeTtl,
    this.staleTimeout = AppConstants.connectionTimeout,
    this.maxCodeAttempts = 3,
    this.ticketTtl = const Duration(minutes: 5),
    Random? random,
    MonoClock? clock,
    this.scratchDir,
    SleepTimerService? sleepTimer,
  })  : _random = random ?? Random.secure(),
        clock = clock ?? MonoClock.instance,
        _ownsSleepTimer = sleepTimer == null,
        _sleep = sleepTimer ?? SleepTimerService(onFire: engine.pause) {
    // Whoever sets or ends the timer, the connected Controller is told.
    _sleepSub = _sleep.changes.listen((_) {
      final s = _session;
      final conn = s?.conn;
      if (s != null && conn != null) _sendState(conn, s);
    });
  }

  /// The sleep timer (shared with this phone's own screens when given).
  SleepTimerService get sleepTimer => _sleep;

  final SleepTimerService _sleep;
  final bool _ownsSleepTimer;
  StreamSubscription<int>? _sleepSub;

  final PlaybackEngine engine;
  final String deviceName;
  final int port;
  final InternetAddress? bindAddress;
  final PairedControllersStore? store;
  final PlayerAdvertiser? advertiser;

  /// Music library for `library_request` and song-based commands (Phase 2).
  final PlayerLibrary? library;

  /// False for "Online only": no local server is opened on the network.
  final bool enableLocal;

  /// If the local server cannot start (e.g. the port is busy), keep running so
  /// the online relay can still be used. The problem stays in [PlayerServerState.error].
  final bool continueWithoutLocal;
  final Duration pairingTtl;
  final Duration staleTimeout;
  final int maxCodeAttempts;
  final Duration ticketTtl;
  final Random _random;

  /// The Player's monotonic clock, used for group play.
  final MonoClock clock;

  /// Where the Auto-align click track is written (the app's temporary folder).
  /// Defaults to the system temporary directory.
  final Directory? scratchDir;

  String? _ticket;
  Timer? _ticketTimer;
  List<TrustedController> _trusted = const [];

  HttpServer? _http;
  bool _running = false;
  OnlineRelayInfo? _online;
  StreamSubscription<dynamic>? _engineSub;
  Timer? _staleTimer;
  bool _stopRequested = false;

  final Set<_Conn> _conns = {};
  _Session? _session;
  _Pending? _pending;

  List<String> _addresses = const [];
  String? _error;
  String? _advertisingWarning;

  final StreamController<PlayerServerState> _stateController =
      StreamController<PlayerServerState>.broadcast();
  PlayerServerState _state = const PlayerServerState();

  PlayerServerState get current => _state;
  Stream<PlayerServerState> get stateStream => _stateController.stream;

  // ---------------------------------------------------------------- lifecycle

  Future<void> start() async {
    if (_running || _stopRequested) return;
    HttpServer? server;
    if (enableLocal) {
      try {
        server = await shelf_io.serve(
          _handler,
          bindAddress ?? InternetAddress.anyIPv4,
          port,
        );
      } on SocketException {
        _error = 'Port $port is already in use. Pick another port in Settings.';
        if (!continueWithoutLocal) {
          _publish();
          return;
        }
      } catch (_) {
        _error = "The Player couldn't start. Check your network and try again.";
        if (!continueWithoutLocal) {
          _publish();
          return;
        }
      }
      if (_stopRequested) {
        await server?.close(force: true);
        return;
      }
    }
    _http = server;
    _running = true;
    // Keep a local-start problem visible when the Player carries on online.
    if (server != null) _error = null;
    _addresses = server != null ? await _localAddresses() : const [];
    _engineSub = engine.states.listen(_onEngineState);
    _newTicket();
    _staleTimer = Timer.periodic(
      Duration(milliseconds: max(200, staleTimeout.inMilliseconds ~/ 3)),
      (_) => _closeStale(),
    );
    await _safe(() => store?.deactivateAll());
    await _refreshTrusted();
    _publish();

    final adv = advertiser;
    if (server != null && adv != null) {
      try {
        await adv.start(
          name: deviceName,
          port: server.port,
          addresses: _addresses,
          roomCode: _online?.roomCode,
        );
      } catch (_) {
        _advertisingWarning =
            "Automatic discovery isn't available. Use the address shown below to connect manually.";
        _publish();
      }
    }
  }

  /// Called by the online relay host to report its state (room code,
  /// connected/reconnecting/failed) so the UI can show it.
  void updateOnline(OnlineRelayInfo? info) {
    _online = info;
    _publish();
  }

  /// Hands the server a new Controller connection (a local WebSocket, or a
  /// virtual peer from the online relay).
  void acceptConnection(ServerChannel channel) => _onConnection(channel);

  Future<void> stop() async {
    _stopRequested = true;
    _staleTimer?.cancel();
    _ticketTimer?.cancel();
    if (_ownsSleepTimer) _sleep.set(null);
    unawaited(_sleepSub?.cancel());
    _sleepSub = null;
    _groupTimer?.cancel();
    _groupTimer = null;
    await _endCalibration();
    _ticket = null;
    await _engineSub?.cancel();
    _engineSub = null;
    _pending?.timer?.cancel();
    _pending = null;
    final session = _session;
    _session = null;
    if (session != null) await _safe(() => store?.setActive(session.sessionId, false));
    for (final c in _conns.toList()) {
      _closeConn(c, CloseCodes.playerDisconnected, 'server_stopped');
    }
    _conns.clear();
    await advertiser?.stop();
    await _http?.close(force: true);
    _http = null;
    _running = false;
    _publish();
    await _stateController.close();
  }

  // --------------------------------------------------------------------- UI API

  /// Player user accepts the pending pairing request.
  void acceptPairing() {
    final p = _pending;
    if (p == null) return;
    p.accepted = true;
    if (p.codeVerified) {
      _completePairing(p);
    } else {
      _publish();
    }
  }

  /// Player user rejects the pending pairing request.
  void rejectPairing() {
    final p = _pending;
    if (p == null) return;
    _finishPending(p, PairingStatus.rejected);
  }

  /// Player user removes one trusted Controller (it must pair again).
  Future<void> forgetTrusted(String sessionId) async {
    final s = _session;
    if (s != null && s.sessionId == sessionId) {
      await disconnectController();
      return;
    }
    await _safe(() => store?.forget(sessionId));
    await _refreshTrusted();
    _publish();
  }

  /// Player user forgets every trusted Controller.
  Future<void> forgetAllTrusted() async {
    final s = _session;
    if (s != null) await disconnectController();
    await _safe(() => store?.forgetAll());
    await _refreshTrusted();
    _publish();
  }

  Future<void> _refreshTrusted() async {
    try {
      _trusted = await store?.listTrusted() ?? const [];
    } catch (_) {}
  }

  /// Player user disconnects (and revokes) the paired Controller.
  Future<void> disconnectController() async {
    final s = _session;
    if (s == null) return;
    _session = null;
    _updateGroupTimer();
    final conn = s.conn;
    if (conn != null) {
      _send(
        conn,
        RemoteMessage.error(
          ErrorCodes.invalidSession,
          'The Player disconnected this Controller.',
          sessionId: s.sessionId,
        ),
      );
      _closeConn(conn, CloseCodes.playerDisconnected, 'player_disconnect');
    }
    await _safe(() async {
      await store?.setActive(s.sessionId, false);
      await store?.forget(s.sessionId); // disconnecting from the Player forgets it
    });
    await _refreshTrusted();
    _publish();
  }

  // ------------------------------------------------------------------- plumbing

  Handler get _handler => (Request request) {
        // Group play: the other phone downloads the playing song here.
        final segs = request.url.pathSegments;
        if (segs.length == 3 && segs[0] == 'group' && segs[1] == 'audio') {
          return _serveGroupAudio(request, int.tryParse(segs[2]));
        }
        final info = request.context['shelf.io.connection_info'];
        final remote =
            info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
        return webSocketHandler(
          (WebSocketChannel channel, String? _) =>
              _onConnection(WebSocketServerChannel(channel, remote)),
        )(request);
      };

  final Map<String, ({int length, DateTime modified, String hash})> _hashes = {};

  /// `GET /group/audio/<songId>` with the session id and token as headers. Only
  /// for a Controller that joined group play, and only for songs in the
  /// library (never an arbitrary path).
  Future<Response> _serveGroupAudio(Request request, int? songId) async {
    final s = _session;
    final sid = request.headers['x-rt-session'];
    final tok = request.headers['x-rt-token'];
    if (s == null ||
        !s.group ||
        sid == null ||
        tok == null ||
        sid != s.sessionId ||
        !_tokenEquals(tok, s.token)) {
      return Response.forbidden('Not allowed.');
    }
    final lib = library;
    File? file;
    if (songId == CalibrationTrack.songId) {
      // The Auto-align click track, only while a test is running.
      file = _calibration?.file;
    } else if (songId != null && lib != null) {
      file = await lib.audioFileFor(songId);
    }
    if (file == null) return Response.notFound('No such song.');
    try {
      final stat = await file.stat();
      final cached = _hashes[file.path];
      String hash;
      if (cached != null && cached.length == stat.size && cached.modified == stat.modified) {
        hash = cached.hash;
      } else {
        hash = (await sha256.bind(file.openRead()).first).toString();
        _hashes[file.path] = (length: stat.size, modified: stat.modified, hash: hash);
      }
      final dot = file.path.lastIndexOf('.');
      final ext = dot < 0 ? '' : file.path.substring(dot + 1).toLowerCase();
      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': switch (ext) {
            'mp3' => 'audio/mpeg',
            'm4a' || 'aac' => 'audio/mp4',
            'ogg' || 'opus' => 'audio/ogg',
            'flac' => 'audio/flac',
            'wav' => 'audio/wav',
            _ => 'application/octet-stream',
          },
          'content-length': '${stat.size}',
          'x-rt-sha256': hash,
          'x-rt-ext': RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'audio',
        },
      );
    } on FileSystemException {
      return Response.notFound('No such song.');
    }
  }

  void _onConnection(ServerChannel channel) {
    final conn = _Conn(channel);
    _conns.add(conn);
    conn.sub = channel.incoming.listen(
      (raw) => _onRaw(conn, raw),
      onDone: () => _onClosed(conn),
      onError: (_) => _onClosed(conn),
      cancelOnError: true,
    );
  }

  void _closeStale() {
    final now = DateTime.now();
    for (final c in _conns.toList()) {
      if (now.difference(c.lastSeen) > staleTimeout) {
        _closeConn(c, CloseCodes.timeout, 'timeout');
        _onClosed(c);
      }
    }
  }

  void _closeConn(_Conn c, int code, String reason) {
    try {
      unawaited(c.channel.close(code, reason).catchError((_) {}));
    } catch (_) {}
  }

  void _onClosed(_Conn conn) {
    if (!_conns.remove(conn)) return;
    conn.sub?.cancel();

    final p = _pending;
    if (p != null && p.conn == conn) {
      p.timer?.cancel();
      _pending = null;
    }

    final s = _session;
    if (s != null && s.conn == conn) {
      s.conn = null;
      s.group = false; // it joins again when it reconnects
      _updateGroupTimer();
      if (conn.byeReceived ||
          conn.channel.closeCode == CloseCodes.controllerDisconnected) {
        // The Controller user disconnected on purpose: revoke the session.
        _session = null;
      }
      _safe(() => store?.setActive(s.sessionId, false));
    }
    _publish();
  }

  void _send(_Conn conn, RemoteMessage message) {
    try {
      conn.channel.send(message.encode());
    } catch (_) {
      // Connection already closed; the onDone handler cleans up.
    }
  }

  /// Answers a clock-offset probe from the Controller: when the ping arrived
  /// and when this reply leaves, on this phone's monotonic clock.
  void _onSyncPing(_Conn conn, RemoteMessage msg) {
    final t1 = clock.nowMs();
    final s = _authorize(conn, msg);
    if (s == null) return;
    _send(
      conn,
      RemoteMessage(
        type: MessageType.syncPong,
        requestId: msg.requestId,
        sessionId: s.sessionId,
        payload: {'t0': msg.payload['t0'], 't1': t1, 't2': clock.nowMs()},
      ),
    );
  }

  Timer? _groupTimer;

  // ---------------------------------------------------------------- Auto-align

  _Calibration? _calibration;

  /// Plays the click track on this Player (as the next thing in the queue) so
  /// the other phone can measure the difference between the two phones.
  Future<void> _startCalibration() async {
    if (_calibration != null) await _endCalibration();
    final dir = scratchDir ?? Directory.systemTemp;
    final file = File('${dir.path}${Platform.pathSeparator}rt_calibration.wav');
    final bytes = CalibrationTrack.wavBytes();
    if (!file.existsSync() || file.lengthSync() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    // Remember what was playing, to put it back afterwards.
    final before = engine.state;
    int? origItem;
    final e0 = engine;
    if (e0 is QueueAwareEngine) {
      for (final i in e0.queueSnapshot().items) {
        if (i.isCurrent) origItem = i.queueItemId;
      }
    }
    final cal = _calibration = _Calibration(file, before.volume)
      ..origItemId = origItem
      ..origPositionSeconds = before.positionSeconds
      ..wasPlaying = before.isPlaying;
    // A safety net: whatever happens, this is undone after 40 seconds.
    cal.watchdog = Timer(const Duration(seconds: 40), () => unawaited(_endCalibration()));
    await _queueEngine.playNow([
      PlayableSong(
        id: CalibrationTrack.songId,
        title: 'Sync test (Auto-align)',
        artist: 'RemoteTunes',
        album: 'Auto-align',
        filePath: file.path,
        durationSeconds: CalibrationTrack.seconds.round(),
      ),
    ]);
  }

  Future<void> _muteForCalibration(bool mute) async {
    final cal = _calibration;
    if (cal == null) return;
    await engine.setVolume(mute ? 0.0 : cal.savedVolume);
  }

  /// Puts everything back: the volume, the queue without the click track, and
  /// the playback state (paused).
  Future<void> _endCalibration() async {
    final cal = _calibration;
    if (cal == null) return;
    _calibration = null;
    cal.watchdog?.cancel();
    // Silent while things are moved around (the song that was playing is
    // briefly started again to put it back), and the volume comes back last.
    try {
      await engine.setVolume(0.0);
    } catch (_) {}
    try {
      await engine.pause();
    } catch (_) {}
    try {
      final e = engine;
      if (e is QueueAwareEngine) {
        for (final i in e.queueSnapshot().items) {
          if (i.song.id == CalibrationTrack.songId) {
            await e.removeQueueItem(i.queueItemId);
          }
        }
        // Back to the song (and spot) that was playing before the test.
        final orig = cal.origItemId;
        if (orig != null &&
            e.queueSnapshot().items.any((i) => i.queueItemId == orig)) {
          await e.playQueueItem(orig);
          await e.pause();
          if (cal.origPositionSeconds > 0) {
            try {
              await e.seek(cal.origPositionSeconds);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    try {
      await engine.setVolume(cal.savedVolume);
    } catch (_) {}
    try {
      if (cal.wasPlaying) await engine.play();
    } catch (_) {}
  }

  /// While a Controller has joined group play it gets an update every second,
  /// whether or not anything changed, so it can keep checking its drift and
  /// recover from a missed message. (State changes also send one at once.)
  void _updateGroupTimer() {
    final s = _session;
    final wanted = s != null && s.group && s.conn != null;
    if (!wanted) {
      _groupTimer?.cancel();
      _groupTimer = null;
      // Nobody is playing along any more: undo an unfinished Auto-align.
      unawaited(_endCalibration());
      return;
    }
    _groupTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final cur = _session;
      final conn = cur?.conn;
      if (cur == null || conn == null || !cur.group) {
        _updateGroupTimer();
        return;
      }
      _sendGroupSync(conn, cur);
    });
  }

  /// Tells a joined Controller what is playing and where, stamped with this
  /// phone's clock, so it can play the same song at the same moment.
  void _sendGroupSync(_Conn conn, _Session s) {
    if (!s.group) return;
    final e = engine;
    final source = e is GroupSyncSource ? e as GroupSyncSource : null;
    final st = e.state;
    // Sample the position and the clock together, as close as possible.
    final positionMs = source?.positionMsNow;
    final at = clock.nowMs();
    final libraryId = st.songId; // null for internet links and external apps
    _send(
      conn,
      RemoteMessage(
        type: MessageType.groupSync,
        sessionId: s.sessionId,
        payload: {
          if (libraryId != null && positionMs != null) 'songId': libraryId,
          'positionMs': positionMs ?? 0,
          'atMs': at,
          'playing': st.isPlaying && !st.isLoading,
          'speed': st.speed,
          'durationMs': st.durationSeconds * 1000,
          if (source?.nextLibrarySongId != null) 'nextSongId': source!.nextLibrarySongId,
        },
      ),
    );
  }

  void _sendState(_Conn conn, _Session s) {
    _sendGroupSync(conn, s);
    _send(
      conn,
      RemoteMessage(
        type: MessageType.state,
        sessionId: s.sessionId,
        payload: {
          ...engine.state.toJson(),
          if (_sleepSecondsLeft > 0) 'sleepTimerSeconds': _sleepSecondsLeft,
          if (_currentIsFavorite) 'favorite': true,
        },
      ),
    );
  }

  bool get _currentIsFavorite {
    final id = engine.state.songId;
    return id != null && (library?.isFavorite(id) ?? false);
  }

  /// Seconds left on the sleep timer (rounded up), 0 when it is off.
  int get _sleepSecondsLeft => _sleep.secondsLeft;

  /// Starts (or with null, cancels) the sleep timer. [d] is exposed to tests
  /// through [debugSetSleepTimer].
  void _setSleepTimer(Duration? d) => _sleep.set(d);

  void debugSetSleepTimer(Duration? d) => _setSleepTimer(d);

  void _onEngineState(dynamic _) {
    final s = _session;
    final conn = s?.conn;
    if (s != null && conn != null) _sendState(conn, s);
  }

  Future<void> _safe(FutureOr<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      // History is best-effort; never break control because of the database.
    }
  }

  void _publish() {
    if (_stateController.isClosed) return;
    final p = _pending;
    final s = _session;
    _state = PlayerServerState(
      running: _running,
      port: _http?.port,
      addresses: _addresses,
      error: _error,
      advertisingWarning: _advertisingWarning,
      online: _online,
      pairingTicket: _ticket,
      groupJoined: s != null && s.group && s.conn != null,
      trusted: [
        for (final t in _trusted)
          TrustedDeviceInfo(sessionId: t.sessionId, name: t.name, lastSeen: t.lastSeen),
      ],
      pending: p == null
          ? null
          : PendingPairingInfo(
              controllerName: p.conn.deviceName,
              address: p.conn.address,
              connectionType: p.conn.type,
              code: p.code,
              expiresAt: p.expiresAt,
              codeVerified: p.codeVerified,
              replacesController: s?.controllerName,
            ),
      controller: s == null
          ? null
          : ControllerInfo(
              name: s.controllerName,
              address: s.address,
              connectionType: s.type,
              connected: s.conn != null,
            ),
    );
    _stateController.add(_state);
  }

  // ------------------------------------------------------------------ messages

  void _onRaw(_Conn conn, dynamic raw) {
    conn.lastSeen = DateTime.now();
    final RemoteMessage msg;
    try {
      msg = RemoteMessage.decode(raw);
    } on ProtocolException catch (e) {
      _send(conn, RemoteMessage.error(ErrorCodes.invalidMessage, e.message));
      return;
    }

    switch (msg.type) {
      case MessageType.ping:
        // `hello:false` tells a Controller this Player no longer knows its
        // connection (e.g. dropped as stale on the online relay, which has no
        // close signal), so it should say hello again and resume.
        _send(
          conn,
          RemoteMessage(
            type: MessageType.pong,
            requestId: msg.requestId,
            payload: {'hello': conn.helloDone},
          ),
        );
      case MessageType.bye:
        // The Controller disconnected on purpose (the only way the online relay
        // can say so): revoke its session.
        conn.byeReceived = true;
        _closeConn(conn, CloseCodes.controllerDisconnected, 'bye');
        _onClosed(conn);
      case MessageType.hello:
        _onHello(conn, msg);
      case MessageType.pairingRequest:
        _onPairingRequest(conn, msg);
      case MessageType.pairingCode:
        _onPairingCode(conn, msg);
      case MessageType.syncPing:
        _onSyncPing(conn, msg);
      case MessageType.command:
        unawaited(_onCommand(conn, msg));
      case MessageType.libraryRequest:
        unawaited(_onLibraryRequest(conn, msg));
      default:
        break; // Unknown types are ignored (docs/04).
    }
  }

  bool _requireHello(_Conn conn, RemoteMessage msg) {
    if (conn.helloDone) return true;
    _send(
      conn,
      RemoteMessage.error(
        ErrorCodes.invalidMessage,
        'Say hello first.',
        requestId: msg.requestId,
      ),
    );
    return false;
  }

  void _onHello(_Conn conn, RemoteMessage msg) {
    final version = msg.payload['protocolVersion'];
    if (version != AppConstants.protocolVersion) {
      _send(
        conn,
        RemoteMessage.error(
          ErrorCodes.unsupportedProtocol,
          'This Player speaks protocol ${AppConstants.protocolVersion}, but the '
          'Controller sent $version. Update both apps.',
          requestId: msg.requestId,
        ),
      );
      _closeConn(conn, CloseCodes.unsupportedProtocol, 'unsupported_protocol');
      return;
    }
    final name = msg.payload['deviceName'];
    if (name is String && name.trim().isNotEmpty) {
      conn.deviceName = name.trim();
    }
    conn.helloDone = true;

    var resumed = false;
    var s = _session;
    if (s != null &&
        msg.sessionId == s.sessionId &&
        msg.token != null &&
        _tokenEquals(msg.token!, s.token)) {
      final old = s.conn;
      s.conn = conn;
      s.address = conn.address; // may be a new route (Wi‑Fi -> online)
      s.type = conn.type;
      resumed = true;
      if (old != null && old != conn) {
        _closeConn(old, CloseCodes.resumedElsewhere, 'resumed_elsewhere');
      }
      _safe(() => store?.setActive(s.sessionId, true));
    }

    final sid = msg.sessionId;
    final tok = msg.token;
    if (!resumed && store != null && sid.isNotEmpty && tok != null) {
      // Not the live session: maybe a trusted device coming back (the Player
      // was restarted, or the Controller left on purpose).
      unawaited(_resumeTrusted(conn, msg, sid, tok));
      return;
    }
    _replyHello(conn, msg, resumed, s);
  }

  Future<void> _resumeTrusted(
      _Conn conn, RemoteMessage msg, String sid, String tok) async {
    _Session? s;
    try {
      final t = await store!.findTrusted(sid);
      if (t != null && _tokenEquals(hashToken(tok), t.tokenHash)) {
        final old = _session;
        s = _Session(
          sessionId: sid,
          token: tok,
          controllerName: t.name,
          address: conn.address,
          type: conn.type,
          conn: conn,
        );
        if (old != null && old.sessionId != sid) {
          final oldConn = old.conn;
          if (oldConn != null && oldConn != conn) {
            _send(
              oldConn,
              RemoteMessage.error(
                ErrorCodes.sessionReplaced,
                'Another Controller took over this Player.',
                sessionId: old.sessionId,
              ),
            );
            _closeConn(oldConn, CloseCodes.sessionReplaced, 'session_replaced');
          }
          await _safe(() => store?.setActive(old.sessionId, false));
        } else if (old != null) {
          final oldConn = old.conn;
          if (oldConn != null && oldConn != conn) {
            _closeConn(oldConn, CloseCodes.resumedElsewhere, 'resumed_elsewhere');
          }
        }
        _session = s;
        await _safe(() => store?.setActive(sid, true));
        await _refreshTrusted();
      }
    } catch (_) {
      s = null;
    }
    if (!_conns.contains(conn)) return; // it went away while we looked
    _replyHello(conn, msg, s != null, s);
  }

  void _replyHello(_Conn conn, RemoteMessage msg, bool resumed, _Session? s) {
    _send(
      conn,
      RemoteMessage(
        type: MessageType.hello,
        requestId: msg.requestId,
        sessionId: resumed ? s!.sessionId : '',
        payload: {
          'protocolVersion': AppConstants.protocolVersion,
          'role': 'player',
          'deviceName': deviceName,
          'resumed': resumed,
        },
      ),
    );
    if (resumed) {
      _sendState(conn, s!);
      _publish();
    }
  }

  // ------------------------------------------------------------------- pairing

  void _onPairingRequest(_Conn conn, RemoteMessage msg) {
    if (!_requireHello(conn, msg)) return;

    final existing = _pending;
    if (existing != null) _finishPending(existing, PairingStatus.rejected);

    final p = _Pending(
      conn: conn,
      code: _newCode(),
      expiresAt: DateTime.now().add(pairingTtl),
    );
    p.timer = Timer(pairingTtl, () {
      if (identical(_pending, p)) _finishPending(p, PairingStatus.expired);
    });
    _pending = p;

    _send(
      conn,
      RemoteMessage(
        type: MessageType.pairingResult,
        requestId: msg.requestId,
        payload: {
          'status': PairingStatus.pending,
          'expiresInSeconds': pairingTtl.inSeconds,
        },
      ),
    );
    _publish();
  }

  void _onPairingCode(_Conn conn, RemoteMessage msg) {
    if (!_requireHello(conn, msg)) return;
    final p = _pending;
    if (p == null || p.conn != conn) {
      _send(
        conn,
        RemoteMessage.error(
          ErrorCodes.invalidCode,
          'No pairing is in progress. Request pairing first.',
          requestId: msg.requestId,
        ),
      );
      return;
    }
    if (DateTime.now().isAfter(p.expiresAt)) {
      _finishPending(p, PairingStatus.expired);
      return;
    }

    final code = msg.payload['code']?.toString().trim() ?? '';
    final ticket = _ticket;
    final viaTicket = ticket != null && _tokenEquals(code, ticket);
    if (!viaTicket && !_tokenEquals(code, p.code)) {
      p.failedAttempts++;
      if (p.failedAttempts >= maxCodeAttempts) {
        _finishPending(p, PairingStatus.tooManyAttempts);
      } else {
        _send(
          conn,
          RemoteMessage.error(
            ErrorCodes.invalidCode,
            "That code isn't right. ${maxCodeAttempts - p.failedAttempts} "
            'attempt(s) left.',
            requestId: msg.requestId,
          ),
        );
      }
      return;
    }

    if (viaTicket) _newTicket(); // a ticket works once
    p.codeVerified = true;
    p.codeRequestId = msg.requestId;
    if (p.accepted) {
      _completePairing(p);
    } else {
      _send(
        conn,
        RemoteMessage(
          type: MessageType.pairingResult,
          requestId: msg.requestId,
          payload: {'status': PairingStatus.waitingForPlayer},
        ),
      );
      _publish();
    }
  }

  void _finishPending(_Pending p, String status) {
    p.timer?.cancel();
    if (identical(_pending, p)) _pending = null;
    _send(
      p.conn,
      RemoteMessage(
        type: MessageType.pairingResult,
        requestId: p.codeRequestId,
        payload: {'status': status},
      ),
    );
    _publish();
  }

  void _completePairing(_Pending p) {
    p.timer?.cancel();
    _pending = null;

    final old = _session;
    final session = _Session(
      sessionId: const Uuid().v4(),
      token: _newToken(),
      controllerName: p.conn.deviceName,
      address: p.conn.address,
      type: p.conn.type,
      conn: p.conn,
    );
    _session = session;

    if (old != null) {
      final oldConn = old.conn;
      if (oldConn != null && oldConn != p.conn) {
        _send(
          oldConn,
          RemoteMessage.error(
            ErrorCodes.sessionReplaced,
            'Another Controller took over this Player.',
            sessionId: old.sessionId,
          ),
        );
        _closeConn(oldConn, CloseCodes.sessionReplaced, 'session_replaced');
      }
      _safe(() => store?.setActive(old.sessionId, false));
    }

    () async {
      await _safe(() async {
        await store?.upsert(
          sessionId: session.sessionId,
          controllerName: session.controllerName,
          controllerAddress: session.address,
          connectionType: session.type.name,
        );
        // Accepting a Controller also trusts it: it can come back without
        // pairing until the Player user forgets it.
        await store?.trust(sessionId: session.sessionId, token: session.token);
      });
      await _refreshTrusted();
      _publish();
    }();

    _send(
      p.conn,
      RemoteMessage(
        type: MessageType.pairingResult,
        requestId: p.codeRequestId,
        sessionId: session.sessionId,
        payload: {
          'status': PairingStatus.accepted,
          'sessionId': session.sessionId,
          'token': session.token,
          'playerName': deviceName,
        },
      ),
    );
    _sendState(p.conn, session);
    _publish();
  }

  // ------------------------------------------------------------------ commands

  /// Checks the session token for an authenticated request. On failure it
  /// sends the right error and returns null.
  _Session? _authorize(_Conn conn, RemoteMessage msg) {
    final s = _session;
    if (s == null || msg.token == null) {
      _send(
        conn,
        RemoteMessage.error(
          ErrorCodes.notPaired,
          'Pair with this Player before sending commands.',
          requestId: msg.requestId,
        ),
      );
      return null;
    }
    if (msg.sessionId != s.sessionId ||
        !_tokenEquals(msg.token!, s.token) ||
        s.conn != conn) {
      _send(
        conn,
        RemoteMessage.error(
          ErrorCodes.invalidSession,
          'This session is no longer valid. Pair again.',
          requestId: msg.requestId,
        ),
      );
      return null;
    }
    return s;
  }

  Future<void> _onCommand(_Conn conn, RemoteMessage msg) async {
    final s = _authorize(conn, msg);
    if (s == null) return;

    final action = msg.payload['action'];
    final Map<String, dynamic> extra;
    try {
      extra = await _execute(action, msg.payload, conn);
    } on PlaybackException catch (e) {
      _send(
        conn,
        RemoteMessage.error(e.code, e.message,
            requestId: msg.requestId, sessionId: s.sessionId),
      );
      return;
    } catch (_) {
      _send(
        conn,
        RemoteMessage.error(
          ErrorCodes.internalError,
          'Something went wrong on the Player.',
          requestId: msg.requestId,
          sessionId: s.sessionId,
        ),
      );
      return;
    }

    _send(
      conn,
      RemoteMessage(
        type: MessageType.commandResult,
        requestId: msg.requestId,
        sessionId: s.sessionId,
        payload: {'action': action, 'ok': true, ...extra},
      ),
    );
    _sendState(conn, s); // Full state after every successful command (FR-64).
  }

  /// Runs one command. Returns extra data for the `command_result` payload.
  Future<Map<String, dynamic>> _execute(
    Object? action,
    Map<String, dynamic> p,
    _Conn conn,
  ) async {
    switch (action) {
      case RemoteActions.play:
        await engine.play();
      case RemoteActions.pause:
        await engine.pause();
      case RemoteActions.setSleepTimer:
        final m = p['minutes'];
        if (m is! num || m < 0 || m > 720) {
          throw PlaybackException(ErrorCodes.invalidAction,
              'The sleep timer needs minutes from 0 to 720.');
        }
        _setSleepTimer(m == 0 ? null : Duration(minutes: m.toInt()));
      case RemoteActions.groupCalibrate:
        final gs = _session;
        if (gs == null || gs.conn != conn || !gs.group) {
          throw PlaybackException(ErrorCodes.invalidAction,
              'Switch on "Play on this phone too" before Auto-align.');
        }
        switch (p['step']) {
          case 'start':
            await _startCalibration();
          case 'mutePlayer':
            await _muteForCalibration(true);
          case 'unmutePlayer':
            await _muteForCalibration(false);
          case 'end':
            await _endCalibration();
          default:
            throw PlaybackException(ErrorCodes.invalidAction,
                'step must be start, mutePlayer, unmutePlayer or end.');
        }
      case RemoteActions.groupJoin:
        final s = _session;
        if (p['enabled'] is! bool) {
          throw PlaybackException(
              ErrorCodes.invalidAction, 'groupJoin needs enabled: true or false.');
        }
        if (s == null || s.conn != conn) {
          throw PlaybackException(ErrorCodes.invalidSession, 'Pair first.');
        }
        if (p['enabled'] == true && conn.type != ConnectionType.local) {
          throw PlaybackException(ErrorCodes.invalidAction,
              'Playing on two phones needs the local network (the same Wi-Fi). '
              'The internet is too slow and uneven to keep them in step.');
        }
        s.group = p['enabled'] as bool;
        _updateGroupTimer();
        _publish();
      case RemoteActions.setSpeed:
        final v = p['speed'];
        if (v is! num || v.isNaN || v < 0.5 || v > 2.0) {
          throw PlaybackException(
              ErrorCodes.invalidAction, 'Speed must be between 0.5 and 2.');
        }
        await _queueEngine.setSpeed(v.toDouble());
      case RemoteActions.setFavorite:
        if (p['favorite'] is! bool) {
          throw PlaybackException(
              ErrorCodes.invalidAction, 'setFavorite needs favorite: true or false.');
        }
        await _library.setFavorite(_requiredInt(p, 'songId'), p['favorite'] as bool);
      case RemoteActions.saveQueueAsPlaylist:
        final name = p['name'];
        if (name is! String) {
          throw PlaybackException(ErrorCodes.invalidAction, 'Give the playlist a name.');
        }
        final lib = _library;
        final saved = await saveQueueAsPlaylist(
          queue: _queueEngine.queueSnapshot(),
          name: name,
          createPlaylist: lib.createPlaylist,
          addToPlaylist: lib.addToPlaylist,
          deletePlaylist: lib.deletePlaylist,
        );
        return {
          'playlistId': saved.playlistId,
          'added': saved.added,
          'skipped': saved.skipped,
        };
      case RemoteActions.createPlaylist:
        final name = p['name'];
        if (name is! String) {
          throw PlaybackException(ErrorCodes.invalidAction, 'Give the playlist a name.');
        }
        return {'playlistId': await _library.createPlaylist(name)};
      case RemoteActions.renamePlaylist:
        final name = p['name'];
        if (name is! String) {
          throw PlaybackException(ErrorCodes.invalidAction, 'Give the playlist a name.');
        }
        if (!await _library.renamePlaylist(_requiredInt(p, 'playlistId'), name)) {
          throw _noPlaylist();
        }
      case RemoteActions.deletePlaylist:
        if (!await _library.deletePlaylist(_requiredInt(p, 'playlistId'))) {
          throw _noPlaylist();
        }
      case RemoteActions.addToPlaylist:
        final added =
            await _library.addToPlaylist(_requiredInt(p, 'playlistId'), _songIds(p));
        if (added == null) throw _noPlaylist();
        return {'added': added};
      case RemoteActions.removeFromPlaylist:
        await _library.removeFromPlaylist(
            _requiredInt(p, 'playlistId'), _requiredInt(p, 'songId'));
      case RemoteActions.getLyrics:
        final l = await _library.lyrics(_requiredInt(p, 'songId'));
        return {'lyrics': l.toJson()};
      case RemoteActions.getArt:
        final size = p['size'] is num ? (p['size'] as num).toInt() : 256;
        final bytes =
            await _library.artThumbnail(_requiredInt(p, 'songId'), size: size);
        return bytes == null ? const {} : {'art': base64Encode(bytes)};
      case RemoteActions.toggle:
        await engine.toggle();
      case RemoteActions.next:
        await engine.next();
      case RemoteActions.previous:
        await engine.previous();
      case RemoteActions.stop:
        await engine.stop();
      case RemoteActions.seek:
        final pos = p['positionSeconds'];
        if (pos is! num) {
          throw PlaybackException(
              ErrorCodes.invalidPosition, 'Seek needs positionSeconds.');
        }
        await engine.seek(pos.toInt());
      case RemoteActions.setVolume:
        final v = p['volume'];
        if (v is! num) {
          throw PlaybackException(
              ErrorCodes.invalidAction, 'setVolume needs a volume from 0 to 1.');
        }
        await engine.setVolume(v.toDouble());

      // ---- Phase 5: control another music app on this phone ----
      case RemoteActions.setControlMode:
        final switcher = engine is ControlModeCapable
            ? engine as ControlModeCapable
            : null;
        if (switcher == null) {
          throw PlaybackException(
            ErrorCodes.invalidAction,
            "This Player can't control other apps.",
          );
        }
        final mode = ControlMode.values.where((m) => m.name == p['mode']);
        if (mode.isEmpty) {
          throw PlaybackException(
              ErrorCodes.invalidAction, "Mode must be 'local' or 'external'.");
        }
        await switcher.setControlMode(mode.first);

      // ---- Phase 3: internet audio ----
      case RemoteActions.playUrl:
        final url = p['url'];
        if (url is! String) {
          throw PlaybackException(
              ErrorCodes.invalidUrl, 'Send a link to an audio file.');
        }
        String? text(String k) {
          final v = p[k];
          return v is String && v.length <= 200 ? v : null;
        }
        // Licence and artwork links are shown later (queue, history), so only
        // links on creativecommons.org / jamendo.com are kept.
        String? link(String k) {
          final v = p[k];
          return v is String && v.length <= 500 ? v : null;
        }
        final license = creativeCommonsUrl(link('license'));
        final art = jamendoHttpsUrl(link('art'));
        // `queue: true` adds it to the end of the queue instead of playing it.
        if (p['queue'] == true) {
          await _queueEngine.enqueueUrl(url,
              title: text('title'),
              artist: text('artist'),
              album: text('album'),
              licenseUrl: license,
              imageUrl: art);
        } else {
          await _queueEngine.playUrl(url,
              title: text('title'),
              artist: text('artist'),
              album: text('album'),
              licenseUrl: license,
              imageUrl: art);
        }

      // ---- Online Library history (the link never leaves the Player) ----
      case RemoteActions.playHistory:
        final entry = await _library.historySong(_requiredInt(p, 'historyId'));
        if (entry == null) {
          throw PlaybackException(
              ErrorCodes.invalidAction, 'That track is no longer in the history.');
        }
        if (p['queue'] == true) {
          await _queueEngine.enqueueUrl(entry.url!,
              title: entry.title,
              artist: entry.artist,
              album: entry.album,
              licenseUrl: entry.licenseUrl,
              imageUrl: entry.imageUrl);
        } else {
          await _queueEngine.playUrl(entry.url!,
              title: entry.title,
              artist: entry.artist,
              album: entry.album,
              licenseUrl: entry.licenseUrl,
              imageUrl: entry.imageUrl);
        }
      case RemoteActions.removeHistory:
        await _library.removeHistory(_requiredInt(p, 'historyId'));
      case RemoteActions.clearHistory:
        await _library.clearHistory();
      case RemoteActions.setHistoryEnabled:
        if (p['enabled'] is! bool) {
          throw PlaybackException(ErrorCodes.invalidAction,
              'setHistoryEnabled needs enabled: true or false.');
        }
        await _library.setHistoryEnabled(p['enabled'] as bool);

      // ---- Phase 2: queue and library (need a queue-aware engine) ----
      case RemoteActions.playSong:
        final ids = _songIds(p);
        final songs = await _playable(ids);
        if (p['keepQueue'] == true) {
          // Play now, but leave the rest of the queue alone.
          await _queueEngine.playNow(songs);
          return const {};
        }
        final startId = p['songId'] is num ? (p['songId'] as num).toInt() : null;
        final start = startId == null
            ? 0
            : songs.indexWhere((s) => s.id == startId).clamp(0, songs.length - 1);
        await _queueEngine.playSongs(songs, startIndex: start);
      case RemoteActions.queueSong:
        final songs = await _playable(_songIds(p));
        await _queueEngine.enqueue(songs, playNext: p['playNext'] == true);
      case RemoteActions.getQueue:
        var snapshot = _queueEngine.queueSnapshot();
        // The online relay limits message size, so very long queues are cut
        // (the Controller is told the real total).
        if (conn.type == ConnectionType.online &&
            snapshot.items.length > maxOnlineQueueItems) {
          snapshot = snapshot.truncated(maxOnlineQueueItems);
        }
        return {'queue': snapshot.toJson()};
      case RemoteActions.removeQueueItem:
        await _queueEngine.removeQueueItem(_requiredInt(p, 'queueItemId'));
      case RemoteActions.moveQueueItem:
        await _queueEngine.moveQueueItem(
          _requiredInt(p, 'queueItemId'),
          _requiredInt(p, 'newIndex'),
        );
      case RemoteActions.clearQueue:
        await _queueEngine.clearQueue();
      case RemoteActions.playQueueItem:
        await _queueEngine.playQueueItem(_requiredInt(p, 'queueItemId'));
      case RemoteActions.setRepeatMode:
        final mode = RepeatMode.values.where((m) => m.name == p['mode']);
        if (mode.isEmpty) {
          throw PlaybackException(
              ErrorCodes.invalidAction, 'Repeat mode must be off, one or queue.');
        }
        await _queueEngine.setRepeatMode(mode.first);
      case RemoteActions.setShuffle:
        if (p['enabled'] is! bool) {
          throw PlaybackException(
              ErrorCodes.invalidAction, 'setShuffle needs enabled: true or false.');
        }
        await _queueEngine.setShuffle(p['enabled'] as bool);
      default:
        throw PlaybackException(
          ErrorCodes.invalidAction,
          "The action '$action' isn't supported.",
        );
    }
    return const {};
  }

  PlayerLibrary get _library {
    final lib = library;
    if (lib == null) {
      throw PlaybackException(
          ErrorCodes.invalidAction, 'This Player has no music library.');
    }
    return lib;
  }

  PlaybackException _noPlaylist() => PlaybackException(
      ErrorCodes.invalidAction, 'That playlist no longer exists.');

  QueueAwareEngine get _queueEngine {
    final e = engine;
    if (e is QueueAwareEngine) return e;
    throw PlaybackException(
      ErrorCodes.invalidAction,
      "This Player doesn't support a queue.",
    );
  }

  static const _maxIdsPerCommand = 2000;

  /// Longest queue sent over the online relay (~50 KB, well under its limit).
  static const maxOnlineQueueItems = 250;

  /// `songIds` (a list) or a single `songId`.
  List<int> _songIds(Map<String, dynamic> p) {
    final raw = p['songIds'];
    final List<int> ids;
    if (raw is List) {
      ids = [for (final e in raw) if (e is num) e.toInt()];
    } else if (p['songId'] is num) {
      ids = [(p['songId'] as num).toInt()];
    } else {
      ids = const [];
    }
    if (ids.isEmpty) {
      throw PlaybackException(
          ErrorCodes.invalidAction, 'Choose at least one song.');
    }
    if (ids.length > _maxIdsPerCommand) {
      throw PlaybackException(ErrorCodes.invalidAction,
          'Too many songs at once (limit $_maxIdsPerCommand).');
    }
    return ids;
  }

  Future<List<PlayableSong>> _playable(List<int> ids) async {
    final lib = library;
    if (lib == null) {
      throw PlaybackException(
          ErrorCodes.invalidAction, "This Player has no music library.");
    }
    final songs = await lib.playableByIds(ids);
    if (songs.isEmpty) {
      throw PlaybackException(
        ErrorCodes.fileNotFound,
        "Those songs are no longer in the Player's library.",
      );
    }
    return songs;
  }

  int _requiredInt(Map<String, dynamic> p, String key) {
    final v = p[key];
    if (v is! num) {
      throw PlaybackException(ErrorCodes.invalidAction, 'Missing $key.');
    }
    return v.toInt();
  }

  // ------------------------------------------------------------------- library

  Future<void> _onLibraryRequest(_Conn conn, RemoteMessage msg) async {
    final s = _authorize(conn, msg);
    if (s == null) return;
    final lib = library;
    if (lib == null) {
      _send(
        conn,
        RemoteMessage.error(
          ErrorCodes.invalidAction,
          'This Player has no music library.',
          requestId: msg.requestId,
          sessionId: s.sessionId,
        ),
      );
      return;
    }

    final p = msg.payload;
    String? text(String key) {
      final v = p[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    final query = text('query') ?? '';
    final offset = p['offset'] is num ? max(0, (p['offset'] as num).toInt()) : 0;
    final limit =
        p['limit'] is num ? (p['limit'] as num).toInt().clamp(1, 100) : 50;
    final scope = p['scope'];

    try {
      final Map<String, dynamic> body;
      switch (scope) {
        case LibraryScope.songs:
          final page = await lib.songs(
            query: query,
            artist: text('artist'),
            album: text('album'),
            view: text('view'),
            playlistId: p['playlistId'] is num ? (p['playlistId'] as num).toInt() : null,
            folderId: p['folderId'] is num ? (p['folderId'] as num).toInt() : null,
            groupKind: text('groupKind'),
            groupValue: text('groupValue'),
            offset: offset,
            limit: limit,
          );
          body = _pageJson(page, (RemoteSong e) => e.toJson());
        case LibraryScope.folderRoot:
          final root = await lib.folderRoot();
          body = _pageJson(
              LibraryPage(items: [if (root != null) root], total: root == null ? 0 : 1, offset: 0),
              (RemoteFolder e) => e.toJson());
        case LibraryScope.folderChildren:
          final page = await lib.folderChildren(
            parentId: p['parentId'] is num ? (p['parentId'] as num).toInt() : null,
            query: query,
            offset: offset,
            limit: limit,
          );
          body = _pageJson(page, (RemoteFolder e) => e.toJson());
        case LibraryScope.groups:
          final page = await lib.groups(
              kind: text('kind') ?? '', query: query, offset: offset, limit: limit);
          body = _pageJson(page, (RemoteGroup e) => e.toJson());
        case LibraryScope.folders:
          final page = await lib.folders(query: query, offset: offset, limit: limit);
          body = _pageJson(page, (RemoteFolder e) => e.toJson());
        case LibraryScope.playlists:
          final page = await lib.playlists(query: query, offset: offset, limit: limit);
          body = _pageJson(page, (RemotePlaylist e) => e.toJson());
        case LibraryScope.onlineHistory:
          final page = await lib.onlineHistory(offset: offset, limit: limit);
          body = {
            ..._pageJson(page, (RemoteHistoryItem e) => e.toJson()),
            // So the screen can show the on/off switch in the right position.
            'enabled': await lib.historyEnabled(),
          };
        case LibraryScope.artists:
          final page = await lib.artists(query: query, offset: offset, limit: limit);
          body = _pageJson(page, (RemoteArtist e) => e.toJson());
        case LibraryScope.albums:
          final page = await lib.albums(
            query: query,
            artist: text('artist'),
            offset: offset,
            limit: limit,
          );
          body = _pageJson(page, (RemoteAlbum e) => e.toJson());
        default:
          _send(
            conn,
            RemoteMessage.error(
              ErrorCodes.invalidAction,
              'Library scope must be songs, artists, albums, folders, playlists or onlineHistory.',
              requestId: msg.requestId,
              sessionId: s.sessionId,
            ),
          );
          return;
      }
      _send(
        conn,
        RemoteMessage(
          type: MessageType.libraryResponse,
          requestId: msg.requestId,
          sessionId: s.sessionId,
          payload: {'scope': scope, ...body},
        ),
      );
    } catch (_) {
      _send(
        conn,
        RemoteMessage.error(
          ErrorCodes.internalError,
          "The library couldn't be read.",
          requestId: msg.requestId,
          sessionId: s.sessionId,
        ),
      );
    }
  }

  Map<String, dynamic> _pageJson<T>(
    LibraryPage<T> page,
    Map<String, dynamic> Function(T) toJson,
  ) =>
      {
        'total': page.total,
        'offset': page.offset,
        'items': [for (final e in page.items) toJson(e)],
      };

  // ------------------------------------------------------------------- helpers

  /// Makes a fresh QR ticket (10 symbols, ~50 bits) and schedules the next one.
  void _newTicket() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    _ticket = String.fromCharCodes(List.generate(
        10, (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length))));
    _ticketTimer?.cancel();
    _ticketTimer = Timer(ticketTtl, () {
      _newTicket();
      _publish();
    });
    if (_running) _publish();
  }

  String _newCode() => _random.nextInt(1000000).toString().padLeft(6, '0');

  String _newToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Constant-time string comparison.
  bool _tokenEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<List<String>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLinkLocal) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// An Auto-align test in progress on the Player.
class _Calibration {
  _Calibration(this.file, this.savedVolume);

  final File file;

  /// The Player's volume before the test, put back afterwards.
  final double savedVolume;
  Timer? watchdog;

  /// What was playing before the test: its queue entry, position and whether
  /// it was playing, so it can be put back.
  int? origItemId;
  int origPositionSeconds = 0;
  bool wasPlaying = false;
}
