import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/data/repositories/online_history_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';

Future<void> waitFor(bool Function() c, {String? reason}) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

String jam(int id) => 'https://prod-1.storage.jamendo.com/?trackid=$id&format=mp32';
const art = 'https://usercontent.jamendo.com?type=album&id=1&width=200';
const cc = 'http://creativecommons.org/licenses/by-nc-nd/3.0/';

PlayableSong track(int id, {String? image = art, String? license = cc}) =>
    PlayableSong.stream(
        url: jam(id),
        title: 'Song $id',
        artist: 'Band',
        album: 'Rec',
        imageUrl: image,
        licenseUrl: license);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late OnlineHistoryRepository history;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    history = OnlineHistoryRepository(db);
  });
  tearDown(() => db.close());

  group('the history store', () {
    test('is on by default and remembers what was played, newest first', () async {
      expect(await history.isEnabled(), isTrue);
      await history.record(track(1));
      await Future<void>.delayed(const Duration(milliseconds: 1100)); // whole seconds
      await history.record(track(2));
      final page = await history.list();
      expect(page.items.map((e) => e.title), ['Song 2', 'Song 1']);
      expect(page.total, 2);
      final e = page.items.first;
      expect(e.artist, 'Band');
      expect(e.album, 'Rec');
      expect(e.licenseUrl, cc);
      expect(e.imageUrl, art);
      expect(e.playedAtSeconds, greaterThan(0));
    });

    test('playing a track again moves it up instead of adding a copy', () async {
      await history.record(track(1));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await history.record(track(2));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await history.record(track(1));
      final page = await history.list();
      expect(page.items.map((e) => e.title), ['Song 1', 'Song 2']);
    });

    test('only Online Library tracks are kept', () async {
      await history.record(const PlayableSong.stream(
          url: 'https://example.com/radio.mp3', title: 'Radio'));
      await history.record(const PlayableSong(
          id: 5, title: 'Local', artist: 'A', album: 'B', filePath: '/x.mp3'));
      expect((await history.list()).total, 0);
    });

    test('while it is off nothing is recorded, and turning it on resumes', () async {
      await history.setEnabled(false);
      expect(await history.isEnabled(), isFalse);
      await history.record(track(1));
      expect((await history.list()).total, 0);
      await history.setEnabled(true);
      await history.record(track(2));
      expect((await history.list()).total, 1);
    });

    test('remove one entry, or clear all', () async {
      await history.record(track(1));
      await history.record(track(2));
      final first = (await history.list()).items.first;
      await history.remove(first.id);
      expect((await history.list()).total, 1);
      await history.clear();
      expect((await history.list()).total, 0);
    });

    test('it is capped, dropping the oldest', () async {
      for (var i = 1; i <= OnlineHistoryRepository.maxEntries + 5; i++) {
        await history.record(track(i));
      }
      final page = await history.list(limit: 500);
      expect(page.total, OnlineHistoryRepository.maxEntries);
    });

    test('artwork and licence links that are not Jamendo / Creative Commons are dropped',
        () async {
      await history.record(
          track(1, image: 'https://evil.example/p.jpg', license: 'https://evil.example/l'));
      final e = (await history.list()).items.single;
      expect(e.imageUrl, isNull);
      expect(e.licenseUrl, isNull);
    });

    test('the paging works', () async {
      for (var i = 1; i <= 5; i++) {
        await history.record(track(i));
      }
      final page = await history.list(offset: 3, limit: 10);
      expect(page.items, hasLength(2));
      expect(page.total, 5);
    });
  });

  group('over the protocol', () {
    late FakeAudioBackend backend;
    late FakeUrlChecker checker;
    late QueuePlaybackEngine engine;
    late PlayerServer server;
    late ControllerClient client;

    setUp(() async {
      backend = FakeAudioBackend();
      checker = FakeUrlChecker();
      final library = RepositoryPlayerLibrary(LibraryRepository(db), history: history);
      engine = QueuePlaybackEngine(
        backend: backend,
        fileExists: (_) => true,
        urlChecker: checker,
        onStreamStarted: (s) => library.recordStream(s),
      );
      server = PlayerServer(
        engine: engine,
        deviceName: 'P',
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4,
        library: library,
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

    Future<List<String>> titles() async =>
        [for (final e in (await client.onlineHistory()).page.items) e.title];

    test('playing a Jamendo track from the Controller adds it to the history', () async {
      await client.playUrl(jam(1),
          title: 'Song 1', artist: 'Band', album: 'Rec', licenseUrl: cc, imageUrl: art);
      await waitFor(() => client.current.playback.title == 'Song 1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final r = await client.onlineHistory();
      expect(r.enabled, isTrue);
      expect(r.page.items.single.title, 'Song 1');
      expect(r.page.items.single.licenseUrl, cc);
      expect(r.page.items.single.imageUrl, art);
    });

    test('a track only lined up in the queue is not history until it plays', () async {
      await client.playUrl(jam(1), title: 'Song 1', queue: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await titles(), isEmpty);
    });

    test('the stream link is never sent to the Controller', () async {
      await client.playUrl(jam(1), title: 'Song 1');
      await waitFor(() => client.current.playback.title == 'Song 1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final raw = (await client.onlineHistory()).page.items.single.toJson().toString();
      expect(raw, isNot(contains('prod-1.storage')));
      expect(raw, isNot(contains('trackid')));
    });

    test('play it again from the history, and add another to the queue', () async {
      await client.playUrl(jam(1), title: 'Song 1', artist: 'Band', album: 'Rec');
      await waitFor(() => client.current.playback.title == 'Song 1');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await client.playUrl(jam(2), title: 'Song 2');
      await waitFor(() => client.current.playback.title == 'Song 2');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final items = (await client.onlineHistory()).page.items;
      final first = items.firstWhere((e) => e.title == 'Song 1');
      await client.playHistory(first.id);
      await waitFor(() => client.current.playback.title == 'Song 1', reason: 'replayed');
      expect(backend.loadedUrls.last, jam(1), reason: 'the Player used its own saved link');
      expect(client.current.playback.artist, 'Band');

      final second = items.firstWhere((e) => e.title == 'Song 2');
      await client.playHistory(second.id, queue: true);
      final q = await client.getQueue();
      expect([for (final i in q.items) i.song.title], ['Song 1', 'Song 2']);
    });

    test('a removed entry cannot be played, with a plain message', () async {
      await expectLater(client.playHistory(9999),
          throwsA(isA<ControllerException>().having((e) => e.message, 'm', contains('no longer'))));
    });

    test('remove, clear and the on/off switch work from the Controller', () async {
      await client.playUrl(jam(1), title: 'Song 1');
      await waitFor(() => client.current.playback.title == 'Song 1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final id = (await client.onlineHistory()).page.items.single.id;
      await client.removeHistory(id);
      expect(await titles(), isEmpty);

      await client.setHistoryEnabled(false);
      expect((await client.onlineHistory()).enabled, isFalse);
      await client.playUrl(jam(2), title: 'Song 2');
      await waitFor(() => client.current.playback.title == 'Song 2');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await titles(), isEmpty, reason: 'off means off');

      await client.setHistoryEnabled(true);
      await client.playUrl(jam(3), title: 'Song 3');
      await waitFor(() => client.current.playback.title == 'Song 3');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await titles(), ['Song 3']);
      await client.clearHistory();
      expect(await titles(), isEmpty);
    });

    test('links to other sites for art and licence are not accepted from a Controller',
        () async {
      await client.playUrl(jam(1),
          title: 'Song 1',
          licenseUrl: 'https://evil.example/l',
          imageUrl: 'https://evil.example/p.jpg');
      await waitFor(() => client.current.playback.title == 'Song 1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final e = (await client.onlineHistory()).page.items.single;
      expect(e.licenseUrl, isNull);
      expect(e.imageUrl, isNull);
    });
  });

  test('upgrading a version 3 database keeps everything and adds the new tables',
      () async {
    final old = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('''
        CREATE TABLE songs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL, artist TEXT, album TEXT,
          duration_seconds INTEGER, track_number INTEGER,
          file_path TEXT, url TEXT, album_art_path TEXT,
          file_size_bytes INTEGER, mime_type TEXT,
          source TEXT NOT NULL,
          added_at INTEGER NOT NULL DEFAULT 0,
          favorite INTEGER NOT NULL DEFAULT 0,
          last_played_at INTEGER,
          CHECK ((file_path IS NULL) <> (url IS NULL))
        )''');
      raw.execute('CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, '
          'value TEXT NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0)');
      raw.execute("INSERT INTO songs (title, artist, album, file_path, source, favorite) "
          "VALUES ('Old song', 'A', 'B', '/x.mp3', 'localFile', 1)");
      raw.execute('PRAGMA user_version = 3');
    }));
    final r = LibraryRepository(old);
    final songs = await r.songs();
    expect(songs.items.single.title, 'Old song');
    expect(songs.items.single.favorite, isTrue);
    final h = OnlineHistoryRepository(old);
    await h.record(track(1));
    expect((await h.list()).total, 1);
    expect(await old.select(old.queueStreams).get(), isEmpty);
    await old.close();
  });
}
