import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

Future<void> waitFor(bool Function() c, {String? reason}) async {
  final end = DateTime.now().add(const Duration(seconds: 6));
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late SimulatedPlaybackEngine engine;
  late PlayerServer server;
  late ControllerClient c;

  setUp(() async {
    engine = SimulatedPlaybackEngine(autoTick: false);
    server = PlayerServer(
        engine: engine,
        deviceName: 'P',
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4);
    await server.start();
    c = ControllerClient(
        transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p));
    await c.connect(host: '127.0.0.1', port: server.current.port!, deviceName: 'C');
    final code = server.current.pending!.code;
    server.acceptPairing();
    await c.submitCode(code);
    await waitFor(() => c.current.isConnected, reason: 'paired');
  });

  tearDown(() async {
    await c.dispose();
    await server.stop();
  });

  test('the sleep timer is reported to the Controller and can be cancelled', () async {
    await c.setSleepTimer(30);
    await waitFor(() => c.current.playback.sleepTimerSeconds > 1700,
        reason: 'timer reported');
    await c.setSleepTimer(0);
    await waitFor(() => c.current.playback.sleepTimerSeconds == 0,
        reason: 'timer cancelled');
  });

  test('a bad sleep timer is refused', () async {
    expect(() => c.sendCommand('setSleepTimer', {'minutes': -5}),
        throwsA(isA<ControllerException>()));
  });

  test('when it runs out the Player pauses and the timer clears', () async {
    await engine.play();
    expect(engine.state.isPlaying, isTrue);
    server.debugSetSleepTimer(const Duration(milliseconds: 200));
    await waitFor(() => !engine.state.isPlaying, reason: 'paused');
    await waitFor(() => c.current.playback.sleepTimerSeconds == 0,
        reason: 'cleared');
  });
}
