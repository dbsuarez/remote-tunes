import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/online/online_relay_host.dart';
import 'package:remote_tunes/features/online/online_transport.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/in_memory_relay.dart';

const room = 'ABCD2345';

Future<void> waitFor(bool Function() c,
    {Duration timeout = const Duration(seconds: 5), String? reason}) async {
  final end = DateTime.now().add(timeout);
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: ${reason ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late InMemoryRelayHub hub;
  late FakeAudioBackend backend;
  late QueuePlaybackEngine engine;
  late PlayerServer server;
  late OnlineRelayHost host;
  final clients = <ControllerClient>[];

  Future<void> startPlayer({String roomCode = room}) async {
    backend = FakeAudioBackend();
    engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
    await engine.enqueue([
      const PlayableSong(
          id: 1, title: 'Song', artist: 'A', album: 'B', filePath: '/x/1.mp3', durationSeconds: 100),
    ]);
    server = PlayerServer(
      engine: engine,
      deviceName: 'Home Player',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      enableLocal: false,
    );
    await server.start();
    host = OnlineRelayHost(
      channelFactory: hub.channel,
      roomCode: roomCode,
      onPeer: server.acceptConnection,
      onStatus: server.updateOnline,
      rebuildAfter: const Duration(milliseconds: 300),
    );
    await host.start();
  }

  ControllerClient newClient({bool neverReconnect = false}) {
    final c = ControllerClient(
      onlineTransportFactory: (r, peer) => OnlineTransport(
        channelFactory: hub.channel,
        roomCode: r,
        peerId: peer,
        joinTimeout: const Duration(seconds: 2),
      ),
      heartbeatInterval: const Duration(milliseconds: 200),
      connectionTimeout: const Duration(seconds: 2),
      onlineHelloTimeout: const Duration(milliseconds: 600),
      reconnectDelays: neverReconnect
          ? const [Duration(hours: 1)]
          : List.filled(30, const Duration(milliseconds: 100)),
    );
    clients.add(c);
    return c;
  }

  Future<void> pair(ControllerClient c) async {
    await c.connect(roomCode: room, deviceName: 'Browser', mode: ConnectionMode.onlineOnly);
    final pin = server.current.pending!.code;
    server.acceptPairing();
    await c.submitCode(pin);
    await waitFor(() => c.current.isConnected);
  }

  /// A browser tab closing or reloading: the old page just disappears, with no
  /// goodbye (so the Player keeps the session).
  Future<void> vanish(ControllerClient c) => c.debugDropConnection();

  setUp(() async {
    hub = InMemoryRelayHub();
    await startPlayer();
  });

  tearDown(() async {
    for (final c in clients) {
      await c.dispose();
    }
    clients.clear();
    await host.stop();
    await server.stop();
    await engine.dispose();
  });

  group('saved session', () {
    test('there is nothing to save before pairing', () async {
      final c = newClient();
      expect(c.savedSession, isNull);
      await c.connect(roomCode: room, deviceName: 'B', mode: ConnectionMode.onlineOnly);
      expect(c.current.status, ControllerStatus.awaitingCode);
      expect(c.savedSession, isNull, reason: 'not paired yet');
    });

    test('after pairing it holds what is needed to come back', () async {
      final c = newClient();
      await pair(c);
      final s = c.savedSession!;
      expect(s.roomCode, room);
      expect(s.sessionId, isNotEmpty);
      expect(s.token, isNotEmpty);
      expect(s.peerId, startsWith('c-'));
      expect(s.playerName, 'Home Player');
    });

    test('it round-trips through JSON; damaged data is rejected, not crashed on', () {
      const s = ControllerSession(
          roomCode: room, sessionId: 'sid', token: 'tok', peerId: 'c-1', playerName: 'P');
      final back = ControllerSession.fromJson(s.toJson())!;
      expect(back.roomCode, room);
      expect(back.token, 'tok');
      expect(back.playerName, 'P');

      for (final bad in [
        null,
        'x',
        5,
        <String, dynamic>{},
        {'roomCode': room},
        {'roomCode': room, 'sessionId': 'a', 'token': '', 'peerId': 'c'},
        {'roomCode': 1, 'sessionId': 'a', 'token': 'b', 'peerId': 'c'},
      ]) {
        expect(ControllerSession.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('it is cleared when the user disconnects', () async {
      final c = newClient();
      await pair(c);
      await c.disconnect();
      expect(c.savedSession, isNull);
    });
  });

  group('resuming after a reload', () {
    test('rejoins without pairing again and keeps control', () async {
      final first = newClient(neverReconnect: true);
      await pair(first);
      final saved = first.savedSession!;
      await vanish(first);

      final second = newClient();
      await second.resumeSession(session: saved, deviceName: 'Browser');
      expect(second.current.status, ControllerStatus.connected,
          reason: second.current.message);
      expect(server.current.pending, isNull, reason: 'no new pairing request');
      expect(server.current.controller!.name, 'Browser');
      expect(second.current.route, ConnectionType.online);
      expect(second.current.playerName, 'Home Player');

      await second.sendCommand(RemoteActions.play);
      await waitFor(() => second.current.playback.isPlaying);
      expect(backend.playing, isTrue);
      expect(second.current.playback.title, 'Song');
    });

    test('the same address in the room is kept, so the Player recognises it',
        () async {
      final first = newClient(neverReconnect: true);
      await pair(first);
      final saved = first.savedSession!;
      await vanish(first);
      hub.log.clear();

      final second = newClient();
      await second.resumeSession(session: saved, deviceName: 'Browser');
      await waitFor(() => second.current.isConnected);
      expect(second.savedSession!.peerId, saved.peerId);
      expect(hub.log.map((e) => e.$2.from).toSet(), containsAll([saved.peerId, 'player']));
    });

    test('works again and again (every reload)', () async {
      var c = newClient(neverReconnect: true);
      await pair(c);
      for (var i = 0; i < 3; i++) {
        final saved = c.savedSession!;
        await vanish(c);
        c = newClient(neverReconnect: true);
        await c.resumeSession(session: saved, deviceName: 'Browser');
        expect(c.current.isConnected, isTrue, reason: 'reload #$i: ${c.current.message}');
        await c.sendCommand(RemoteActions.pause);
      }
    });

    test('a wrong token is refused and the real session is left alone', () async {
      final first = newClient(neverReconnect: true);
      await pair(first);
      final real = first.savedSession!;
      await vanish(first);

      final attacker = newClient();
      await attacker.resumeSession(
        session: ControllerSession(
            roomCode: room,
            sessionId: real.sessionId,
            token: 'not-the-token',
            peerId: 'c-evil'),
        deviceName: 'Evil',
      );
      expect(attacker.current.status, ControllerStatus.disconnected);
      expect(attacker.current.message, contains('no longer valid'));
      expect(attacker.current.sessionInvalid, isTrue,
          reason: 'the saved session should be forgotten');
      expect(attacker.savedSession, isNull);

      // The rightful Controller can still come back.
      final rightful = newClient();
      await rightful.resumeSession(session: real, deviceName: 'Browser');
      expect(rightful.current.isConnected, isTrue);
      expect(server.current.controller!.name, 'Browser');
    });

    test('after the user disconnected (session revoked) it cannot be resumed',
        () async {
      final c = newClient();
      await pair(c);
      final saved = c.savedSession!;
      await c.disconnect();
      await waitFor(() => server.current.controller == null);

      final again = newClient();
      await again.resumeSession(session: saved, deviceName: 'Browser');
      expect(again.current.status, ControllerStatus.disconnected);
      expect(again.current.message, contains('pair again'));
    });

    test('after the Player restarted (new room) it fails with a helpful message',
        () async {
      final first = newClient(neverReconnect: true);
      await pair(first);
      final saved = first.savedSession!;
      await vanish(first);

      // The Player app restarts: a new session and a different room code.
      await host.stop();
      await server.stop();
      await engine.dispose();
      await startPlayer(roomCode: 'ZZZZ9999');

      final second = newClient();
      await second.resumeSession(session: saved, deviceName: 'Browser');
      expect(second.current.status, ControllerStatus.disconnected);
      expect(second.current.message, isNotEmpty);
      expect(second.savedSession, isNull);
    });

    test('a Player that restarted in the SAME room does not know the old session',
        () async {
      final first = newClient(neverReconnect: true);
      await pair(first);
      final saved = first.savedSession!;
      await vanish(first);

      await host.stop();
      await server.stop();
      await engine.dispose();
      await startPlayer(); // same room code, brand-new session state

      final second = newClient();
      await second.resumeSession(session: saved, deviceName: 'Browser');
      expect(second.current.status, ControllerStatus.disconnected);
      expect(second.current.message, contains('no longer valid'));
    });

    test('no internet: a clear message, not a hang', () async {
      final first = newClient(neverReconnect: true);
      await pair(first);
      final saved = first.savedSession!;
      await vanish(first);

      hub.offline = true;
      final second = newClient();
      await second.resumeSession(session: saved, deviceName: 'Browser');
      expect(second.current.status, ControllerStatus.disconnected);
      expect(second.current.message, contains('internet'));
      expect(second.current.sessionInvalid, isFalse,
          reason: 'a network problem must not throw the saved session away');
    });

    test('the Player replacing this Controller invalidates the session', () async {
      final a = newClient();
      await pair(a);
      final b = newClient();
      await pair(b);
      await waitFor(() => a.current.status == ControllerStatus.disconnected);
      expect(a.current.sessionInvalid, isTrue);
    });

    test('a resumed session survives a relay blip like any other', () async {
      final first = newClient(neverReconnect: true);
      await pair(first);
      final saved = first.savedSession!;
      await vanish(first);

      final second = newClient();
      await second.resumeSession(session: saved, deviceName: 'Browser');
      hub.dropRoom(room);
      await waitFor(() => second.current.status == ControllerStatus.reconnecting);
      await waitFor(() => second.current.isConnected, reason: 'recovered');
      await second.sendCommand(RemoteActions.next).catchError((_) {});
    });
  });
}
