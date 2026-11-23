import 'dart:async';

import '../../core/models/enums.dart';
import '../../core/online/relay.dart';
import '../player/server/server_channel.dart';
import 'online_status.dart';

/// Player side of the online relay: joins the room and turns each Controller
/// that talks to it into a [ServerChannel], so the Player's pairing, session and
/// command logic works exactly as it does for local sockets.
///
/// It keeps the room joined: if the relay drops, it shows "reconnecting" and
/// rebuilds the channel if the connection does not come back by itself.
class OnlineRelayHost {
  OnlineRelayHost({
    required RelayChannelFactory channelFactory,
    required this.roomCode,
    required this.onPeer,
    required this.onStatus,
    this.joinTimeout = const Duration(seconds: 12),
    this.rebuildAfter = const Duration(seconds: 30),
    this.retryDelays = const [
      Duration(seconds: 3),
      Duration(seconds: 6),
      Duration(seconds: 12),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ],
    this.maxPeers = 20,
  }) : _factory = channelFactory;

  final RelayChannelFactory _factory;
  final String roomCode;

  /// A new Controller appeared on the relay.
  final void Function(ServerChannel peer) onPeer;
  final void Function(OnlineRelayInfo info) onStatus;
  final Duration joinTimeout;
  final Duration rebuildAfter;
  final List<Duration> retryDelays;

  /// Most Controllers tracked at once (stops a flood from creating endless
  /// connections).
  final int maxPeers;

  RelayChannel? _channel;
  StreamSubscription<RelayFrame>? _frameSub;
  StreamSubscription<RelayStatus>? _statusSub;
  Timer? _retryTimer;
  Timer? _watchdog;
  bool _stopped = false;
  int _attempt = 0;
  final Map<String, _VirtualPeer> _peers = {};

  /// Peers currently tracked (for tests).
  int get peerCount => _peers.length;

  /// Joins the room. Completes after the first attempt; if it failed, retries
  /// continue in the background.
  Future<void> start() async {
    _stopped = false;
    await _connect(first: true);
  }

  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _watchdog?.cancel();
    for (final p in _peers.values.toList()) {
      p._closeFromHost();
    }
    _peers.clear();
    await _dropChannel();
  }

  void _emit(OnlinePhase phase, [String? error]) {
    if (_stopped) return;
    onStatus(OnlineRelayInfo(roomCode: roomCode, phase: phase, error: error));
  }

  Future<void> _connect({bool first = false}) async {
    if (_stopped) return;
    _emit(first && _attempt == 0 ? OnlinePhase.connecting : OnlinePhase.reconnecting);
    final channel = _factory(roomCode);
    try {
      await channel.join().timeout(joinTimeout);
    } on RelayException catch (e) {
      await _giveUp(channel, e.message);
      return;
    } on TimeoutException {
      await _giveUp(channel,
          'The online relay took too long to answer. Check the internet connection.');
      return;
    } catch (_) {
      await _giveUp(channel, "Couldn't connect to the online relay.");
      return;
    }
    if (_stopped) {
      await channel.leave();
      return;
    }
    _attempt = 0;
    _retryTimer?.cancel();
    _channel = channel;
    _frameSub = channel.frames.listen(_onFrame);
    _statusSub = channel.status.listen(_onChannelStatus);
    _emit(OnlinePhase.connected);
  }

  Future<void> _giveUp(RelayChannel channel, String message) async {
    try {
      await channel.leave();
    } catch (_) {}
    if (_stopped) return;
    _emit(OnlinePhase.failed, message);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_stopped) return;
    _retryTimer?.cancel();
    final delay = retryDelays[_attempt.clamp(0, retryDelays.length - 1)];
    _attempt++;
    _retryTimer = Timer(delay, () => _connect());
  }

  void _onChannelStatus(RelayStatus s) {
    if (_stopped) return;
    switch (s) {
      case RelayStatus.connected:
        _watchdog?.cancel();
        _emit(OnlinePhase.connected);
      case RelayStatus.closed:
      case RelayStatus.error:
        _emit(OnlinePhase.reconnecting, 'The online relay connection was lost.');
        // The Realtime client normally rejoins by itself; if it has not within
        // [rebuildAfter], start over with a fresh channel.
        _watchdog?.cancel();
        _watchdog = Timer(rebuildAfter, _rebuild);
    }
  }

  Future<void> _rebuild() async {
    if (_stopped) return;
    await _dropChannel();
    await _connect();
  }

  Future<void> _dropChannel() async {
    await _frameSub?.cancel();
    await _statusSub?.cancel();
    _frameSub = null;
    _statusSub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.leave();
      } catch (_) {}
    }
  }

  void _onFrame(RelayFrame f) {
    if (f.to != RelayPeers.player || f.from == RelayPeers.player) return;
    var peer = _peers[f.from];
    if (peer == null) {
      if (_peers.length >= maxPeers) return;
      peer = _VirtualPeer(this, f.from);
      _peers[f.from] = peer;
      onPeer(peer);
    }
    peer._deliver(f.message);
  }

  void _sendTo(String peerId, String frame) {
    final ch = _channel;
    if (ch == null) return;
    final f = RelayFrame(from: RelayPeers.player, to: peerId, message: frame);
    if (f.approxBytes > maxRelayFrameBytes) return; // would be refused anyway
    ch.send(f).catchError((Object _) {});
  }

  void _removePeer(_VirtualPeer p) {
    if (identical(_peers[p.id], p)) _peers.remove(p.id);
  }
}

/// One Controller on the relay, as seen by the server.
class _VirtualPeer implements ServerChannel {
  _VirtualPeer(this._host, this.id);

  final OnlineRelayHost _host;
  final String id;
  final StreamController<String> _incoming = StreamController<String>();
  int? _closeCode;
  bool _closed = false;

  @override
  Stream<dynamic> get incoming => _incoming.stream;

  @override
  String get address => 'Online';

  @override
  ConnectionType get type => ConnectionType.online;

  @override
  int? get closeCode => _closeCode;

  void _deliver(String message) {
    if (!_closed) _incoming.add(message);
  }

  @override
  void send(String frame) {
    if (_closed) return;
    _host._sendTo(id, frame);
  }

  @override
  Future<void> close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    _closeCode = code;
    _host._removePeer(this);
    await _incoming.close();
  }

  void _closeFromHost() {
    if (_closed) return;
    _closed = true;
    _closeCode = 1001;
    _incoming.close();
  }
}
