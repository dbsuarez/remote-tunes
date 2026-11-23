import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/constants.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/paired_controllers_store.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for: ${reason ?? 'condition'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late SimulatedPlaybackEngine engine;
  late PlayerServer server;
  final clients = <ControllerClient>[];
  final transports = <LocalWebSocketTransport>[];

  Future<void> startServer({
    Duration pairingTtl = const Duration(minutes: 5),
    Duration staleTimeout = const Duration(seconds: 15),
    PairedControllersStore? store,
  }) async {
    engine = SimulatedPlaybackEngine(autoTick: false);
    server = PlayerServer(
      engine: engine,
      deviceName: 'Test Player',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      pairingTtl: pairingTtl,
      staleTimeout: staleTimeout,
      store: store,
    );
    await server.start();
    expect(server.current.running, isTrue);
  }

  ControllerClient newClient() {
    final c = ControllerClient(
      transportFactory: (host, port) =>
          LocalWebSocketTransport(host: host, port: port),
      heartbeatInterval: const Duration(milliseconds: 200),
      connectionTimeout: const Duration(seconds: 2),
      reconnectDelays: List.filled(30, const Duration(milliseconds: 100)),
    );
    clients.add(c);
    return c;
  }

  Future<void> pair(ControllerClient c, {String name = 'Test Phone'}) async {
    await c.connect(
        host: '127.0.0.1', port: server.current.port!, deviceName: name);
    expect(c.current.status, ControllerStatus.awaitingCode, reason: c.current.message);
    final code = server.current.pending!.code;
    server.acceptPairing();
    await c.submitCode(code);
    await waitFor(() => c.current.isConnected, reason: 'controller connected');
  }

  Future<LocalWebSocketTransport> rawTransport(List<RemoteMessage> inbox) async {
    final t = LocalWebSocketTransport(host: '127.0.0.1', port: server.current.port!);
    transports.add(t);
    await t.connect();
    t.messages.listen(inbox.add);
    return t;
  }

  RemoteMessage hello({int version = AppConstants.protocolVersion}) => RemoteMessage(
        type: MessageType.hello,
        requestId: 'h1',
        payload: {'protocolVersion': version, 'role': 'controller', 'deviceName': 'Raw'},
      );

  tearDown(() async {
    for (final c in clients) {
      await c.dispose();
    }
    clients.clear();
    for (final t in transports) {
      await t.disconnect();
    }
    transports.clear();
    await server.stop();
    await engine.dispose();
  });

  test('pairs, then play / seek / volume / next control the Player and sync state',
      () async {
    await startServer();
    final c = newClient();
    await pair(c);

    expect(c.current.playerName, 'Test Player');
    // The Player pushes full state right after pairing completes.
    await waitFor(() => c.current.playback.title == 'Demo Track 1',
        reason: 'initial state after pairing');
    expect(c.current.playback.isPlaying, isFalse);

    await c.sendCommand(RemoteActions.play);
    await waitFor(() => c.current.playback.isPlaying, reason: 'playing state');
    expect(engine.state.isPlaying, isTrue);

    await c.sendCommand(RemoteActions.seek, {'positionSeconds': 45});
    await waitFor(() => c.current.playback.positionSeconds == 45);

    await c.sendCommand(RemoteActions.setVolume, {'volume': 0.35});
    await waitFor(() => (c.current.playback.volume - 0.35).abs() < 1e-9);

    await c.sendCommand(RemoteActions.next);
    await waitFor(() => c.current.playback.queueIndex == 1);
    expect(c.current.playback.title, 'Demo Track 2');

    await c.sendCommand(RemoteActions.toggle);
    await waitFor(() => !c.current.playback.isPlaying);

    await c.sendCommand(RemoteActions.previous);
    await waitFor(() => c.current.playback.queueIndex == 0);

    // The Player's own engine ticking is pushed to the Controller too.
    await c.sendCommand(RemoteActions.play);
    engine.tickForTest();
    await waitFor(() => c.current.playback.positionSeconds == 1);
  });

  test('invalid seek and unsupported actions return errors, not crashes', () async {
    await startServer();
    final c = newClient();
    await pair(c);

    await expectLater(
      c.sendCommand(RemoteActions.seek, {'positionSeconds': 99999}),
      throwsA(isA<ControllerException>()
          .having((e) => e.code, 'code', ErrorCodes.invalidPosition)),
    );
    await expectLater(
      c.sendCommand('playUrl', {'url': 'https://example.com/a.mp3'}),
      throwsA(isA<ControllerException>()
          .having((e) => e.code, 'code', ErrorCodes.invalidAction)),
    );
    await expectLater(
      c.sendCommand(RemoteActions.setVolume, {'volume': 7}),
      throwsA(isA<ControllerException>()
          .having((e) => e.code, 'code', ErrorCodes.invalidAction)),
    );
    expect(c.current.isConnected, isTrue);
  });

  test('commands without a token are rejected (NOT_PAIRED)', () async {
    await startServer();
    final inbox = <RemoteMessage>[];
    final t = await rawTransport(inbox);
    await t.send(hello());
    await t.send(RemoteMessage(
      type: MessageType.command,
      requestId: 'c1',
      payload: {'action': RemoteActions.play},
    ));
    await waitFor(() => inbox.any((m) => m.type == MessageType.error));
    final err = inbox.firstWhere((m) => m.type == MessageType.error);
    expect(err.errorCode, ErrorCodes.notPaired);
    expect(engine.state.isPlaying, isFalse);
  });

  test('commands with a wrong token are rejected (INVALID_SESSION)', () async {
    await startServer();
    final c = newClient();
    await pair(c);

    final inbox = <RemoteMessage>[];
    final t = await rawTransport(inbox);
    await t.send(hello());
    await t.send(RemoteMessage(
      type: MessageType.command,
      requestId: 'c1',
      sessionId: 'whatever',
      token: 'not-the-token',
      payload: {'action': RemoteActions.play},
    ));
    await waitFor(() => inbox.any((m) => m.type == MessageType.error));
    expect(inbox.firstWhere((m) => m.type == MessageType.error).errorCode,
        ErrorCodes.invalidSession);
    expect(engine.state.isPlaying, isFalse);
  });

  test('unsupported protocol versions are refused', () async {
    await startServer();
    final inbox = <RemoteMessage>[];
    final t = await rawTransport(inbox);
    await t.send(hello(version: 99));
    await waitFor(() => inbox.any((m) => m.type == MessageType.error));
    expect(inbox.first.errorCode, ErrorCodes.unsupportedProtocol);
  });

  test('malformed messages get INVALID_MESSAGE and the server keeps working',
      () async {
    await startServer();
    final socket = await WebSocket.connect('ws://127.0.0.1:${server.current.port}');
    final replies = <String>[];
    socket.listen((m) => replies.add(m as String));
    socket.add('not json at all');
    await waitFor(() => replies.isNotEmpty);
    expect(RemoteMessage.decode(replies.first).errorCode, ErrorCodes.invalidMessage);
    await socket.close();

    final c = newClient();
    await pair(c);
    expect(c.current.isConnected, isTrue);
  });

  test('wrong code is refused; three wrong codes cancel pairing', () async {
    await startServer();
    final c = newClient();
    await c.connect(
        host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    final good = server.current.pending!.code;
    final bad = good == '000000' ? '111111' : '000000';

    await expectLater(
      c.submitCode(bad),
      throwsA(isA<ControllerException>()
          .having((e) => e.code, 'code', ErrorCodes.invalidCode)),
    );
    expect(c.current.status, ControllerStatus.awaitingCode);

    await expectLater(c.submitCode(bad), throwsA(isA<ControllerException>()));
    // Third wrong attempt: pairing is cancelled.
    try {
      await c.submitCode(bad);
    } catch (_) {}
    await waitFor(() => c.current.status == ControllerStatus.disconnected);
    expect(c.current.message, contains('Too many'));
    expect(server.current.pending, isNull);
    expect(server.current.controller, isNull);
  });

  test('Player rejecting the request leaves the Controller disconnected', () async {
    await startServer();
    final c = newClient();
    await c.connect(
        host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    server.rejectPairing();
    await waitFor(() => c.current.status == ControllerStatus.disconnected);
    expect(c.current.message, contains('rejected'));
    expect(server.current.controller, isNull);
  });

  test('pairing code expires', () async {
    await startServer(pairingTtl: const Duration(milliseconds: 300));
    final c = newClient();
    await c.connect(
        host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    await waitFor(() => c.current.status == ControllerStatus.disconnected,
        reason: 'expiry');
    expect(c.current.message, contains('expired'));
    expect(server.current.pending, isNull);
  });

  test('Accept after the code is entered also completes pairing', () async {
    await startServer();
    final c = newClient();
    await c.connect(
        host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    final code = server.current.pending!.code;
    await c.submitCode(code);
    expect(c.current.status, ControllerStatus.waitingForPlayer);
    expect(server.current.pending!.codeVerified, isTrue);
    server.acceptPairing();
    await waitFor(() => c.current.isConnected);
  });

  test('a second Controller replaces the first (SESSION_REPLACED)', () async {
    await startServer();
    final a = newClient();
    await pair(a, name: 'Phone A');
    expect(server.current.controller!.name, 'Phone A');

    final b = newClient();
    await b.connect(
        host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone B');
    expect(server.current.pending!.replacesController, 'Phone A');
    final code = server.current.pending!.code;
    server.acceptPairing();
    await b.submitCode(code);
    await waitFor(() => b.current.isConnected);
    await waitFor(() => a.current.status == ControllerStatus.disconnected,
        reason: 'first controller replaced');
    expect(a.current.message, contains('took over'));
    expect(server.current.controller!.name, 'Phone B');

    // The replaced Controller cannot control anymore; the new one can.
    await expectLater(a.sendCommand(RemoteActions.play), throwsA(isA<ControllerException>()));
    await b.sendCommand(RemoteActions.play);
    await waitFor(() => engine.state.isPlaying);
  });

  test('connection drop: Controller reconnects with its token and keeps control',
      () async {
    await startServer();
    final c = newClient();
    await pair(c);
    await c.sendCommand(RemoteActions.play);

    await c.debugDropConnection();
    expect(c.current.status, ControllerStatus.reconnecting);
    await waitFor(() => c.current.isConnected, reason: 'reconnected');

    await c.sendCommand(RemoteActions.pause);
    await waitFor(() => !c.current.playback.isPlaying);
    expect(server.current.controller!.connected, isTrue);
  });

  test('Controller disconnect revokes the session', () async {
    await startServer();
    final c = newClient();
    await pair(c);
    await c.disconnect();
    expect(c.current.status, ControllerStatus.disconnected);
    await waitFor(() => server.current.controller == null,
        reason: 'session revoked on Player');
  });

  test('Player disconnecting the Controller ends the session without reconnecting',
      () async {
    await startServer();
    final c = newClient();
    await pair(c);
    await server.disconnectController();
    await waitFor(() => c.current.status == ControllerStatus.disconnected);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(c.current.status, ControllerStatus.disconnected,
        reason: 'must not auto-reconnect after the Player ended it');
    expect(server.current.controller, isNull);
  });

  test('silent connections are closed after the stale timeout', () async {
    await startServer(staleTimeout: const Duration(milliseconds: 600));
    final closed = Completer<void>();
    final t = LocalWebSocketTransport(host: '127.0.0.1', port: server.current.port!);
    transports.add(t);
    await t.connect();
    t.messages.listen((_) {}, onDone: closed.complete);
    await closed.future.timeout(const Duration(seconds: 5));
  });

  test('pairing history is written to paired_controllers', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await startServer(store: DriftPairedControllersStore(db));
    final c = newClient();
    await pair(c, name: 'History Phone');

    final repo = SettingsRepository(db);
    var rows = await repo.watchConnectionHistory().first;
    expect(rows, hasLength(1));
    expect(rows.single.controllerName, 'History Phone');
    expect(rows.single.connectionType, 'local');
    expect(rows.single.active, isTrue);

    await c.disconnect();
    await waitFor(() => server.current.controller == null);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    rows = await repo.watchConnectionHistory().first;
    expect(rows.single.active, isFalse);
  });

  test('connecting to a closed port reports a plain-language error', () async {
    await startServer();
    final port = server.current.port!;
    await server.stop();
    final c = newClient();
    await c.connect(host: '127.0.0.1', port: port, deviceName: 'Phone');
    expect(c.current.status, ControllerStatus.disconnected);
    expect(c.current.message, contains("Couldn't reach"));
    // Re-create so tearDown has a live server object to stop.
    await startServer();
  });
}
