import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/music/local_music_source.dart';
import 'package:remote_tunes/features/music/music_source.dart';
import 'package:remote_tunes/features/music/queue_view.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';
import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi;

Future<void> waitFor(bool Function() c, {String? reason}) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

const jam = 'https://prod-1.storage.jamendo.com/?trackid=11&format=mp32';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('over the protocol', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late QueuePlaybackEngine engine;
    late PlayerServer server;
    late ControllerClient client;
    final ids = <String, int>{};

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      for (final t in ['One', 'Two', 'Three']) {
        ids[t] = await repo.addSong(
            title: t, artist: 'A', album: 'B', filePath: '/m/$t.mp3', durationSeconds: 100);
      }
      engine = QueuePlaybackEngine(
          backend: FakeAudioBackend(), fileExists: (_) => true, urlChecker: FakeUrlChecker());
      server = PlayerServer(
        engine: engine,
        deviceName: 'P',
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4,
        library: RepositoryPlayerLibrary(repo, fileExists: (_) => true),
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
      await db.close();
    });

    Future<List<String>> titlesOf(int playlistId) async =>
        [for (final s in (await client.songs(playlistId: playlistId)).items) s.title];

    test('the queue becomes a playlist, in queue order', () async {
      await client.sendCommand('playSong', {
        'songIds': [ids['Three'], ids['One'], ids['Two']],
        'songId': ids['Three'],
      });
      final source = RemoteMusicSource(client);
      final r = await source.saveQueueAsPlaylist('  Road   trip ');
      expect(r.added, 3);
      expect(r.skipped, 0);

      final lists = (await client.playlists()).items;
      expect(lists.single.name, 'Road trip');
      expect(lists.single.songCount, 3);
      expect(await titlesOf(lists.single.id), ['Three', 'One', 'Two']);
    });

    test('a song queued twice is listed once; internet tracks are left out', () async {
      await client.sendCommand('playSong', {
        'songIds': [ids['One'], ids['Two'], ids['One']],
        'songId': ids['One'],
      });
      await client.playUrl(jam, title: 'Web track', queue: true);
      final r = await RemoteMusicSource(client).saveQueueAsPlaylist('Mix');
      expect(r.added, 2, reason: 'One appears twice in the queue');
      expect(r.skipped, 1, reason: 'the internet track');
      final id = (await client.playlists()).items.single.id;
      expect(await titlesOf(id), ['One', 'Two']);
    });

    test('the queue itself is not changed', () async {
      await client.sendCommand('playSong', {
        'songIds': [ids['One'], ids['Two']],
        'songId': ids['One'],
      });
      await RemoteMusicSource(client).saveQueueAsPlaylist('Mix');
      final q = await client.getQueue();
      expect([for (final i in q.items) i.song.title], ['One', 'Two']);
    });

    test('an empty queue is refused, and no playlist is made', () async {
      await expectLater(
        RemoteMusicSource(client).saveQueueAsPlaylist('Mix'),
        throwsA(isA<ControllerException>()
            .having((e) => e.message, 'message', contains('queue is empty'))),
      );
      expect((await client.playlists()).total, 0);
    });

    test('a queue of only internet tracks is refused in plain words', () async {
      await client.playUrl(jam, title: 'Web track', queue: true);
      await expectLater(
        RemoteMusicSource(client).saveQueueAsPlaylist('Mix'),
        throwsA(isA<ControllerException>()
            .having((e) => e.message, 'message', contains('only internet tracks'))),
      );
      expect((await client.playlists()).total, 0);
    });

    test('a bad name is refused before anything is made', () async {
      await client.sendCommand('playSong', {
        'songIds': [ids['One']],
        'songId': ids['One'],
      });
      for (final bad in ['   ', 'x' * 61]) {
        await expectLater(RemoteMusicSource(client).saveQueueAsPlaylist(bad),
            throwsA(isA<ControllerException>()));
      }
      expect((await client.playlists()).total, 0);
    });

    test('the Player can do the same from its own screen', () async {
      await client.sendCommand('playSong', {
        'songIds': [ids['Two'], ids['One']],
        'songId': ids['Two'],
      });
      final local = LocalMusicSource(
          RepositoryPlayerLibrary(repo, fileExists: (_) => true), engine);
      final r = await local.saveQueueAsPlaylist('From the Player');
      expect(r.added, 2);
      final id = (await repo.playlists()).items.single.id;
      expect(
          [for (final s in (await repo.songs(playlistId: id)).items) s.title], ['Two', 'One']);
    });
  });

  group('the queue screen', () {
    RemoteQueueItem item(int id, String title, {int songId = 1}) => RemoteQueueItem(
          queueItemId: id,
          isCurrent: false,
          song: RemoteSong(id: songId, title: title, artist: 'A', album: 'B'),
        );

    Widget screen(FakeMusicSource s) => host(QueueView(
          source: s,
          revision: 1,
          currentIndex: -1,
          shuffle: false,
          repeat: RepeatMode.off,
          enabled: true,
        ));

    testWidgets('the button is off for an empty queue', (tester) async {
      await tester.pumpWidget(screen(FakeMusicSource()));
      await settleUi(tester);
      final b = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.playlist_add_rounded));
      expect(b.onPressed, isNull);
    });

    testWidgets('asks for a name (with a sensible default) and says what it saved',
        (tester) async {
      final s = FakeMusicSource(queue: [item(1, 'One', songId: 1), item(2, 'Two', songId: 2)]);
      await tester.pumpWidget(screen(s));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Save queue as a playlist'));
      await tester.pumpAndSettle();
      expect(find.text('Save queue as a playlist'), findsWidgets);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, startsWith('Queue '));

      await tester.enterText(find.byType(TextField), 'Friday mix');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(s.calls, ['saveQueue Friday mix']);
      expect(find.text('Saved 2 songs as "Friday mix"'), findsOneWidget);
    });

    testWidgets('internet tracks left out are mentioned', (tester) async {
      final s = FakeMusicSource(queue: [
        item(1, 'One', songId: 1),
        item(2, 'Web', songId: 0),
        item(3, 'Web 2', songId: 0),
      ]);
      await tester.pumpWidget(screen(s));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Save queue as a playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved 1 song as'), findsOneWidget);
      expect(find.textContaining('(2 internet tracks left out)'), findsOneWidget);
    });

    testWidgets('cancel saves nothing', (tester) async {
      final s = FakeMusicSource(queue: [item(1, 'One')]);
      await tester.pumpWidget(screen(s));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Save queue as a playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(s.calls, isEmpty);
    });

    testWidgets('a refusal is shown, not swallowed', (tester) async {
      final s = FakeMusicSource(queue: [item(1, 'One')]);
      await tester.pumpWidget(screen(s));
      await settleUi(tester);
      s.failWith = ControllerException('Give the playlist a name.');
      // (loading the queue already happened; only saving fails now)
      await tester.tap(find.byTooltip('Save queue as a playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Give the playlist a name.'), findsOneWidget);
    });
  });
}
