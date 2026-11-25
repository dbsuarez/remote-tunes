import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/insights/insights_data.dart';
import 'package:remote_tunes/features/insights/insights_screen.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/settings/settings_screen.dart';
import 'package:remote_tunes/providers/providers.dart';

import 'helpers/fake_audio_backend.dart';

typedef _Event = ({int id, int heard, String outcome});

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

  group('the engine writes one event per song played', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;
    late List<_Event> events;
    late List<DateTime> starts;

    setUp(() {
      backend = FakeAudioBackend();
      events = [];
      starts = [];
      engine = QueuePlaybackEngine(
        backend: backend,
        fileExists: (_) => true,
        onSongEnded: (id, at, heard, outcome) {
          starts.add(at);
          events.add((id: id, heard: heard, outcome: outcome));
        },
      );
    });
    tearDown(() => engine.dispose());

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    Future<void> listen(double seconds) async {
      var t = 0.0;
      while (t < seconds) {
        t += 0.5;
        backend.emitPosition(Duration(milliseconds: (t * 1000).round()));
        await Future<void>.delayed(Duration.zero);
      }
      await settle();
    }

    test('a quick next is a skip, with the seconds that were heard', () async {
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await listen(5);
      await engine.next();
      expect(events.single.id, 1);
      expect(events.single.outcome, 'skipped');
      expect(events.single.heard, inInclusiveRange(4, 5));
      expect(starts.single.isAfter(DateTime.now().subtract(const Duration(minutes: 1))), isTrue);
    });

    test('moving on after a long listen is "stopped", and a song played to its end is "finished"',
        () async {
      await engine.playSongs([song(1), song(2, duration: 20), song(3)]);
      await settle();
      await listen(45);
      await engine.next();
      expect(events.last.outcome, 'stopped');
      expect(events.last.heard, inInclusiveRange(44, 45));
      await listen(20);
      backend.emitCompleted();
      await settle();
      expect(events.last.id, 2);
      expect(events.last.outcome, 'finished');
    });

    test('a link (not in the library) is never logged', () async {
      await engine.playSongs([
        PlayableSong.stream(url: 'https://x/1.mp3', title: 'L', artist: 'A', album: 'B'),
        song(2),
      ]);
      await settle();
      await listen(3);
      await engine.next();
      expect(events, isEmpty);
    });
  });

  group('the log and what it says', () {
    late AppDatabase db;
    late LibraryRepository repo;
    final now = DateTime(2026, 11, 25, 12);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
    });
    tearDown(() => db.close());

    Future<int> add(String t, String artist, String genre) async {
      final id = await repo.addSong(
          title: t, artist: artist, album: 'Al', filePath: '/m/$t.mp3', durationSeconds: 200);
      await db.customUpdate("UPDATE songs SET genre = '$genre' WHERE id = $id", updates: {db.songs});
      return id;
    }

    test('the table exists in a new database, can be counted and cleared', () async {
      expect(await repo.playEventCount(), 0);
      await repo.recordPlayEvent(1, now, 120, 'finished');
      await repo.recordPlayEvent(1, now, -5, 'skipped');
      expect(await repo.playEventCount(), 2);
      expect(await repo.clearPlayEvents(), 2);
      expect(await repo.playEventCount(), 0);
    });

    test('with nothing logged the play part is empty', () async {
      await add('A', 'Ann', 'Rock');
      final d = await loadInsights(db, now: now);
      expect(d.playLog.isEmpty, isTrue);
    });

    test('time listened, plays per day, and where the time went', () async {
      final a = await add('A', 'Ann', 'Rock');
      final b = await add('B', 'Bob', 'Jazz');
      Future<void> ev(int id, DateTime at, int heard, String how) => repo.recordPlayEvent(id, at, heard, how);
      await ev(a, now.subtract(const Duration(hours: 2)), 200, 'finished');
      await ev(a, now.subtract(const Duration(days: 1)), 600, 'finished');
      await ev(b, now.subtract(const Duration(days: 1)), 10, 'skipped');
      await ev(b, now.subtract(const Duration(days: 10)), 300, 'stopped');
      await ev(a, now.subtract(const Duration(days: 40)), 1200, 'finished');

      final l = (await loadInsights(db, now: now)).playLog;
      expect(l.plays, 5);
      expect(l.totalSeconds, 200 + 600 + 10 + 300 + 1200);
      expect(l.weekPlays, 3);
      expect(l.weekSeconds, 810);
      expect(l.finished, 3);
      expect(l.skipped, 1);

      expect(l.playsByDay, hasLength(14));
      expect(l.playsByDay.map((e) => e.value).reduce((x, y) => x + y), 4, reason: 'the 40-day-old one is outside');
      expect(l.playsByDay.last.value, 1);
      expect(l.minutesByDay.last.value, 3);

      expect(l.minutesByGenre.first.label, 'Rock');
      expect(l.minutesByGenre.first.value, 33, reason: "all of the log, 2000 s");
      expect(l.minutesByArtist.map((e) => e.label), ['Ann', 'Bob']);
    });

    test('the history stays when the song is removed from the library', () async {
      final a = await add('A', 'Ann', 'Rock');
      await repo.recordPlayEvent(a, now, 100, 'finished');
      await db.customUpdate('DELETE FROM songs WHERE id = $a', updates: {db.songs});
      expect(await repo.playEventCount(), 1);
      expect((await loadInsights(db, now: now)).isEmpty, isTrue);
    });
  });

  group('the screen', () {
    Future<void> show(WidgetTester tester, PlayLogInsights log) async {
      tester.view.physicalSize = const Size(500, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: InsightsView(insights: LibraryInsights(songs: 10, playLog: log))),
      ));
    }

    testWidgets('says the log starts now when it is empty', (tester) async {
      await show(tester, const PlayLogInsights());
      expect(find.textContaining('Nothing recorded yet'), findsOneWidget);
    });

    testWidgets('shows the time, the two day charts and the lists', (tester) async {
      await show(
        tester,
        PlayLogInsights(
          plays: 5,
          totalSeconds: 3 * 3600 + 20 * 60,
          weekSeconds: 90 * 60,
          weekPlays: 3,
          finished: 3,
          skipped: 1,
          playsByDay: [for (var i = 12; i <= 25; i++) InsightItem('11-$i', i == 25 ? 4 : 0)],
          minutesByDay: [for (var i = 12; i <= 25; i++) InsightItem('11-$i', i == 25 ? 90 : 0)],
          minutesByGenre: const [InsightItem('Rock', 30)],
          minutesByArtist: const [InsightItem('Ann', 30)],
        ),
      );
      expect(find.text('1 h 30 min'), findsOneWidget);
      expect(find.text('3 h 20 min'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Plays, last 14 days'), findsOneWidget);
      expect(find.text('Minutes listened, last 14 days'), findsOneWidget);
      expect(find.text('4 plays'), findsOneWidget);
      expect(find.text('Listening by genre'), findsOneWidget);
      expect(find.text('30 min'), findsNWidgets(2));
    });
  });

  group('Settings', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('the play history is on by default and can be switched off', () async {
      final repo = SettingsRepository(db);
      expect((await repo.load()).playHistory, isTrue);
      await repo.setPlayHistory(false);
      expect((await repo.load()).playHistory, isFalse);
    });

    testWidgets('Clear play history asks first, then empties the log', (tester) async {
      final lib = LibraryRepository(db);
      await lib.recordPlayEvent(1, DateTime.now(), 60, 'finished');
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField).first, 'play history');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('clear-play-history')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('forgets 1 recorded play'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await tester.runAsync(lib.playEventCount), 0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
