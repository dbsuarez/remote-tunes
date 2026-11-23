import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/online/relay.dart';
import '../../core/online/room_code.dart';
import '../../core/protocol/protocol.dart';
import '../../core/transport/remote_transport.dart';

/// Controller side of the online relay: the same [RemoteTransport] interface as
/// the local WebSocket, so [ControllerClient] works over either.
class OnlineTransport implements RemoteTransport {
  OnlineTransport({
    required RelayChannelFactory channelFactory,
    required String roomCode,
    String? peerId,
    this.joinTimeout = const Duration(seconds: 12),
  })  : _factory = channelFactory,
        roomCode = RoomCode.normalize(roomCode),
        peerId = peerId ?? generatePeerId();

  final RelayChannelFactory _factory;
  final String roomCode;

  /// This Controller's address in the room. Kept stable across reconnects so
  /// the Player recognises it when it resumes its session.
  final String peerId;
  final Duration joinTimeout;

  RelayChannel? _channel;
  StreamSubscription<RelayFrame>? _frameSub;
  StreamSubscription<RelayStatus>? _statusSub;
  final StreamController<RemoteMessage> _messages = StreamController();

  static String generatePeerId() => 'c-${const Uuid().v4().substring(0, 8)}';

  @override
  Stream<RemoteMessage> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    final problem = RoomCode.problem(roomCode);
    if (problem != null) throw TransportException(problem);

    final channel = _factory(roomCode);
    try {
      await channel.join().timeout(joinTimeout);
    } on RelayException catch (e) {
      await _quietLeave(channel);
      throw TransportException(e.message);
    } on TimeoutException {
      await _quietLeave(channel);
      throw TransportException(
          'The online relay took too long to answer. Check your internet connection.');
    } catch (_) {
      await _quietLeave(channel);
      throw TransportException("Couldn't connect to the online relay.");
    }

    _channel = channel;
    _frameSub = channel.frames.listen((f) {
      if (f.to != peerId || f.from != RelayPeers.player) return;
      try {
        _messages.add(RemoteMessage.decode(f.message));
      } on ProtocolException {
        // Ignore malformed messages.
      }
    });
    // A lost relay connection ends the message stream, which is how the
    // client notices and starts reconnecting.
    _statusSub = channel.status.listen((s) {
      if (s != RelayStatus.connected) _closeMessages();
    });
  }

  void _closeMessages() {
    if (!_messages.isClosed) _messages.close();
  }

  @override
  Future<void> send(RemoteMessage message) async {
    final channel = _channel;
    if (channel == null) throw TransportException('Not connected.');
    final frame = RelayFrame(
      from: peerId,
      to: RelayPeers.player,
      message: message.encode(),
    );
    if (frame.approxBytes > maxRelayFrameBytes) {
      throw TransportException('That message is too large for the online relay.');
    }
    try {
      await channel.send(frame);
    } on RelayException catch (e) {
      throw TransportException(e.message);
    }
  }

  @override
  Future<void> disconnect({bool intentional = true}) async {
    final channel = _channel;
    _channel = null;
    await _frameSub?.cancel();
    await _statusSub?.cancel();
    _frameSub = null;
    _statusSub = null;
    if (channel != null) {
      if (intentional) {
        // The relay has no socket close code, so tell the Player explicitly.
        try {
          await channel
              .send(RelayFrame(
                from: peerId,
                to: RelayPeers.player,
                message: const RemoteMessage(type: MessageType.bye).encode(),
              ))
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      await _quietLeave(channel);
    }
    _closeMessages();
  }

  Future<void> _quietLeave(RelayChannel channel) async {
    try {
      await channel.leave().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
