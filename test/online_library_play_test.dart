import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';

Future<void> waitFor(bool Function() c, {String? reason}) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

const jam1 = 'https://prod-1.storage.jamendo.com/?trackid=11&format=mp32';
const jam2 = 'https://prod-1.storage.jamendo.com/?trackid=22&format=mp32';

void main() {
  late FakeAudioBackend backend;
  late FakeUrlChecker checker;
  late QueuePlaybackEngine engine;
  late PlayerServer server;
  late ControllerClient client;

  setUp(() async {
    backend = FakeAudioBackend();
    checker = FakeUrlChecker();
    engine = QueuePlaybackEngine(
        backend: backend, fileExists: (_) => true, urlChecker: checker);
    server = PlayerServer(
      engine: engine,
      deviceName: 'P',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
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
    await waitFor(() => client.current.isConnected, reason: 'paired');
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
    await engine.dispose();
  });

  test('Play on Player: the existing playUrl streams it, with artist and album', () async {
    await client.playUrl(jam1, title: 'Sunrise', artist: 'The Band', album: 'Dawn');
    await waitFor(() => client.current.playback.title == 'Sunrise', reason: 'playing');
    expect(backend.loadedUrls, [jam1]);
    expect(client.current.playback.artist, 'The Band');
    expect(client.current.playback.album, 'Dawn');
    expect(client.current.playback.isInternetStream, isTrue);
    expect(checker.checked.single.toString(), jam1, reason: 'the Player checks the link');
  });

  test('Add to queue: it joins the queue without interrupting what plays', () async {
    await client.playUrl(jam1, title: 'First', artist: 'A', album: 'X');
    await waitFor(() => client.current.playback.title == 'First');

    await client.playUrl(jam2, title: 'Second', artist: 'B', album: 'Y', queue: true);
    final q = await client.getQueue();
    expect([for (final i in q.items) i.song.title], ['First', 'Second']);
    expect(q.items.last.song.artist, 'B');
    expect(q.items.last.song.album, 'Y');
    expect(client.current.playback.title, 'First', reason: 'still playing the first');
    expect(backend.loadedUrls, [jam1], reason: 'the second is not loaded yet');
  });

  test('Add to queue with an empty queue lines it up without starting it', () async {
    await client.playUrl(jam1, title: 'Only', queue: true);
    final q = await client.getQueue();
    expect(q.items.single.song.title, 'Only');
    expect(client.current.playback.isPlaying, isFalse);
    expect(backend.loadedUrls, isEmpty);
  });

  test('an unreachable stream is explained, and the queue is not changed', () async {
    checker.failWith = Exception('offline');
    await expectLater(client.playUrl(jam1, title: 'X', queue: true),
        throwsA(anything));
    expect((await client.getQueue()).items, isEmpty);
  });

  test('the Player streams it: no local file is loaded', () async {
    await client.playUrl(jam1, title: 'T', artist: 'A', album: 'B');
    await waitFor(() => client.current.playback.title == 'T');
    expect(backend.loaded, isEmpty, reason: 'no local file was involved');
  });
}
