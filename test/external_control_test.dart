import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/external/control_mode_engine.dart';
import 'package:remote_tunes/features/external/external_app_engine.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/fake_external_bridge.dart';

Future<void> waitFor(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5), String? reason}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: ${reason ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Matcher controllerError(String code, [Matcher? message]) => throwsA(
    isA<ControllerException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.message, 'message', message ?? isNotEmpty));

void main() {
  late AppDatabase db;
  late FakeAudioBackend backend;
  late FakeExternalBridge bridge;
  late QueuePlaybackEngine local;
  late ControlModeEngine engine;
  late PlayerServer server;
  late ControllerClient client;
  late int songId;

  Future<void> start({bool optedIn = true}) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = LibraryRepository(db);
    songId = await repo.addSong(
      title: 'Local Song',
      artist: 'Ann',
      album: 'Album',
      filePath: '/private/music/1.mp3',
      durationSeconds: 100,
    );
    backend = FakeAudioBackend();
    bridge = FakeExternalBridge()..snapshot = FakeExternalBridge.playing();
    local = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
    engine = ControlModeEngine(
      local: local,
      external: optedIn ? ExternalAppEngine(bridge: bridge) : null,
    );
    server = PlayerServer(
      engine: engine,
      deviceName: 'Player',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      library: RepositoryPlayerLibrary(repo, fileExists: (_) => true),
    );
    await server.start();
    client = ControllerClient(
      transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p),
      heartbeatInterval: const Duration(milliseconds: 200),
    );
    await client.connect(host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    final code = server.current.pending!.code;
    server.acceptPairing();
    await client.submitCode(code);
    await waitFor(() => client.current.isConnected);
  }

  tearDown(() async {
    await client.dispose();
    await server.stop();
    await engine.dispose();
    await db.close();
  });

  group('Player opted in to External App Control', () {
    setUp(() async => start());

    test('the Controller is told external control is available', () async {
      await waitFor(() => client.current.playback.externalEnabled,
          reason: 'externalEnabled in state');
      expect(client.current.playback.isExternal, isFalse);
    });

    test('switching to another app and controlling it from the Controller', () async {
      await client.setControlMode(ControlMode.external);
      await waitFor(() => client.current.playback.isExternal, reason: 'external state');
      final p = client.current.playback;
      expect(p.externalApp, 'Spotify');
      expect(p.title, 'Blue Song');
      expect(p.artist, 'The Band');
      expect(p.isPlaying, isTrue);
      expect(p.durationSeconds, 200);

      await client.sendCommand(RemoteActions.pause);
      await client.sendCommand(RemoteActions.next);
      await client.sendCommand(RemoteActions.seek, {'positionSeconds': 60});
      await client.sendCommand(RemoteActions.setVolume, {'volume': 0.3});
      expect(bridge.calls, containsAllInOrder(['start', 'pause', 'next', 'seekTo:60000', 'volume:0.3']));
    });

    test('state follows the other app (new song, paused)', () async {
      await client.setControlMode(ControlMode.external);
      await waitFor(() => client.current.playback.isExternal);
      bridge.push(FakeExternalBridge.playing(
          t: FakeExternalBridge.track(title: 'Second Song', isPlaying: false, positionMs: 0)));
      await waitFor(() => client.current.playback.title == 'Second Song');
      expect(client.current.playback.isPlaying, isFalse);
    });

    test('what the app does not allow is reported, not pretended', () async {
      bridge.snapshot = FakeExternalBridge.playing(
          t: FakeExternalBridge.track(canSeek: false, canNext: false, canPrevious: false));
      await client.setControlMode(ControlMode.external);
      await waitFor(() => client.current.playback.isExternal);
      expect(client.current.playback.canSeek, isFalse);
      expect(client.current.playback.canSkip, isFalse);
      await expectLater(
        client.sendCommand(RemoteActions.next),
        controllerError(ErrorCodes.invalidAction, contains("Spotify doesn't allow skipping")),
      );
    });

    test('queue, library songs and links are refused while external', () async {
      await client.setControlMode(ControlMode.external);
      await waitFor(() => client.current.playback.isExternal);
      await expectLater(
        client.sendCommand(RemoteActions.playSong, {'songId': songId}),
        controllerError(ErrorCodes.invalidAction, contains('Switch back to RemoteTunes')),
      );
      await expectLater(
        client.playUrl('https://example.com/a.mp3'),
        controllerError(ErrorCodes.invalidAction),
      );
      await expectLater(client.sendCommand(RemoteActions.clearQueue),
          controllerError(ErrorCodes.invalidAction));
      expect(client.current.isConnected, isTrue);
    });

    test('switching back pauses the other app and RemoteTunes works again', () async {
      await client.setControlMode(ControlMode.external);
      await waitFor(() => client.current.playback.isExternal);
      await client.setControlMode(ControlMode.local);
      await waitFor(() => !client.current.playback.isExternal);
      expect(bridge.calls, containsAllInOrder(['start', 'pause', 'stop']));

      await client.sendCommand(RemoteActions.playSong, {'songId': songId});
      await waitFor(() => client.current.playback.title == 'Local Song');
      expect(client.current.playback.isPlaying, isTrue);
    });

    test('starting external mode pauses RemoteTunes (never two apps at once)',
        () async {
      await client.sendCommand(RemoteActions.playSong, {'songId': songId});
      await waitFor(() => backend.playing);
      await client.setControlMode(ControlMode.external);
      expect(backend.playing, isFalse);
    });

    test('missing Notification access is explained to the Controller', () async {
      bridge.accessGranted = false;
      await expectLater(
        client.setControlMode(ControlMode.external),
        controllerError(ErrorCodes.permissionDenied, contains('Notification access')),
      );
      expect(client.current.playback.isExternal, isFalse);
      expect(client.current.isConnected, isTrue);
    });

    test('bad modes are rejected', () async {
      await expectLater(
        client.sendCommand(RemoteActions.setControlMode, {'mode': 'banana'}),
        controllerError(ErrorCodes.invalidAction),
      );
      await expectLater(
        client.sendCommand(RemoteActions.setControlMode),
        controllerError(ErrorCodes.invalidAction),
      );
    });

    test('nothing about other apps (package names, titles) leaks beyond the '
        'basic state', () async {
      await client.setControlMode(ControlMode.external);
      await waitFor(() => client.current.playback.isExternal);
      final json = client.current.playback.toJson().toString();
      expect(json, isNot(contains('com.spotify')));
    });
  });

  group('Player has External App Control off (the default)', () {
    setUp(() async => start(optedIn: false));

    test('Controllers are not offered it, and it cannot be switched on remotely',
        () async {
      expect(client.current.playback.externalEnabled, isFalse);
      await expectLater(
        client.setControlMode(ControlMode.external),
        controllerError(ErrorCodes.permissionDenied, contains('turned off')),
      );
      expect(bridge.calls, isEmpty, reason: 'no other app was ever looked at');
    });

    test('everything else works as before', () async {
      await client.sendCommand(RemoteActions.playSong, {'songId': songId});
      await waitFor(() => client.current.playback.title == 'Local Song');
    });
  });

  test('a Player without a switchable engine says so', () async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = FakeAudioBackend();
    bridge = FakeExternalBridge();
    local = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
    engine = ControlModeEngine(local: local);
    // A bare engine (no ControlModeCapable) behind the server:
    server = PlayerServer(
      engine: local,
      deviceName: 'Plain',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    await server.start();
    client = ControllerClient(
      transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p),
      heartbeatInterval: const Duration(milliseconds: 200),
    );
    await client.connect(host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    final code = server.current.pending!.code;
    server.acceptPairing();
    await client.submitCode(code);
    await waitFor(() => client.current.isConnected);
    await expectLater(
      client.setControlMode(ControlMode.external),
      controllerError(ErrorCodes.invalidAction, contains("can't control other apps")),
    );
  });
}
