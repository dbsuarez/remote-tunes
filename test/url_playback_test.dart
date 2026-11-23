import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong local(int id) => PlayableSong(
      id: id,
      title: 'Local $id',
      artist: 'Artist',
      album: 'Album',
      filePath: '/private/music/$id.mp3',
      durationSeconds: 100,
    );

Future<void> waitFor(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('engine: playUrl', () {
    late FakeAudioBackend backend;
    late FakeUrlChecker checker;
    late QueuePlaybackEngine engine;

    setUp(() {
      backend = FakeAudioBackend();
      checker = FakeUrlChecker();
      engine = QueuePlaybackEngine(
        backend: backend,
        urlChecker: checker,
        fileExists: (_) => true,
      );
    });

    tearDown(() => engine.dispose());

    test('plays a link: loads the URL, reports it as an internet stream', () async {
      await engine.playUrl('https://example.com/music/My_Song.mp3');
      await settle();
      expect(checker.checked.single.toString(), 'https://example.com/music/My_Song.mp3');
      expect(backend.loadedUrls, ['https://example.com/music/My_Song.mp3']);
      expect(backend.loaded, isEmpty, reason: 'not loaded as a file');
      final s = engine.state;
      expect(s.title, 'My Song');
      expect(s.source, 'url');
      expect(s.isInternetStream, isTrue);
      expect(s.songId, isNull, reason: 'streams are not library songs');
      expect(s.isPlaying, isTrue);
      expect(s.isLoading, isFalse);
      expect(s.error, '');
      expect(s.queueLength, 1);
    });

    test('a given title wins over the one guessed from the link', () async {
      await engine.playUrl('https://example.com/a.mp3', title: '  My Radio  ');
      expect(engine.state.title, 'My Radio');
    });

    test('a link replaces the queue; local songs play again afterwards', () async {
      await engine.playSongs([local(1), local(2)]);
      await engine.playUrl('https://example.com/a.mp3');
      expect(engine.state.queueLength, 1);
      await engine.playSongs([local(3)]);
      expect(engine.state.source, 'local_file');
      expect(engine.state.title, 'Local 3');
    });

    test('invalid links are refused before any network use', () async {
      for (final bad in ['', 'ftp://example.com/a.mp3', 'not a url', 'file:///a.mp3']) {
        await expectLater(
          engine.playUrl(bad),
          throwsA(isA<PlaybackException>()
              .having((e) => e.code, 'code', ErrorCodes.invalidUrl)),
        );
      }
      expect(checker.checked, isEmpty);
      expect(backend.loadedUrls, isEmpty);
    });

    test('an unreachable link keeps whatever was playing', () async {
      await engine.playSongs([local(1)]);
      checker.failWith = PlaybackException(
          ErrorCodes.urlUnreachable, 'The Player could not reach that website.');
      await expectLater(
        engine.playUrl('https://example.com/a.mp3'),
        throwsA(isA<PlaybackException>()
            .having((e) => e.code, 'code', ErrorCodes.urlUnreachable)),
      );
      expect(engine.state.title, 'Local 1');
      expect(engine.state.isPlaying, isTrue);
      expect(backend.loadedUrls, isEmpty);
    });

    test('a link that passes the check but cannot be decoded reports PLAYBACK_FAILED',
        () async {
      backend.unplayableUrls.add('https://example.com/a.mp3');
      await expectLater(
        engine.playUrl('https://example.com/a.mp3'),
        throwsA(isA<PlaybackException>()
            .having((e) => e.code, 'code', ErrorCodes.playbackFailed)),
      );
      expect(engine.state.isPlaying, isFalse);
      expect(engine.state.isLoading, isFalse);
    });

    test('state says "loading" while the stream opens', () async {
      final gate = Completer<void>();
      backend.urlGate = gate.future;
      final states = <bool>[];
      final sub = engine.states.listen((s) => states.add(s.isLoading));

      final play = engine.playUrl('https://example.com/a.mp3');
      await settle();
      expect(engine.state.isLoading, isTrue);
      expect(engine.state.isPlaying, isFalse);

      gate.complete();
      await play;
      await settle();
      await sub.cancel();
      expect(engine.state.isLoading, isFalse);
      expect(engine.state.isPlaying, isTrue);
      expect(states, contains(true));
    });

    test('other commands stay responsive while the link is being checked',
        () async {
      checker.delay = const Duration(milliseconds: 300);
      await engine.playSongs([local(1)]);
      final play = engine.playUrl('https://example.com/a.mp3');
      await engine.setVolume(0.3); // must not wait for the network check
      expect(engine.state.volume, 0.3);
      expect(engine.state.title, 'Local 1', reason: 'still the old track');
      await play;
      expect(engine.state.source, 'url');
    });

    test('the length of a stream is picked up when it becomes known', () async {
      await engine.playUrl('https://example.com/a.mp3');
      expect(engine.state.durationSeconds, 0);
      backend.emitDuration(const Duration(minutes: 3, seconds: 20));
      await settle();
      expect(engine.state.durationSeconds, 200);
    });

    test('a stream that drops reports a plain error and stops; Play clears it',
        () async {
      await engine.playUrl('https://example.com/a.mp3');
      backend.emitError('Playback stopped. The connection may have dropped.');
      await settle();
      expect(engine.state.isPlaying, isFalse);
      expect(engine.state.error, contains('connection'));

      await engine.play();
      expect(engine.state.error, '');
      expect(engine.state.isPlaying, isTrue);
    });

    test('errors with nothing loaded are ignored', () async {
      backend.emitError('late error');
      await settle();
      expect(engine.state.error, '');
    });

    test('the link never appears in state or queue data sent to Controllers', () async {
      await engine.playUrl('https://secret.example.com/token123/a.mp3');
      final stateJson = jsonEncode(engine.state.toJson());
      final queueJson = jsonEncode(engine.queueSnapshot().toJson());
      for (final text in [stateJson, queueJson]) {
        expect(text, isNot(contains('secret.example.com')));
        expect(text, isNot(contains('token123')));
        expect(text, isNot(contains('http')));
      }
      final item = engine.queueSnapshot().items.single;
      expect(item.song.available, isTrue);
      expect(item.song.artist, 'Internet');
    });

    test('a stream does not break next / previous / clear', () async {
      await engine.playUrl('https://example.com/a.mp3');
      await engine.next(); // end of queue: no-op
      await engine.previous(); // restarts
      await engine.clearQueue();
      expect(engine.state.queueLength, 0);
    });
  });

  group('end to end over the network', () {
    late AppDatabase db;
    late FakeAudioBackend backend;
    late FakeUrlChecker checker;
    late QueuePlaybackEngine engine;
    late PlayerServer server;
    late ControllerClient client;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      backend = FakeAudioBackend();
      checker = FakeUrlChecker();
      engine = QueuePlaybackEngine(
          backend: backend, urlChecker: checker, fileExists: (_) => true);
      server = PlayerServer(
        engine: engine,
        deviceName: 'Test Player',
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4,
        library: RepositoryPlayerLibrary(LibraryRepository(db)),
      );
      await server.start();
      client = ControllerClient(
        transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p),
        heartbeatInterval: const Duration(milliseconds: 200),
      );
      await client.connect(
          host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
      final code = server.current.pending!.code;
      server.acceptPairing();
      await client.submitCode(code);
      await waitFor(() => client.current.isConnected);
    });

    tearDown(() async {
      await client.dispose();
      await server.stop();
      await engine.dispose();
      await db.close();
    });

    test('Controller sends a link; the Player plays it and reports state', () async {
      await client.playUrl('https://example.com/radio/Jazz_Night.mp3');
      await waitFor(() => client.current.playback.title == 'Jazz Night');
      final p = client.current.playback;
      expect(p.source, 'url');
      expect(p.isPlaying, isTrue);
      expect(p.songId, isNull);
      expect(backend.loadedUrls.single, 'https://example.com/radio/Jazz_Night.mp3');
    });

    test('a custom title is used', () async {
      await client.playUrl('https://example.com/a.mp3', title: 'Morning Show');
      await waitFor(() => client.current.playback.title == 'Morning Show');
    });

    test('bad links come back as INVALID_URL with a readable message', () async {
      await expectLater(
        client.playUrl('ftp://example.com/a.mp3'),
        throwsA(isA<ControllerException>()
            .having((e) => e.code, 'code', ErrorCodes.invalidUrl)
            .having((e) => e.message, 'message', contains('http'))),
      );
      await expectLater(
        client.sendCommand(RemoteActions.playUrl, {'url': 42}),
        throwsA(isA<ControllerException>()
            .having((e) => e.code, 'code', ErrorCodes.invalidUrl)),
      );
      await expectLater(
        client.sendCommand(RemoteActions.playUrl),
        throwsA(isA<ControllerException>()),
      );
      expect(client.current.isConnected, isTrue);
    });

    test('an unreachable link comes back as URL_UNREACHABLE; nothing changes',
        () async {
      checker.failWith = PlaybackException(ErrorCodes.urlUnreachable,
          "The Player couldn't reach that website. Make sure the Player phone is connected to the internet.");
      await expectLater(
        client.playUrl('https://example.com/a.mp3'),
        throwsA(isA<ControllerException>()
            .having((e) => e.code, 'code', ErrorCodes.urlUnreachable)
            .having((e) => e.message, 'message', contains('internet'))),
      );
      expect(client.current.playback.source, isNot('url'));
      expect(client.current.isConnected, isTrue);
    });

    test('a slow check still completes (longer timeout than normal commands)',
        () async {
      checker.delay = const Duration(seconds: 6); // longer than the 5 s default
      await client.playUrl('https://example.com/a.mp3');
      await waitFor(() => client.current.playback.source == 'url');
    });

    test('a dropped stream shows up as an error in the Controller\'s state', () async {
      await client.playUrl('https://example.com/a.mp3');
      await waitFor(() => client.current.playback.isPlaying);
      backend.emitError('Playback stopped. The connection may have dropped.');
      await waitFor(() => client.current.playback.error.isNotEmpty);
      expect(client.current.playback.isPlaying, isFalse);
      await client.sendCommand(RemoteActions.play);
      await waitFor(() => client.current.playback.error.isEmpty);
    });

    test('the link itself is never sent back to the Controller', () async {
      await client.playUrl('https://secret.example.com/token123/a.mp3');
      await waitFor(() => client.current.playback.source == 'url');
      final queue = await client.getQueue();
      final text = '${client.current.playback.toJson()} ${queue.toJson()}';
      expect(text, isNot(contains('secret.example.com')));
      expect(text, isNot(contains('token123')));
    });
  });
}
