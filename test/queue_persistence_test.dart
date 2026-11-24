import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/drift_queue_store.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late LibraryRepository repo;
  late DriftQueueStore store;
  final ids = <String, int>{};

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    store = DriftQueueStore(db);
    for (final t in ['One', 'Two', 'Three']) {
      ids[t] = await repo.addSong(
          title: t, artist: 'A', album: 'B', filePath: '/m/$t.mp3', durationSeconds: 100);
    }
  });

  tearDown(() => db.close());

  QueuePlaybackEngine newEngine(FakeAudioBackend b) => QueuePlaybackEngine(
      backend: b,
      fileExists: (_) => true,
      queueStore: store,
      urlChecker: FakeUrlChecker());

  Future<List<PlayableSong>> songs(List<String> titles) async =>
      repo.songsByIds([for (final t in titles) ids[t]!]).then(
          (l) => [for (final s in l) s.toPlayable()!]);

  Future<void> afterSave() => Future<void>.delayed(const Duration(milliseconds: 700));

  test('the queue and current song come back after a restart, paused', () async {
    final a = newEngine(FakeAudioBackend());
    await a.playSongs(await songs(['One', 'Two', 'Three']), startIndex: 1);
    await a.next(); // now on Three
    await afterSave();
    await a.dispose();

    final backend = FakeAudioBackend();
    final b = newEngine(backend);
    await b.restoreQueue();
    final q = b.queueSnapshot();
    expect([for (final i in q.items) i.song.title], ['One', 'Two', 'Three']);
    expect(q.items[q.currentIndex].song.title, 'Three');
    expect(b.state.title, 'Three');
    expect(b.state.isPlaying, isFalse, reason: 'it does not start by itself');
    expect(backend.loaded, isEmpty);

    await b.play(); // and Play starts the saved song
    expect(backend.loaded, ['/m/Three.mp3']);
    expect(b.state.isPlaying, isTrue);
    await b.dispose();
  });

  test('changes made just before closing are kept', () async {
    final a = newEngine(FakeAudioBackend());
    await a.playSongs(await songs(['One']));
    await a.enqueue(await songs(['Two']));
    await a.dispose(); // no waiting: dispose saves

    final b = newEngine(FakeAudioBackend());
    await b.restoreQueue();
    expect([for (final i in b.queueSnapshot().items) i.song.title], ['One', 'Two']);
    await b.dispose();
  });

  const jam = 'https://prod-1.storage.jamendo.com/?trackid=11&format=mp32';
  const art = 'https://usercontent.jamendo.com?type=album&id=1&width=200';
  const cc = 'http://creativecommons.org/licenses/by-nc-nd/3.0/';

  test('internet tracks are kept too, in their place among library songs', () async {
    final a = newEngine(FakeAudioBackend());
    await a.playSongs(await songs(['One']));
    await a.enqueue([
      const PlayableSong.stream(
          url: jam, title: 'Web', artist: 'Band', album: 'Rec', licenseUrl: cc, imageUrl: art),
    ]);
    await a.enqueue(await songs(['Two']));
    await a.next(); // now on the internet track
    await afterSave();
    await a.dispose();

    final backend = FakeAudioBackend();
    final b = newEngine(backend);
    await b.restoreQueue();
    final q = b.queueSnapshot();
    expect([for (final i in q.items) i.song.title], ['One', 'Web', 'Two']);
    expect(q.items[q.currentIndex].song.title, 'Web');
    expect(b.state.artist, 'Band');
    expect(b.state.album, 'Rec');
    expect(b.state.source, 'url');
    expect(backend.loadedUrls, isEmpty, reason: 'it does not start by itself');

    await b.play(); // the saved link plays
    expect(backend.loadedUrls, [jam]);
    await b.dispose();
  });

  test('only audio-free text and links are stored for internet tracks', () async {
    final a = newEngine(FakeAudioBackend());
    await a.playUrl(jam, title: 'Web', artist: 'Band', album: 'Rec');
    await afterSave();
    await a.dispose();
    final row = await db.select(db.queueStreams).getSingle();
    expect(row.url, jam);
    expect(row.title, 'Web');
    // Nothing that looks like a file path or audio is stored.
    expect(row.toString().toLowerCase(), isNot(contains('.mp3')));
  });

  test('links read back from the database are re-checked', () async {
    await db.into(db.queueStreams).insert(QueueStreamsCompanion.insert(
          position: 0,
          url: jam,
          title: 'Web',
          artist: 'A',
          album: 'B',
          licenseUrl: const Value('https://evil.example/licence'),
          imageUrl: const Value('https://evil.example/pic.jpg'),
        ));
    final b = newEngine(FakeAudioBackend());
    await b.restoreQueue();
    final song = b.queueSnapshot().items.single.song;
    expect(song.title, 'Web');
    final entry = (await store.load()).songs.single;
    expect(entry.licenseUrl, isNull);
    expect(entry.imageUrl, isNull);
    await b.dispose();
  });

  test('deleting a library song before the current one keeps the right song current',
      () async {
    final a = newEngine(FakeAudioBackend());
    await a.playSongs(await songs(['One', 'Two']));
    await a.enqueue([const PlayableSong.stream(url: jam, title: 'Web')]);
    await a.next();
    await a.next(); // on Web, the third entry
    await afterSave();
    await a.dispose();
    await repo.removeSong(ids['One']!);

    final b = newEngine(FakeAudioBackend());
    await b.restoreQueue();
    final q = b.queueSnapshot();
    expect([for (final i in q.items) i.song.title], ['Two', 'Web']);
    expect(q.items[q.currentIndex].song.title, 'Web');
    await b.dispose();
  });

  test('a song deleted from the library is gone from the saved queue', () async {
    final a = newEngine(FakeAudioBackend());
    await a.playSongs(await songs(['One', 'Two', 'Three']));
    await afterSave();
    await a.dispose();
    await repo.removeSong(ids['Two']!);

    final b = newEngine(FakeAudioBackend());
    await b.restoreQueue();
    expect([for (final i in b.queueSnapshot().items) i.song.title], ['One', 'Three']);
    await b.dispose();
  });

  test('clearing the queue is remembered too', () async {
    final a = newEngine(FakeAudioBackend());
    await a.playSongs(await songs(['One', 'Two']));
    await afterSave();
    await a.clearQueue();
    await afterSave();
    await a.dispose();

    final b = newEngine(FakeAudioBackend());
    await b.restoreQueue();
    expect(b.queueSnapshot().items, isEmpty);
    await b.dispose();
  });

  test('an engine that already has songs is not overwritten by the saved queue',
      () async {
    final a = newEngine(FakeAudioBackend());
    await a.playSongs(await songs(['One', 'Two']));
    await afterSave();
    await a.dispose();

    final b = newEngine(FakeAudioBackend());
    await b.playSongs(await songs(['Three']));
    await b.restoreQueue();
    expect([for (final i in b.queueSnapshot().items) i.song.title], ['Three']);
    await b.dispose();
  });
}
