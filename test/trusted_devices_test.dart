import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/paired_controllers_store.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/controller/trusted_players.dart';
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
  late AppDatabase db;
  late PlayerServer server;
  final clients = <ControllerClient>[];

  Future<void> startServer() async {
    server = PlayerServer(
      engine: SimulatedPlaybackEngine(autoTick: false),
      deviceName: 'Test Player',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      store: DriftPairedControllersStore(db),
    );
    await server.start();
  }

  ControllerClient newClient() {
    final c = ControllerClient(
      transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p),
    );
    clients.add(c);
    return c;
  }

  Future<TrustedPlayer> pairOnce() async {
    final c = newClient();
    await c.connect(host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    final code = server.current.pending!.code;
    server.acceptPairing();
    await c.submitCode(code);
    await waitFor(() => c.current.isConnected, reason: 'paired');
    final t = c.trustedPlayer!;
    await c.disconnect(); // leaving ends the session but keeps the trust
    await waitFor(() => server.current.controller == null, reason: 'left');
    return t;
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await startServer();
  });

  tearDown(() async {
    for (final c in clients) {
      await c.dispose();
    }
    clients.clear();
    await server.stop();
    await db.close();
  });

  test('a paired Controller is trusted and can come back without pairing', () async {
    final t = await pairOnce();
    expect(server.current.trusted.single.name, 'Phone');

    final c = newClient();
    await c.resumeTrusted(player: t.copyWith(port: server.current.port), deviceName: 'Phone');
    await waitFor(() => c.current.isConnected, reason: 'resumed');
    expect(server.current.pending, isNull);
    expect(server.current.controller?.connected, isTrue);
  });

  test('still trusted after the Player restarts', () async {
    final t = await pairOnce();
    await server.stop();
    await startServer(); // same database, new process in real life

    final c = newClient();
    await c.resumeTrusted(player: t.copyWith(port: server.current.port), deviceName: 'Phone');
    await waitFor(() => c.current.isConnected, reason: 'resumed after restart');
  });

  test('forgetting a trusted Controller makes it pair again', () async {
    final t = await pairOnce();
    await server.forgetTrusted(t.sessionId);
    expect(server.current.trusted, isEmpty);

    final c = newClient();
    await c.resumeTrusted(player: t.copyWith(port: server.current.port), deviceName: 'Phone');
    expect(c.current.status, ControllerStatus.disconnected);
    expect(c.current.sessionInvalid, isTrue);
  });

  test('a wrong token is not trusted', () async {
    final t = await pairOnce();
    final bad = TrustedPlayer(
      sessionId: t.sessionId,
      token: 'not-the-token',
      peerId: t.peerId,
      name: t.name,
      host: '127.0.0.1',
      port: server.current.port,
      lastUsed: DateTime.now(),
    );
    final c = newClient();
    await c.resumeTrusted(player: bad, deviceName: 'Phone');
    expect(c.current.sessionInvalid, isTrue);
  });

  test('only a hash of the token is stored on the Player', () async {
    final t = await pairOnce();
    final found = await DriftPairedControllersStore(db).findTrusted(t.sessionId);
    expect(found!.tokenHash, isNot(t.token));
    expect(found.tokenHash, hashToken(t.token));
  });

  test('trusted Players are saved and read back on the phone', () async {
    final tp = TrustedPlayer(
      sessionId: 's1',
      token: 'tok',
      peerId: 'c-1',
      name: 'Kitchen',
      host: '10.0.0.5',
      port: 8765,
      roomCode: 'ABCDEFGH',
      lastUsed: DateTime(2026, 1, 1),
    );
    final back = TrustedPlayer.fromJson(tp.toJson())!;
    expect(back.token, 'tok');
    expect(back.host, '10.0.0.5');
    expect(back.roomCode, 'ABCDEFGH');
    expect(TrustedPlayer.fromJson({'sessionId': 'x'}), isNull);
  });
}
