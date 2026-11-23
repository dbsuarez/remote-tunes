import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/models/enums.dart';

/// One Controller's connection to the Player, however it arrives: a local
/// WebSocket, or a peer on the online relay. The server's pairing, session and
/// command logic only sees this interface.
abstract class ServerChannel {
  /// Text frames from the Controller. Completes when the connection ends.
  Stream<dynamic> get incoming;

  void send(String frame);

  /// Closes with a protocol close code (see `CloseCodes`).
  Future<void> close(int code, String reason);

  /// Close code once closed (null if unknown).
  int? get closeCode;

  /// Shown to the user: an IP address for local, "Online" for the relay.
  String get address;

  ConnectionType get type;
}

class WebSocketServerChannel implements ServerChannel {
  WebSocketServerChannel(this._channel, this.address);

  final WebSocketChannel _channel;

  @override
  final String address;

  @override
  Stream<dynamic> get incoming => _channel.stream;

  @override
  void send(String frame) => _channel.sink.add(frame);

  @override
  Future<void> close(int code, String reason) =>
      _channel.sink.close(code, reason);

  @override
  int? get closeCode => _channel.closeCode;

  @override
  ConnectionType get type => ConnectionType.local;
}
