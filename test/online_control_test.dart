import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/constants.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/online/relay.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/core/transport/remote_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/online/online_relay_host.dart';
import 'package:remote_tunes/features/online/online_status.dart';
import 'package:remote_tunes/features/online/online_transport.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/in_memory_relay.dart';

const room = 'ABCD2345';

Future<void> waitFor(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5), String? reason}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: ${reason ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late InMemoryRelayHub hub;
  late AppDatabase db;
  late LibraryRepository repo;
  late FakeAudioBackend backend;
  late QueuePlaybackEngine engine;
  late PlayerServer server;
  late OnlineRelayHost host;
  final clients = <ControllerClient>[];
  final extra = <RelayChannel>[];
  final songIds = <int>[];

  /// Local WebSocket path that tests can switch off (Wi‑Fi gone).
  var localReachable = true;
  var localAttempts = 0;

  Future<void> startPlayer({
    bool enableLocal = false,
    Duration staleTimeout = const Duration(seconds: 15),
    Duration rebuildAfter = const Duration(milliseconds: 300),
    List<Duration>? retryDelays,
  }) async {
    hub = InMemoryRelayHub();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    songIds.clear();
    for (var i = 1; i <= 3; i++) {
      songIds.add(await repo.addSong(
        title: 'Song $i',
        artist: 'Ann',
        album: 'Album',
        trackNumber: i,
        filePath: '/private/music/$i.mp3',
        durationSeconds: 100,
      ));
    }
    backend = FakeAudioBackend();
    engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
    server = PlayerServer(
      engine: engine,
      deviceName: 'Online Player',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      enableLocal: enableLocal,
      staleTimeout: staleTimeout,
      library: RepositoryPlayerLibrary(repo, fileExists: (_) => true),
    );
    await server.start();
    host = OnlineRelayHost(
      channelFactory: hub.channel,
      roomCode: room,
      onPeer: server.acceptConnection,
      onStatus: server.updateOnline,
      rebuildAfter: rebuildAfter,
      retryDelays: retryDelays ??
          const [Duration(milliseconds: 100), Duration(milliseconds: 200)],
    );
    await host.start();
  }

  ControllerClient newClient({
    bool local = false,
    Duration onlineHelloTimeout = const Duration(seconds: 3),
  }) {
    final c = ControllerClient(
      transportFactory: local
          ? (h, p) {
              localAttempts++;
              return localReachable
                  ? LocalWebSocketTransport(host: h, port: p)
                  : _Unreachable();
            }
          : null,
      onlineTransportFactory: (r, peer) => OnlineTransport(
        channelFactory: hub.channel,
        roomCode: r,
        peerId: peer,
        joinTimeout: const Duration(seconds: 2),
      ),
      heartbeatInterval: const Duration(milliseconds: 200),
      connectionTimeout: const Duration(seconds: 2),
      localHelloTimeout: const Duration(seconds: 2),
      onlineHelloTimeout: onlineHelloTimeout,
      reconnectDelays: List.filled(30, const Duration(milliseconds: 100)),
    );
    clients.add(c);
    return c;
  }

  Future<void> pairOnline(ControllerClient c,
      {String name = 'Remote Phone', String code = room, ConnectionMode mode = ConnectionMode.onlineOnly}) async {
    await c.connect(roomCode: code, deviceName: name, mode: mode);
    expect(c.current.status, ControllerStatus.awaitingCode, reason: c.current.message);
    final pin = server.current.pending!.code;
    server.acceptPairing();
    await c.submitCode(pin);
    await waitFor(() => c.current.isConnected, reason: 'connected');
  }

  setUp(() {
    localReachable = true;
    localAttempts = 0;
  });

  tearDown(() async {
    for (final c in clients) {
      await c.dispose();
    }
    clients.clear();
    for (final e in extra) {
      await e.leave();
    }
    extra.clear();
    await host.stop();
    await server.stop();
    await engine.dispose();
    await db.close();
  });

  group('online-only control', () {
    setUp(() async => startPlayer());

    test('the Player reports its room and that it is connected', () async {
      final o = server.current.online!;
      expect(o.roomCode, room);
      expect(o.phase, OnlinePhase.connected);
      expect(server.current.running, isTrue);
      expect(server.current.port, isNull, reason: 'no local server in online-only');
      expect(hub.membersIn(room), 1);
    });

    test('pairs with the room code and shows the Controller as Online', () async {
      final c = newClient();
      await c.connect(roomCode: room, deviceName: 'Phone B', mode: ConnectionMode.onlineOnly);
      final pending = server.current.pending!;
      expect(pending.controllerName, 'Phone B');
      expect(pending.address, 'Online');
      expect(pending.connectionType, ConnectionType.online);
      expect(c.current.route, ConnectionType.online);

      server.acceptPairing();
      await c.submitCode(pending.code);
      await waitFor(() => c.current.isConnected);
      expect(server.current.controller!.connectionType, ConnectionType.online);
      expect(server.current.controller!.address, 'Online');
      expect(c.current.playerName, 'Online Player');
    });

    test('commands, state, library and queue all work through the relay', () async {
      final c = newClient();
      await pairOnline(c);

      await c.playUrlOrSongs(songIds);
      await waitFor(() => c.current.playback.title == 'Song 1');
      expect(c.current.playback.isPlaying, isTrue);

      await c.sendCommand(RemoteActions.seek, {'positionSeconds': 33});
      await waitFor(() => c.current.playback.positionSeconds == 33);
      await c.sendCommand(RemoteActions.setVolume, {'volume': 0.25});
      await waitFor(() => (c.current.playback.volume - 0.25).abs() < 1e-9);
      await c.sendCommand(RemoteActions.next);
      await waitFor(() => c.current.playback.title == 'Song 2');
      await c.sendCommand(RemoteActions.toggle);
      await waitFor(() => !c.current.playback.isPlaying);

      final page = await c.songs(query: 'song', limit: 2);
      expect(page.total, 3);
      expect(page.items.map((s) => s.title), ['Song 1', 'Song 2']);
      expect((await c.artists()).items.single.name, 'Ann');

      final queue = await c.getQueue();
      expect(queue.items, hasLength(3));
      expect(queue.currentIndex, 1);
    });

    test('latency does not break ordering', () async {
      hub.latency = const Duration(milliseconds: 15);
      final c = newClient();
      await pairOnline(c);
      await c.playUrlOrSongs(songIds);
      for (var i = 0; i < 5; i++) {
        await c.sendCommand(RemoteActions.next);
      }
      await waitFor(() => c.current.playback.queueIndex == 2);
    });

    test('commands without pairing are refused (NOT_PAIRED), only to that peer',
        () async {
      final spy = hub.channel(room);
      extra.add(spy);
      await spy.join();
      final heard = <RelayFrame>[];
      spy.frames.listen(heard.add);

      await spy.send(RelayFrame(
        from: 'c-evil',
        to: RelayPeers.player,
        message: const RemoteMessage(
          type: MessageType.hello,
          requestId: 'h',
          payload: {'protocolVersion': AppConstants.protocolVersion},
        ).encode(),
      ));
      await spy.send(RelayFrame(
        from: 'c-evil',
        to: RelayPeers.player,
        message: const RemoteMessage(
          type: MessageType.command,
          requestId: 'c',
          payload: {'action': RemoteActions.play},
        ).encode(),
      ));
      await waitFor(() => heard.any((f) => f.message.contains('NOT_PAIRED')));
      expect(engine.state.isPlaying, isFalse);
      // The error was addressed to the sender only.
      expect(heard.every((f) => f.to == 'c-evil' && f.from == RelayPeers.player), isTrue);
    });

    test('a wrong token cannot control the Player', () async {
      final c = newClient();
      await pairOnline(c);
      final spy = hub.channel(room);
      extra.add(spy);
      await spy.join();
      final heard = <RelayFrame>[];
      spy.frames.listen(heard.add);
      await spy.send(RelayFrame(
        from: 'c-evil',
        to: RelayPeers.player,
        message: const RemoteMessage(
          type: MessageType.hello,
          payload: {'protocolVersion': AppConstants.protocolVersion},
        ).encode(),
      ));
      await spy.send(RelayFrame(
        from: 'c-evil',
        to: RelayPeers.player,
        message: const RemoteMessage(
          type: MessageType.command,
          requestId: 'c',
          sessionId: 'guess',
          token: 'guess',
          payload: {'action': RemoteActions.play},
        ).encode(),
      ));
      await waitFor(() => heard.any((f) => f.message.contains('INVALID_SESSION')));
      expect(engine.state.isPlaying, isFalse);
    });

    test('junk and spoofed frames are ignored; the session is unaffected', () async {
      final c = newClient();
      await pairOnline(c);
      final spy = hub.channel(room);
      extra.add(spy);
      await spy.join();
      final heard = <RelayFrame>[];
      spy.frames.listen(heard.add);

      // A frame pretending to come from the Player itself.
      await spy.send(RelayFrame(
        from: RelayPeers.player,
        to: RelayPeers.player,
        message: const RemoteMessage(type: MessageType.ping).encode(),
      ));
      // A frame for someone else.
      await spy.send(const RelayFrame(from: 'c-evil', to: 'c-other', message: 'x'));
      // Garbage text.
      await spy.send(const RelayFrame(
          from: 'c-evil', to: RelayPeers.player, message: 'not json'));
      await waitFor(() => heard.any((f) => f.message.contains('INVALID_MESSAGE')));
      expect(heard, hasLength(1), reason: 'only the garbage got an answer');
      expect(c.current.isConnected, isTrue);
      await c.sendCommand(RemoteActions.pause);
    });

    test('a second Controller replaces the first (SESSION_REPLACED)', () async {
      final a = newClient();
      await pairOnline(a, name: 'Phone A');
      final b = newClient();
      await pairOnline(b, name: 'Phone B');
      await waitFor(() => a.current.status == ControllerStatus.disconnected,
          reason: 'first controller replaced');
      expect(a.current.message, contains('took over'));
      expect(server.current.controller!.name, 'Phone B');
      await b.sendCommand(RemoteActions.next).catchError((_) {});
    });

    test('Controller disconnect revokes the session (bye)', () async {
      final c = newClient();
      await pairOnline(c);
      await c.disconnect();
      await waitFor(() => server.current.controller == null, reason: 'revoked');
      expect(host.peerCount, 0);
    });

    test('Player disconnect ends the session without reconnecting', () async {
      final c = newClient();
      await pairOnline(c);
      await server.disconnectController();
      await waitFor(() => c.current.status == ControllerStatus.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.current.status, ControllerStatus.disconnected);
    });

    test('a relay blip: both sides reconnect and the Controller keeps control',
        () async {
      final c = newClient();
      await pairOnline(c);
      await c.playUrlOrSongs(songIds);

      hub.dropRoom(room);
      await waitFor(() => c.current.status == ControllerStatus.reconnecting,
          reason: 'controller noticed');
      await waitFor(() => server.current.online!.phase == OnlinePhase.reconnecting,
          reason: 'player noticed');

      await waitFor(() => c.current.isConnected, reason: 'controller resumed');
      await waitFor(() => server.current.online!.phase == OnlinePhase.connected,
          reason: 'player back online');
      await c.sendCommand(RemoteActions.pause);
      await waitFor(() => !c.current.playback.isPlaying);
      expect(server.current.controller!.connected, isTrue);
    });

    test('losing connections does not leave channels subscribed', () async {
      final c = newClient();
      await pairOnline(c);
      for (var i = 0; i < 3; i++) {
        hub.dropRoom(room);
        await waitFor(() => c.current.isConnected && server.current.online!.isConnected,
            reason: 'recovered #$i');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // One Player + one Controller, not piles of stale subscriptions.
      expect(hub.membersIn(room), lessThanOrEqualTo(2));
    });

    test('a Controller that vanishes is dropped after the stale timeout but may '
        'resume', () async {
      await host.stop();
      await server.stop();
      await engine.dispose();
      await db.close();
      await startPlayer(staleTimeout: const Duration(milliseconds: 600));

      final c = newClient();
      await pairOnline(c);
      expect(host.peerCount, 1);

      // Simulate the Controller going silent: pause its heartbeat by dropping
      // frames for longer than the stale timeout.
      hub.dropFrames = true;
      await waitFor(() => host.peerCount == 0, reason: 'stale peer closed');
      expect(server.current.controller, isNotNull, reason: 'session is kept');
      expect(server.current.controller!.connected, isFalse);

      hub.dropFrames = false;
      await waitFor(() => c.current.isConnected && server.current.controller!.connected,
          timeout: const Duration(seconds: 8), reason: 'resumed');
      await c.sendCommand(RemoteActions.play).catchError((_) {});
    });

    test('very long queues are cut for the relay, with the real total reported',
        () async {
      final c = newClient();
      await pairOnline(c);
      await engine.enqueue([
        for (var i = 0; i < 400; i++)
          PlayableSong(
              id: 1000 + i,
              title: 'Bulk $i',
              artist: 'A',
              album: 'B',
              filePath: '/private/bulk/$i.mp3',
              durationSeconds: 10),
      ]);
      final q = await c.getQueue();
      expect(q.items.length, PlayerServer.maxOnlineQueueItems);
      expect(q.total, 400);
      expect(q.isTruncated, isTrue);
      // And the biggest frame stayed well under the relay limit.
      final biggest = hub.log.map((e) => e.$2.approxBytes).reduce((a, b) => a > b ? a : b);
      expect(biggest, lessThan(maxRelayFrameBytes));
    });

    test('nothing on the relay carries file paths', () async {
      final c = newClient();
      await pairOnline(c);
      await c.playUrlOrSongs(songIds);
      await c.songs();
      await c.getQueue();
      await waitFor(() => c.current.playback.title == 'Song 1');
      final all = hub.log.map((e) => e.$2.message).join();
      expect(all, isNot(contains('/private')));
      expect(all, isNot(contains('.mp3')));
    });
  });

  group('failures', () {
    test('no internet: a clear message, nothing connects', () async {
      await startPlayer();
      hub.offline = true;
      final c = newClient();
      await c.connect(roomCode: room, deviceName: 'P', mode: ConnectionMode.onlineOnly);
      expect(c.current.status, ControllerStatus.disconnected);
      expect(c.current.message, contains('relay'));
      expect(c.current.message, contains('internet'));
    });

    test('a mistyped room code is explained before touching the network', () async {
      await startPlayer();
      final c = newClient();
      await c.connect(roomCode: 'ABC', deviceName: 'P', mode: ConnectionMode.onlineOnly);
      expect(c.current.status, ControllerStatus.disconnected);
      expect(c.current.message, contains('8 letters and numbers'));
      expect(hub.membersIn('ABC'), 0);
    });

    test('a room with no Player in it times out with a helpful message', () async {
      await startPlayer();
      final c = newClient(onlineHelloTimeout: const Duration(milliseconds: 400));
      await c.connect(roomCode: 'ZZZZ2222', deviceName: 'P', mode: ConnectionMode.onlineOnly);
      expect(c.current.status, ControllerStatus.disconnected);
      expect(c.current.message, contains('did not respond'));
      // And it left the empty room.
      expect(hub.membersIn('ZZZZ2222'), 0);
    });

    test('rooms are isolated: a Controller only reaches the Player in its room',
        () async {
      await startPlayer();
      final c = newClient(onlineHelloTimeout: const Duration(milliseconds: 400));
      await c.connect(roomCode: 'WXYZ3456', deviceName: 'P', mode: ConnectionMode.onlineOnly);
      expect(c.current.isConnected, isFalse);
      expect(server.current.pending, isNull);
    });

    test('missing setup is explained per mode', () async {
      await startPlayer();
      final c = newClient();
      await c.connect(deviceName: 'P', mode: ConnectionMode.onlineOnly);
      expect(c.current.message, contains('room code'));
      await c.connect(deviceName: 'P', mode: ConnectionMode.localOnly);
      expect(c.current.message, contains('Local only'));
      await c.connect(deviceName: 'P', mode: ConnectionMode.auto);
      expect(c.current.message, contains('room code'));
    });

    test('the Player keeps retrying until the relay is reachable', () async {
      hub = InMemoryRelayHub()..offline = true;
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      backend = FakeAudioBackend();
      engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
      server = PlayerServer(
        engine: engine,
        deviceName: 'Online Player',
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4,
        enableLocal: false,
      );
      await server.start();
      host = OnlineRelayHost(
        channelFactory: hub.channel,
        roomCode: room,
        onPeer: server.acceptConnection,
        onStatus: server.updateOnline,
        retryDelays: const [Duration(milliseconds: 100)],
      );
      await host.start();
      expect(server.current.online!.phase, OnlinePhase.failed);
      expect(server.current.online!.error, contains('internet'));

      hub.offline = false;
      await waitFor(() => server.current.online!.isConnected, reason: 'retry worked');
      expect(hub.membersIn(room), 1);
    });
  });

  group('modes: local / online / auto', () {
    setUp(() async => startPlayer(enableLocal: true));

    test('Local only never touches the relay, even if a room code is given',
        () async {
      final c = newClient(local: true);
      await c.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        roomCode: room,
        deviceName: 'P',
        mode: ConnectionMode.localOnly,
      );
      expect(c.current.status, ControllerStatus.awaitingCode);
      expect(c.current.route, ConnectionType.local);
      expect(hub.log, isEmpty);
      expect(hub.membersIn(room), 1, reason: 'only the Player is in the room');
    });

    test('Online only never opens the local network, even if an address is given',
        () async {
      final c = newClient(local: true);
      await c.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        roomCode: room,
        deviceName: 'P',
        mode: ConnectionMode.onlineOnly,
      );
      expect(c.current.status, ControllerStatus.awaitingCode);
      expect(c.current.route, ConnectionType.online);
      expect(localAttempts, 0);
    });

    test('Auto prefers the local network when it is reachable', () async {
      final c = newClient(local: true);
      await c.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        roomCode: room,
        deviceName: 'P',
      );
      expect(c.current.route, ConnectionType.local);
      expect(server.current.pending!.connectionType, ConnectionType.local);
      expect(hub.log, isEmpty, reason: 'no relay traffic when local works');
    });

    test('Auto falls back to online when the local Player cannot be reached',
        () async {
      localReachable = false;
      final c = newClient(local: true);
      await c.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        roomCode: room,
        deviceName: 'P',
      );
      expect(localAttempts, 1);
      expect(c.current.status, ControllerStatus.awaitingCode, reason: c.current.message);
      expect(c.current.route, ConnectionType.online);
      expect(server.current.pending!.connectionType, ConnectionType.online);
    });

    test('Auto with nothing reachable reports both routes', () async {
      localReachable = false;
      hub.offline = true;
      final c = newClient(local: true);
      await c.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        roomCode: room,
        deviceName: 'P',
      );
      expect(c.current.status, ControllerStatus.disconnected);
      expect(c.current.message, contains('local network or online'));
    });

    test('paired on Wi‑Fi, then Wi‑Fi dies: the Controller moves to online and '
        'keeps its session (no new pairing)', () async {
      final c = newClient(local: true);
      await c.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        roomCode: room,
        deviceName: 'Phone',
      );
      final pin = server.current.pending!.code;
      server.acceptPairing();
      await c.submitCode(pin);
      await waitFor(() => c.current.isConnected);
      expect(c.current.route, ConnectionType.local);
      final sessionBefore = server.current.controller!;
      expect(sessionBefore.connectionType, ConnectionType.local);

      // Wi‑Fi path breaks.
      localReachable = false;
      await c.debugDropConnection();
      expect(c.current.status, ControllerStatus.reconnecting);
      await waitFor(() => c.current.isConnected, reason: 'resumed online');

      expect(c.current.route, ConnectionType.online);
      expect(server.current.pending, isNull, reason: 'no new pairing needed');
      expect(server.current.controller!.name, sessionBefore.name);
      await waitFor(
          () => server.current.controller!.connectionType == ConnectionType.online,
          reason: 'Player sees the new route');
      await c.sendCommand(RemoteActions.next).catchError((_) {});
      await waitFor(() => c.current.isConnected);
    });

    test('back on Wi‑Fi: reconnecting prefers the local network again', () async {
      final c = newClient(local: true);
      await c.connect(
        host: '127.0.0.1',
        port: server.current.port!,
        roomCode: room,
        deviceName: 'Phone',
      );
      final pin = server.current.pending!.code;
      server.acceptPairing();
      await c.submitCode(pin);
      await waitFor(() => c.current.isConnected);

      localReachable = false;
      await c.debugDropConnection();
      await waitFor(() => c.current.isConnected && c.current.route == ConnectionType.online);

      localReachable = true;
      await c.debugDropConnection();
      await waitFor(() => c.current.isConnected);
      expect(c.current.route, ConnectionType.local);
    });
  });

  group('Player stops', () {
    setUp(() async => startPlayer());

    test('stopping the host closes its peers and leaves the room', () async {
      final c = newClient();
      await pairOnline(c);
      await host.stop();
      expect(host.peerCount, 0);
      expect(hub.membersIn(room), 1, reason: 'only the Controller is left');
    });
  });
}

/// A local transport that can never connect (Wi‑Fi is gone).
class _Unreachable implements RemoteTransport {
  @override
  Future<void> connect() async =>
      throw TransportException("Couldn't reach the Player on the network.");

  @override
  Future<void> disconnect({bool intentional = true}) async {}

  @override
  Stream<RemoteMessage> get messages => const Stream.empty();

  @override
  Future<void> send(RemoteMessage message) async {}
}

extension on ControllerClient {
  /// Starts playing the given library songs (helper for these tests).
  Future<void> playUrlOrSongs(List<int> ids) => sendCommand(
      RemoteActions.playSong, {'songIds': ids, 'songId': ids.first});
}
