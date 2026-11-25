import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id, {int duration = 200}) => PlayableSong(
      id: id,
      title: 'S$id',
      artist: 'A',
      album: 'B',
      filePath: '/m/$id.mp3',
      durationSeconds: duration,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the lists', () {
    late AppDatabase db;
    late LibraryRepository repo;
    final ids = <String, int>{};

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      for (final t in ['Alpha', 'Bravo', 'Charlie', 'Delta']) {
        ids[t] = await repo.addSong(
            title: t, artist: 'Ann', album: 'Al', filePath: '/m/$t.mp3', durationSeconds: 100);
      }
    });
    tearDown(() => db.close());

    Future<List<String>> titles(String view) async =>
        [for (final s in (await repo.songs(view: view)).items) s.title];

    test('Most skipped is empty until a song is skipped, then most skipped first', () async {
      expect(await titles(LibraryView.skipped), isEmpty);
      await repo.markSkipped(ids['Charlie']!);
      await repo.markSkipped(ids['Charlie']!);
      await repo.markSkipped(ids['Charlie']!);
      await repo.markSkipped(ids['Alpha']!);
      expect(await titles(LibraryView.skipped), ['Charlie', 'Alpha']);
    });

    test('the counts travel with the song (and only when there are some)', () async {
      await repo.markPlayed(ids['Bravo']!);
      await repo.markPlayed(ids['Bravo']!);
      await repo.markSkipped(ids['Bravo']!);
      final bravo = (await repo.songs(view: LibraryView.top)).items.single;
      final json = bravo.toRemote(available: true).toJson();
      expect(json['plays'], 2);
      expect(json['skips'], 1);
      final alpha = (await repo.songs()).items.firstWhere((s) => s.title == 'Alpha');
      final plain = alpha.toRemote(available: true).toJson();
      expect(plain.containsKey('plays'), isFalse);
      expect(plain.containsKey('skips'), isFalse);
      expect(RemoteSong.fromJson(json).skips, 1);
    });

    test('Never played lists songs with no plays, and a played song leaves it', () async {
      expect((await titles(LibraryView.never)).toSet(), {'Alpha', 'Bravo', 'Charlie', 'Delta'});
      await repo.markPlayed(ids['Delta']!);
      expect((await titles(LibraryView.never)).contains('Delta'), isFalse);
      expect((await titles(LibraryView.never)).length, 3);
    });

    test('resetting forgets plays, skips and when they were played', () async {
      await repo.markPlayed(ids['Alpha']!);
      await repo.markSkipped(ids['Bravo']!);
      expect(await repo.resetListeningStats(), 2);
      expect(await titles(LibraryView.top), isEmpty);
      expect(await titles(LibraryView.skipped), isEmpty);
      expect(await titles(LibraryView.recent), isEmpty);
      expect(await repo.resetListeningStats(), 0);
    });
  });

  group('the engine decides what a skip is', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;
    late List<int> skipped;

    setUp(() {
      backend = FakeAudioBackend();
      skipped = [];
      engine = QueuePlaybackEngine(
        backend: backend,
        fileExists: (_) => true,
        onSongSkipped: skipped.add,
      );
    });
    tearDown(() => engine.dispose());

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    /// Plays [seconds] of the song, a tick at a time (like a real player).
    Future<void> listen(double seconds) async {
      var t = 0.0;
      while (t < seconds) {
        t += 0.5;
        backend.emitPosition(Duration(milliseconds: (t * 1000).round()));
        await Future<void>.delayed(Duration.zero);
      }
      await settle();
    }

    test('pressing next after a few seconds is a skip', () async {
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await listen(5);
      await engine.next();
      expect(skipped, [1]);
    });

    test('moving on after listening for a while is not', () async {
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await listen(45);
      await engine.next();
      expect(skipped, isEmpty);
    });

    test('a song that played to its end is not, however short', () async {
      await engine.playSongs([song(1, duration: 20), song(2), song(3)]);
      await settle();
      await listen(3);
      backend.emitCompleted();
      await settle();
      expect(skipped, isEmpty);
      // The next one is tracked on its own.
      await engine.next();
      expect(skipped, [2]);
    });

    test('a short song is skipped by half its length, not thirty seconds', () async {
      await engine.playSongs([song(1, duration: 20), song(2)]);
      await settle();
      await listen(12);
      await engine.next();
      expect(skipped, isEmpty, reason: '12 of 20 seconds is more than half');
    });

    test('choosing another song counts the same as next', () async {
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await listen(4);
      await engine.playSongs([song(3)]);
      expect(skipped, [1]);
    });

    test('a jump in the position (a seek) is not listening', () async {
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await listen(2);
      backend.emitPosition(const Duration(seconds: 150)); // dragged the bar
      await settle();
      await engine.next();
      expect(skipped, [1], reason: 'only about 2 seconds were really heard');
    });

    test('paused time does not count', () async {
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await listen(10);
      await engine.pause();
      await settle();
      // The bar moves while paused (e.g. a seek on the lock screen): not listening.
      backend.emitPosition(const Duration(seconds: 100));
      await settle();
      await engine.next();
      expect(skipped, [1]);
    });

    test('songs that are not in the library (links) are never counted', () async {
      await engine.playSongs([
        PlayableSong.stream(url: 'https://x/1.mp3', title: 'L', artist: 'A', album: 'B'),
        song(2),
      ]);
      await settle();
      await listen(3);
      await engine.next();
      expect(skipped, isEmpty);
    });
  });
}
