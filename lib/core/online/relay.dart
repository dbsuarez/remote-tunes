import 'dart:convert';

/// A message crossing the online relay. The relay is a broadcast channel (every
/// participant in a room hears every frame), so each frame says who sent it and
/// who it is for. [message] is a [RemoteMessage] as JSON text, unchanged from
/// the local protocol.
class RelayFrame {
  const RelayFrame({required this.from, required this.to, required this.message});

  /// Sender: [RelayPeers.player] or a Controller's peer id.
  final String from;

  /// Receiver: [RelayPeers.player] or a Controller's peer id.
  final String to;
  final String message;

  Map<String, dynamic> toPayload() => {'v': 1, 'from': from, 'to': to, 'm': message};

  /// Tolerant parser. Accepts the bare payload or one nested under `payload`
  /// (how Supabase delivers broadcasts). Returns null for anything that is not
  /// a valid frame, so junk from other participants is ignored.
  static RelayFrame? fromPayload(Object? raw) {
    if (raw is! Map) return null;
    var map = Map<String, dynamic>.from(raw);
    if (map['m'] == null && map['payload'] is Map) {
      map = Map<String, dynamic>.from(map['payload'] as Map);
    }
    final from = map['from'];
    final to = map['to'];
    final m = map['m'];
    if (from is! String || to is! String || m is! String) return null;
    if (from.isEmpty || to.isEmpty || from.length > 64 || to.length > 64) return null;
    return RelayFrame(from: from, to: to, message: m);
  }

  /// Approximate size on the wire.
  int get approxBytes => utf8.encode(message).length + from.length + to.length + 32;
}

class RelayPeers {
  RelayPeers._();

  /// The Player's fixed address in a room.
  static const player = 'player';
}

enum RelayStatus { connected, closed, error }

class RelayException implements Exception {
  RelayException(this.message);

  /// Plain-language reason.
  final String message;

  @override
  String toString() => 'RelayException: $message';
}

/// One participant's connection to a room on the relay. The real
/// implementation wraps a Supabase Realtime channel; tests use an in-memory
/// hub.
abstract class RelayChannel {
  /// Joins the room. Completes when subscribed; throws [RelayException] with a
  /// readable reason if it cannot (no internet, bad keys, timeout).
  Future<void> join();

  /// Frames sent by *other* participants (a participant never hears itself).
  Stream<RelayFrame> get frames;

  /// Connection changes after [join].
  Stream<RelayStatus> get status;

  Future<void> send(RelayFrame frame);
  Future<void> leave();
}

/// Creates a channel for a room code.
typedef RelayChannelFactory = RelayChannel Function(String roomCode);

/// Frames larger than this are not sent (Supabase limits message size).
const int maxRelayFrameBytes = 200 * 1024;
