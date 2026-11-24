import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late LibraryRepository repo;
  late RepositoryPlayerLibrary library;
  late FakeAudioBackend backend;
  late QueuePlaybackEngine engine;
  late PlayerServer server;
  late ControllerClient client;
  late Directory tmp;
  final ids = <String, int>{};

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt_p7_');
    // A real 600x600 picture, so the thumbnail code has something to shrink.
    final art = img.Image(width: 600, height: 600);
    img.fill(art, color: img.ColorRgb8(200, 30, 90));
    final artFile = File('${tmp.path}/cover.png')..writeAsBytesSync(img.encodePng(art));

    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    library = RepositoryPlayerLibrary(repo, fileExists: (_) => true);
    Future<void> add(String title, {String? artPath}) async {
      ids[title] = await repo.addSong(
        title: title,
        artist: 'Ann',
        album: 'Album',
        filePath: '/private/$title.mp3',
        durationSeconds: 100,
        albumArtPath: artPath,
      );
    }

    await add('One', artPath: artFile.path);
    await add('Two');
    await add('Three');

    backend = FakeAudioBackend();
    engine = QueuePlaybackEngine(
      backend: backend,
      fileExists: (_) => true,
      onSongStarted: (id) => unawaited(library.markPlayed(id)),
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
    await waitFor(() => client.current.isConnected);
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
    await engine.dispose();
    await db.close();
    await tmp.delete(recursive: true);
    ids.clear();
  });

  group('favorites', () {
    test('a favorite shows in the Favorites list, in song rows and in state', () async {
      expect((await client.songs(view: LibraryView.favorites)).total, 0);
      await client.setFavorite(ids['Two']!, true);

      final favs = await client.songs(view: LibraryView.favorites);
      expect(favs.items.map((s) => s.title), ['Two']);
      expect(favs.items.single.favorite, isTrue);
      final all = await client.songs();
      expect(all.items.where((s) => s.favorite).map((s) => s.title), ['Two']);

      await client.sendCommand('playSong', {'songId': ids['Two']});
      await waitFor(() => client.current.playback.favorite, reason: 'state says favorite');
      await client.setFavorite(ids['Two']!, false);
      await waitFor(() => !client.current.playback.favorite, reason: 'state cleared');
      expect((await client.songs(view: LibraryView.favorites)).total, 0);
    });

    test('favorites survive in the database', () async {
      await client.setFavorite(ids['One']!, true);
      expect(await repo.favoriteIds(), {ids['One']});
    });
  });

  group('recently played', () {
    test('songs appear newest first once they start playing', () async {
      expect((await client.songs(view: LibraryView.recent)).total, 0);
      await client.sendCommand('playSong', {'songId': ids['One']});
      await waitFor(() => client.current.playback.title == 'One');
      // Drift stores times in whole seconds.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await client.sendCommand('playSong', {'songId': ids['Three']});
      await waitFor(() => client.current.playback.title == 'Three');
      var recent = await client.songs(view: LibraryView.recent);
      for (var i = 0; i < 50 && recent.total < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        recent = await client.songs(view: LibraryView.recent);
      }
      expect(recent.items.map((s) => s.title), ['Three', 'One']);
    });
  });

  group('playlists', () {
    Future<int> make(String name) async {
      final r = await client.sendCommandForResult('createPlaylist', {'name': name});
      return (r['playlistId'] as num).toInt();
    }

    test('create, fill in order, skip duplicates, list with counts', () async {
      final id = await make('  Road   trip ');
      final added = await client.sendCommandForResult('addToPlaylist', {
        'playlistId': id,
        'songIds': [ids['Three'], ids['One'], ids['Three']],
      });
      expect(added['added'], 2);

      final lists = await client.playlists();
      expect(lists.items.single.name, 'Road trip');
      expect(lists.items.single.songCount, 2);

      final songs = await client.songs(playlistId: id);
      expect(songs.items.map((s) => s.title), ['Three', 'One']); // added order
      // Adding again later goes to the end.
      await client.sendCommand('addToPlaylist', {'playlistId': id, 'songIds': [ids['Two']]});
      expect((await client.songs(playlistId: id)).items.map((s) => s.title),
          ['Three', 'One', 'Two']);
    });

    test('rename, remove a song, delete (songs stay in the library)', () async {
      final id = await make('Mix');
      await client.sendCommand('addToPlaylist',
          {'playlistId': id, 'songIds': [ids['One'], ids['Two']]});
      await client.sendCommand('renamePlaylist', {'playlistId': id, 'name': 'Better mix'});
      expect((await client.playlists()).items.single.name, 'Better mix');

      await client.sendCommand(
          'removeFromPlaylist', {'playlistId': id, 'songId': ids['One']});
      expect((await client.songs(playlistId: id)).items.map((s) => s.title), ['Two']);

      await client.sendCommand('deletePlaylist', {'playlistId': id});
      expect((await client.playlists()).total, 0);
      expect((await client.songs()).total, 3);
    });

    test('deleting a song removes it from playlists', () async {
      final id = await make('Mix');
      await client.sendCommand('addToPlaylist',
          {'playlistId': id, 'songIds': [ids['One'], ids['Two']]});
      await repo.removeSong(ids['One']!);
      expect((await client.songs(playlistId: id)).items.map((s) => s.title), ['Two']);
      expect((await client.playlists()).items.single.songCount, 1);
    });

    test('bad names and missing playlists are refused in plain words', () async {
      await expectLater(
          client.sendCommand('createPlaylist', {'name': '   '}),
          throwsA(isA<ControllerException>()));
      await expectLater(
          client.sendCommand('createPlaylist', {'name': 'x' * 61}),
          throwsA(isA<ControllerException>()));
      await expectLater(
          client.sendCommand('deletePlaylist', {'playlistId': 999}),
          throwsA(isA<ControllerException>()));
      await expectLater(
          client.sendCommand('addToPlaylist', {'playlistId': 999, 'songIds': [1]}),
          throwsA(isA<ControllerException>()));
      await expectLater(
          client.sendCommand('renamePlaylist', {'playlistId': 999, 'name': 'a'}),
          throwsA(isA<ControllerException>()));
    });
  });

  group('play now keeps the queue', () {
    test('a single song goes in after the current one and plays', () async {
      await client.sendCommand('playSong',
          {'songIds': [ids['One'], ids['Two']], 'songId': ids['One']});
      await waitFor(() => client.current.playback.title == 'One');

      await client.sendCommand(
          'playSong', {'songId': ids['Three'], 'keepQueue': true});
      await waitFor(() => client.current.playback.title == 'Three');

      final q = await client.getQueue();
      expect([for (final i in q.items) i.song.title], ['One', 'Three', 'Two']);
      expect(q.items[q.currentIndex].song.title, 'Three');
    });

    test('with an empty queue it just plays the song', () async {
      await client.sendCommand(
          'playSong', {'songId': ids['Two'], 'keepQueue': true});
      await waitFor(() => client.current.playback.title == 'Two');
      expect((await client.getQueue()).items, hasLength(1));
    });

    test('without keepQueue the queue is replaced, as before', () async {
      await client.sendCommand('playSong',
          {'songIds': [ids['One'], ids['Two']], 'songId': ids['One']});
      await client.sendCommand('playSong', {'songId': ids['Three']});
      await waitFor(() => client.current.playback.title == 'Three');
      expect((await client.getQueue()).items, hasLength(1));
    });
  });

  group('playback speed', () {
    test('the Player changes speed and reports it', () async {
      await client.sendCommand('playSong', {'songId': ids['One']});
      await waitFor(() => client.current.playback.title == 'One');
      await client.setSpeed(1.5);
      await waitFor(() => client.current.playback.speed == 1.5, reason: 'speed in state');
      expect(backend.speed, 1.5);

      // It is kept for the next song.
      await client.sendCommand('playSong', {'songId': ids['Two']});
      await waitFor(() => client.current.playback.title == 'Two');
      expect(backend.speed, 1.5);
      await client.setSpeed(1.0);
      await waitFor(() => client.current.playback.speed == 1.0);
    });

    test('out-of-range speeds are refused', () async {
      await expectLater(client.setSpeed(3), throwsA(isA<ControllerException>()));
      await expectLater(client.setSpeed(0.1), throwsA(isA<ControllerException>()));
      expect(backend.speed, 1.0);
    });
  });

  group('album art', () {
    test('the Controller gets a small JPEG, never the file path', () async {
      final bytes = await client.artFor(ids['One']!);
      expect(bytes, isNotNull);
      final decoded = img.decodeImage(bytes!);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(256));
      expect(bytes.length, lessThan(60 * 1024));
      // JPEG signature.
      expect(bytes.sublist(0, 2), Uint8List.fromList([0xFF, 0xD8]));
    });

    test('list rows ask for a small picture, and sizes are kept in range', () async {
      final small = await client.artFor(ids['One']!, size: 96);
      final big = await client.artFor(ids['One']!);
      final s = img.decodeImage(small!)!;
      expect(s.width, lessThanOrEqualTo(96));
      expect(small.length, lessThan(big!.length));
      // Absurd sizes are clamped to 48..256 instead of failing.
      final tiny = img.decodeImage((await client.artFor(ids['One']!, size: 1))!)!;
      expect(tiny.width, 48);
      final huge = img.decodeImage((await client.artFor(ids['One']!, size: 99999))!)!;
      expect(huge.width, 256);
    });

    test('many pictures at once all arrive (a few at a time)', () async {
      final results = await Future.wait([
        for (var i = 0; i < 12; i++) client.artFor(ids['One']!, size: 48 + i),
      ]);
      expect(results.every((r) => r != null), isTrue);
    });

    test('many rows asking for the same album share one picture', () async {
      final all = await Future.wait([
        for (var i = 0; i < 12; i++) library.artThumbnail(ids['One']!, size: 96),
      ]);
      expect(all.every((b) => b != null), isTrue);
      expect(all.every((b) => identical(b, all.first)), isTrue,
          reason: 'one job, not twelve');
    });

    test('a song without art, or an unknown song, gives null', () async {
      expect(await client.artFor(ids['Two']!), isNull);
      expect(await client.artFor(99999), isNull);
    });
  });

  test('upgrading a version 2 database keeps the library and adds the new tables',
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
          CHECK ((file_path IS NULL) <> (url IS NULL))
        )''');
      raw.execute("INSERT INTO songs (title, artist, album, file_path, source) "
          "VALUES ('Old song', 'A', 'B', '/x.mp3', 'localFile')");
      raw.execute('PRAGMA user_version = 2');
    }));
    final r = LibraryRepository(old);
    final songs = await r.songs();
    expect(songs.items.single.title, 'Old song');
    expect(songs.items.single.favorite, isFalse);
    expect(songs.items.single.lastPlayedAt, isNull);
    final id = await r.createPlaylist('After upgrade');
    expect(await r.addToPlaylist(id, [songs.items.single.id]), 1);
    await old.close();
  });
}
