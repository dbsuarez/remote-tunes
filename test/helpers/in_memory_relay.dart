import 'dart:async';

import 'package:remote_tunes/core/online/relay.dart';

/// An in-memory stand-in for the Supabase Realtime relay: a broadcast channel
/// per room where every participant hears every other participant.
class InMemoryRelayHub {
  final Map<String, List<_Member>> _rooms = {};

  /// When true, [RelayChannel.join] fails like a phone with no internet.
  bool offline = false;

  /// Extra delay per frame, to shake out ordering assumptions.
  Duration latency = Duration.zero;

  /// Every frame that crossed the hub (for privacy/size assertions).
  final List<(String room, RelayFrame frame)> log = [];

  /// Frames not delivered (simulates the relay dropping messages).
  bool dropFrames = false;

  RelayChannel channel(String room) => _Member(this, room);

  int membersIn(String room) => _rooms[room]?.length ?? 0;

  /// Simulates the relay closing every connection in [room] (network blip).
  void dropRoom(String room, {RelayStatus status = RelayStatus.closed}) {
    for (final m in List.of(_rooms[room] ?? const <_Member>[])) {
      m._emitStatus(status);
    }
  }

  void _deliver(_Member sender, RelayFrame frame) {
    log.add((sender.room, frame));
    if (dropFrames) return;
    void go() {
      for (final m in List.of(_rooms[sender.room] ?? const <_Member>[])) {
        if (!identical(m, sender)) m._receive(frame);
      }
    }

    if (latency == Duration.zero) {
      scheduleMicrotask(go);
    } else {
      Timer(latency, go);
    }
  }
}

class _Member implements RelayChannel {
  _Member(this._hub, this.room);

  final InMemoryRelayHub _hub;
  final String room;
  final _frames = StreamController<RelayFrame>.broadcast();
  final _status = StreamController<RelayStatus>.broadcast();
  bool _joined = false;

  @override
  Stream<RelayFrame> get frames => _frames.stream;

  @override
  Stream<RelayStatus> get status => _status.stream;

  @override
  Future<void> join() async {
    if (_hub.offline) {
      throw RelayException(
          "Couldn't reach the online relay. Check the internet connection.");
    }
    _hub._rooms.putIfAbsent(room, () => []).add(this);
    _joined = true;
  }

  @override
  Future<void> send(RelayFrame frame) async {
    if (!_joined) throw RelayException('Not connected to the online relay.');
    _hub._deliver(this, frame);
  }

  void _receive(RelayFrame frame) {
    if (!_frames.isClosed) _frames.add(frame);
  }

  void _emitStatus(RelayStatus s) {
    if (!_status.isClosed) _status.add(s);
  }

  @override
  Future<void> leave() async {
    _joined = false;
    _hub._rooms[room]?.remove(this);
    await _frames.close();
    await _status.close();
  }
}
