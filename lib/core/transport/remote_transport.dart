import '../protocol/protocol.dart';

/// Shared abstraction (docs/02_ARCHITECTURE.md).
///
/// This file must stay free of `dart:io` so the same code can be reused by a
/// future web Controller (docs/17_WEB_CONTROLLER.md). Concrete transports live
/// in their own files:
///  * `local_websocket_transport.dart` (dart:io, Phase 1)
///  * Supabase Realtime transport (Phase 4)
abstract class RemoteTransport {
  Future<void> connect();

  /// Incoming messages. Completes (onDone) when the connection closes.
  Stream<RemoteMessage> get messages;

  Future<void> send(RemoteMessage message);

  /// [intentional] true tells the peer the user chose to disconnect (the
  /// Player then revokes the session); false simulates/handles a lost link.
  Future<void> disconnect({bool intentional = true});
}

class TransportException implements Exception {
  TransportException(this.message);
  final String message;

  @override
  String toString() => 'TransportException: $message';
}
