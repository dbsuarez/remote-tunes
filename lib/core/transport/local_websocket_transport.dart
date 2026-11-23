import 'dart:async';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../protocol/protocol.dart';
import 'remote_transport.dart';

/// Controller-side local WebSocket transport (Android/desktop, uses dart:io).
class LocalWebSocketTransport implements RemoteTransport {
  LocalWebSocketTransport({
    required this.host,
    required this.port,
    this.connectTimeout = const Duration(seconds: 5),
  });

  final String host;
  final int port;
  final Duration connectTimeout;

  WebSocketChannel? _channel;
  final StreamController<RemoteMessage> _messages = StreamController();

  @override
  Stream<RemoteMessage> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    final Uri uri;
    try {
      uri = Uri(scheme: 'ws', host: host, port: port);
    } on FormatException {
      throw TransportException('That address is not valid.');
    }
    final channel = IOWebSocketChannel.connect(uri, connectTimeout: connectTimeout);
    try {
      await channel.ready;
    } catch (_) {
      throw TransportException(
          "Couldn't reach $host:$port. Check the address and that both phones are on the same network.");
    }
    _channel = channel;
    channel.stream.listen(
      (raw) {
        try {
          _messages.add(RemoteMessage.decode(raw));
        } on ProtocolException {
          // Ignore malformed frames; the spec says unknown input is ignored.
        }
      },
      onDone: _closeMessages,
      onError: (_) => _closeMessages(),
      cancelOnError: true,
    );
  }

  void _closeMessages() {
    if (!_messages.isClosed) _messages.close();
  }

  @override
  Future<void> send(RemoteMessage message) async {
    final channel = _channel;
    if (channel == null) {
      throw TransportException('Not connected.');
    }
    channel.sink.add(message.encode());
  }

  @override
  Future<void> disconnect({bool intentional = true}) async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.sink
            .close(
              intentional
                  ? CloseCodes.controllerDisconnected
                  : CloseCodes.connectionLost,
              intentional ? 'controller_disconnect' : 'connection_lost',
            )
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Peer may already be gone.
      }
    }
    _closeMessages();
  }
}
