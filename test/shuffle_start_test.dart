import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/music/local_music_source.dart';
import 'package:remote_tunes/features/music/music_source.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';

/// "Play" on a list, with shuffle on, starts on any of its songs, not always the first.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  PlayableSong song(int i) => PlayableSong(id: i, title: 'S$i', artist: 'A', album: 'B', filePath: '/m/$i.mp3', durationSeconds: 100);
  final five = [for (var i = 1; i <= 5; i++) song(i)];

  late QueuePlaybackEngine engine;
  var missing = <String>{};

  setUp(() {
    missing = {};
    engine = QueuePlaybackEngine(backend: FakeAudioBackend(), fileExists: (p) => !missing.contains(p), urlChecker: FakeUrlChecker());
  });
  tearDown(() => engine.dispose());

  /// The songs that were first, over many tries.
  Future<Set<String>> starts(Future<void> Function() play, {int tries = 80}) async {
    final seen = <String>{};
    for (var i = 0; i < tries; i++) {
      await play();
      seen.add(engine.queueSnapshot().items.firstWhere((x) => x.isCurrent).song.title);
    }
    return seen;
  }

  group('the player', () {
    test('with shuffle on, playing a list starts on any song', () async {
      await engine.setShuffle(true);
      expect(await starts(() => engine.playSongs(five)), {'S1', 'S2', 'S3', 'S4', 'S5'});
    });

    test('with shuffle off it starts on the first', () async {
      expect(await starts(() => engine.playSongs(five), tries: 10), {'S1'});
    });

    test('a song that was picked is the one that plays, shuffle or not', () async {
      await engine.setShuffle(true);
      expect(await starts(() => engine.playSongs(five, startIndex: 2), tries: 20), {'S3'});
    });

    test('a missing file is never picked to start', () async {
      missing = {'/m/1.mp3', '/m/2.mp3', '/m/3.mp3', '/m/4.mp3'};
      await engine.setShuffle(true);
      expect(await starts(() => engine.playSongs(five), tries: 20), {'S5'});
    });

    test('adding a list to an empty queue, then Play, starts on any song', () async {
      await engine.setShuffle(true);
      expect(
        await starts(() async {
          await engine.clearQueue();
          await engine.enqueue(five);
          await engine.play();
        }),
        hasLength(5),
      );
    });
  });

  group('from the screens', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late RepositoryPlayerLibrary library;
    late List<int> ids;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      ids = [
        for (var i = 1; i <= 5; i++)
          await repo.addSong(title: 'S$i', artist: 'A', album: 'B', filePath: '/m/$i.mp3', durationSeconds: 100),
      ];
      library = RepositoryPlayerLibrary(repo, fileExists: (_) => true);
      await engine.setShuffle(true);
    });
    tearDown(() => db.close());

    test('on this phone, Play on a list starts anywhere; tapping a song starts there', () async {
      final source = LocalMusicSource(library, engine);
      expect(await starts(() => source.playSongs(ids)), hasLength(5));
      expect(await starts(() => source.playSongs(ids, startSongId: ids[3]), tries: 15), {'S4'});
    });

    test('from another phone too', () async {
      final server = PlayerServer(
        engine: engine,
        deviceName: 'P',
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4,
        library: library,
      );
      await server.start();
      final client = ControllerClient(transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p));
      await client.connect(host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
      final code = server.current.pending!.code;
      server.acceptPairing();
      await client.submitCode(code);
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!client.current.isConnected && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final source = RemoteMusicSource(client);
      expect(await starts(() => source.playSongs(ids), tries: 40), hasLength(greaterThan(1)));
      expect(await starts(() => source.playSongs(ids, startSongId: ids[1]), tries: 10), {'S2'});
      await client.dispose();
      await server.stop();
    });
  });
}
