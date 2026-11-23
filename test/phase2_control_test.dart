import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/constants.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';

Future<void> waitFor(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5), String? reason}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: ${reason ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late FakeAudioBackend backend;
  late QueuePlaybackEngine engine;
  late PlayerServer server;
  late ControllerClient client;
  final extras = <Object>[];
  final ids = <String, int>{};

  Future<void> addSong(String title, String artist, String album, int track) async {
    ids[title] = await repo.addSong(
      title: title,
      artist: artist,
      album: album,
      trackNumber: track,
      filePath: '/private/music/$title.mp3',
      durationSeconds: 100 + track,
      albumArtPath: '/private/art/$album.jpg',
    );
  }

  Future<void> startAll({PlaybackEngine? customEngine, bool withLibrary = true}) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    await addSong('Alpha One', 'Ann', 'First Album', 1);
    await addSong('Alpha Two', 'Ann', 'First Album', 2);
    await addSong('Beta One', 'Bob', 'Second Album', 1);
    await addSong('Gamma One', 'Cy', 'Third Album', 1);

    backend = FakeAudioBackend();
    engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
    server = PlayerServer(
      engine: customEngine ?? engine,
      deviceName: 'Test Player',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      library: withLibrary
          ? RepositoryPlayerLibrary(repo, fileExists: (_) => true)
          : null,
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
  }

  tearDown(() async {
    await client.dispose();
    await server.stop();
    await engine.dispose();
    await db.close();
    for (final e in extras) {
      if (e is LocalWebSocketTransport) await e.disconnect();
    }
    extras.clear();
    ids.clear();
  });

  group('library browsing', () {
    setUp(() async => startAll());

    test('songs: paged, searchable, filtered by artist/album', () async {
      final all = await client.songs(limit: 3);
      expect(all.total, 4);
      expect(all.items.map((s) => s.title), ['Alpha One', 'Alpha Two', 'Beta One']);
      expect(all.hasMore, isTrue);
      final rest = await client.songs(offset: 3, limit: 3);
      expect(rest.items.map((s) => s.title), ['Gamma One']);

      expect((await client.songs(query: 'beta')).items.single.title, 'Beta One');
      expect((await client.songs(artist: 'Ann')).total, 2);
      expect((await client.songs(album: 'First Album')).items.map((s) => s.trackNumber),
          [1, 2]);
      expect((await client.songs(query: 'nothing')).total, 0);

      final s = all.items.first;
      expect(s.artist, 'Ann');
      expect(s.album, 'First Album');
      expect(s.durationSeconds, 101);
      expect(s.available, isTrue);
    });

    test('artists and albums', () async {
      final artists = await client.artists();
      expect(artists.items.map((a) => a.name), ['Ann', 'Bob', 'Cy']);
      expect(artists.items.first.songCount, 2);
      final albums = await client.albums(artist: 'Ann');
      expect(albums.items.single.name, 'First Album');
      expect(albums.items.single.songCount, 2);
      expect((await client.albums(query: 'third')).items.single.artist, 'Cy');
    });

    test('file paths and art paths never appear on the wire', () async {
      final inbox = <String>[];
      final raw = LocalWebSocketTransport(host: '127.0.0.1', port: server.current.port!);
      extras.add(raw);
      // Second connection must not see anything without a session.
      await raw.connect();
      raw.messages.listen((m) => inbox.add(m.encode()));
      await raw.send(RemoteMessage(
        type: MessageType.hello,
        requestId: 'h',
        payload: {'protocolVersion': AppConstants.protocolVersion, 'deviceName': 'x'},
      ));
      await raw.send(RemoteMessage(
        type: MessageType.libraryRequest,
        requestId: 'l',
        payload: {'scope': 'songs'},
      ));
      await waitFor(() => inbox.any((m) => m.contains('NOT_PAIRED')));
      expect(inbox.join(), isNot(contains('/private')));

      // And the authenticated responses are clean too: use the client's own
      // decoded objects and re-encode everything we got.
      final page = await client.songs();
      final queue = () async {
        await client.sendCommand(RemoteActions.queueSong, {'songId': ids['Alpha One']});
        return client.getQueue();
      }();
      final snap = await queue;
      final text = '${page.items.map((e) => e.toJson())} ${snap.toJson()} '
          '${client.current.playback.toJson()}';
      expect(text, isNot(contains('/private')));
      expect(text, isNot(contains('.mp3')));
      expect(text, isNot(contains('.jpg')));
    });

    test('bad library requests get errors, not crashes', () async {
      await expectLater(
        client.songs(offset: -5, limit: 1000), // clamped, still works
        completes,
      );
      final page = await client.songs(limit: 1000);
      expect(page.items.length, 4);

      final reply = Completer<RemoteMessage>();
      final raw = LocalWebSocketTransport(host: '127.0.0.1', port: server.current.port!);
      extras.add(raw);
      await raw.connect();
      raw.messages.listen((m) {
        if (m.requestId == 'bad' && !reply.isCompleted) reply.complete(m);
      });
      await raw.send(RemoteMessage(
        type: MessageType.hello,
        payload: {'protocolVersion': AppConstants.protocolVersion},
      ));
      await raw.send(RemoteMessage(
        type: MessageType.libraryRequest,
        requestId: 'bad',
        payload: {'scope': 'songs'},
      ));
      expect((await reply.future).errorCode, ErrorCodes.notPaired);
    });
  });

  group('queue commands', () {
    setUp(() async => startAll());

    test('playSong with a list starts at the chosen song and queues the rest',
        () async {
      final albumIds = [ids['Alpha One']!, ids['Alpha Two']!, ids['Beta One']!];
      await client.sendCommand(RemoteActions.playSong,
          {'songId': ids['Alpha Two'], 'songIds': albumIds});
      await waitFor(() => client.current.playback.title == 'Alpha Two');
      expect(client.current.playback.isPlaying, isTrue);
      expect(client.current.playback.queueIndex, 1);
      expect(client.current.playback.queueLength, 3);
      expect(client.current.playback.songId, ids['Alpha Two']);

      final q = await client.getQueue();
      expect(q.items.map((i) => i.song.title), ['Alpha One', 'Alpha Two', 'Beta One']);
      expect(q.currentIndex, 1);
      expect(q.items[1].isCurrent, isTrue);
      expect(backend.currentPath, '/private/music/Alpha Two.mp3');
    });

    test('playSong with a single id plays just that song', () async {
      await client.sendCommand(RemoteActions.playSong, {'songId': ids['Gamma One']});
      await waitFor(() => client.current.playback.title == 'Gamma One');
      expect(client.current.playback.queueLength, 1);
    });

    test('queueSong appends or inserts after the current one, without starting',
        () async {
      await client.sendCommand(RemoteActions.queueSong, {'songId': ids['Alpha One']});
      await waitFor(() => client.current.playback.queueLength == 1);
      expect(client.current.playback.isPlaying, isFalse);
      expect(client.current.playback.title, 'Alpha One');

      await client.sendCommand(RemoteActions.queueSong, {
        'songIds': [ids['Beta One'], ids['Gamma One']],
      });
      await client.sendCommand(RemoteActions.queueSong,
          {'songId': ids['Alpha Two'], 'playNext': true});
      final q = await client.getQueue();
      expect(q.items.map((i) => i.song.title),
          ['Alpha One', 'Alpha Two', 'Beta One', 'Gamma One']);

      await client.sendCommand(RemoteActions.play);
      await waitFor(() => client.current.playback.isPlaying);
    });

    test('queue revision in state tells the Controller when to refetch', () async {
      await client.sendCommand(RemoteActions.queueSong, {'songId': ids['Alpha One']});
      await waitFor(() => client.current.playback.queueRevision > 0);
      final r = client.current.playback.queueRevision;
      await client.sendCommand(RemoteActions.queueSong, {'songId': ids['Beta One']});
      await waitFor(() => client.current.playback.queueRevision > r);
    });

    test('remove, move, jump, clear', () async {
      await client.sendCommand(RemoteActions.playSong, {
        'songId': ids['Alpha One'],
        'songIds': [ids['Alpha One'], ids['Alpha Two'], ids['Beta One']],
      });
      var q = await client.getQueue();
      final entry = q.items.map((i) => i.queueItemId).toList();

      await client.sendCommand(
          RemoteActions.moveQueueItem, {'queueItemId': entry[0], 'newIndex': 2});
      q = await client.getQueue();
      expect(q.items.map((i) => i.song.title), ['Alpha Two', 'Beta One', 'Alpha One']);
      expect(q.currentIndex, 2, reason: 'the playing song moved with its entry');

      await client.sendCommand(RemoteActions.playQueueItem, {'queueItemId': entry[1]});
      await waitFor(() => client.current.playback.title == 'Alpha Two');

      await client.sendCommand(RemoteActions.removeQueueItem, {'queueItemId': entry[2]});
      q = await client.getQueue();
      expect(q.items, hasLength(2));

      await client.sendCommand(RemoteActions.clearQueue);
      q = await client.getQueue();
      expect(q.items, isEmpty);
      await waitFor(() => !client.current.playback.isPlaying);
      expect(client.current.playback.queueLength, 0);
    });

    test('shuffle and repeat are set remotely and reported back', () async {
      await client.sendCommand(RemoteActions.playSong, {
        'songId': ids['Alpha One'],
        'songIds': ids.values.toList(),
      });
      await client.sendCommand(RemoteActions.setShuffle, {'enabled': true});
      await client.sendCommand(RemoteActions.setRepeatMode, {'mode': 'queue'});
      await waitFor(() =>
          client.current.playback.shuffleEnabled &&
          client.current.playback.repeatMode == RepeatMode.queue);
      final q = await client.getQueue();
      expect(q.shuffle, isTrue);
      expect(q.repeat, RepeatMode.queue);
    });

    test('invalid arguments are rejected with INVALID_ACTION', () async {
      Future<void> expectInvalid(String action, Map<String, dynamic> p) =>
          expectLater(
            client.sendCommand(action, p),
            throwsA(isA<ControllerException>()
                .having((e) => e.code, 'code', ErrorCodes.invalidAction)),
          );
      await expectInvalid(RemoteActions.playSong, {});
      await expectInvalid(RemoteActions.playSong, {'songIds': []});
      await expectInvalid(RemoteActions.queueSong, {'songId': 'abc'});
      await expectInvalid(RemoteActions.removeQueueItem, {});
      await expectInvalid(RemoteActions.removeQueueItem, {'queueItemId': 9999});
      await expectInvalid(RemoteActions.setRepeatMode, {'mode': 'sometimes'});
      await expectInvalid(RemoteActions.setShuffle, {'enabled': 'yes'});
      await expectInvalid(
          RemoteActions.playSong, {'songIds': List.filled(2001, 1)});
      expect(client.current.isConnected, isTrue);
    });

    test('unknown song ids report FILE_NOT_FOUND', () async {
      await expectLater(
        client.sendCommand(RemoteActions.playSong, {'songId': 424242}),
        throwsA(isA<ControllerException>()
            .having((e) => e.code, 'code', ErrorCodes.fileNotFound)),
      );
    });

    test('play with an empty queue reports QUEUE_EMPTY', () async {
      await expectLater(
        client.sendCommand(RemoteActions.play),
        throwsA(isA<ControllerException>()
            .having((e) => e.code, 'code', ErrorCodes.queueEmpty)),
      );
    });

    test('normal transport controls still work on the real engine', () async {
      await client.sendCommand(RemoteActions.playSong, {
        'songId': ids['Alpha One'],
        'songIds': [ids['Alpha One'], ids['Alpha Two']],
      });
      await client.sendCommand(RemoteActions.seek, {'positionSeconds': 30});
      await waitFor(() => client.current.playback.positionSeconds == 30);
      await client.sendCommand(RemoteActions.setVolume, {'volume': 0.4});
      await waitFor(() => (client.current.playback.volume - 0.4).abs() < 1e-9);
      await client.sendCommand(RemoteActions.next);
      await waitFor(() => client.current.playback.title == 'Alpha Two');
      await client.sendCommand(RemoteActions.toggle);
      await waitFor(() => !client.current.playback.isPlaying);
    });
  });

  group('compatibility', () {
    test('queue commands are refused by an engine without a queue', () async {
      final simulated = SimulatedPlaybackEngine(autoTick: false);
      await startAll(customEngine: simulated);
      await expectLater(
        client.sendCommand(RemoteActions.clearQueue),
        throwsA(isA<ControllerException>()
            .having((e) => e.code, 'code', ErrorCodes.invalidAction)),
      );
      // Phase 1 controls keep working.
      await client.sendCommand(RemoteActions.play);
      await waitFor(() => client.current.playback.isPlaying);
      await simulated.dispose();
    });

    test('a Player with no library refuses library requests and song commands',
        () async {
      await startAll(withLibrary: false);
      await expectLater(client.songs(), throwsA(isA<ControllerException>()));
      await expectLater(
        client.sendCommand(RemoteActions.playSong, {'songId': 1}),
        throwsA(isA<ControllerException>()),
      );
    });
  });
}
