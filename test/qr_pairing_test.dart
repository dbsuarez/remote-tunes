import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

Future<void> waitFor(bool Function() c, {String? reason}) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late PlayerServer server;
  late ControllerClient client;

  setUp(() async {
    server = PlayerServer(
      engine: SimulatedPlaybackEngine(autoTick: false),
      deviceName: 'Test Player',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    await server.start();
    client = ControllerClient(
      transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p),
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
  });

  test('the Player offers a ticket', () {
    expect(server.current.pairingTicket, isNotNull);
    expect(server.current.pairingTicket!.length, 10);
  });

  test('a scanned ticket replaces typing: only Accept is needed', () async {
    final ticket = server.current.pairingTicket!;
    await client.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        deviceName: 'Scanner',
        pairingTicket: ticket);
    await waitFor(() => server.current.pending?.codeVerified ?? false,
        reason: 'ticket verified');
    server.acceptPairing();
    await waitFor(() => client.current.isConnected, reason: 'connected');
    // used once: the ticket changed
    expect(server.current.pairingTicket, isNot(ticket));
  });

  test('a wrong ticket falls back to typing the code', () async {
    await client.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        deviceName: 'Scanner',
        pairingTicket: 'WRONGWRONG');
    await waitFor(() => client.current.message != null, reason: 'message');
    expect(client.current.status, ControllerStatus.awaitingCode);
    final code = server.current.pending!.code;
    server.acceptPairing();
    await client.submitCode(code);
    await waitFor(() => client.current.isConnected, reason: 'connected');
  });
}
