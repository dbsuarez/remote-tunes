import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/insights/insights_data.dart';
import 'package:remote_tunes/features/insights/insights_screen.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;
  final now = DateTime(2026, 11, 25, 12);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });
  tearDown(() => db.close());

  Future<int> add(String title, String artist, String album,
      {int seconds = 200, String? genre, int plays = 0, int skips = 0, DateTime? added, DateTime? last, bool fav = false}) async {
    final id = await repo.addSong(
        title: title, artist: artist, album: album, filePath: '/m/$title.mp3', durationSeconds: seconds);
    await db.customUpdate(
      'UPDATE songs SET genre = ?, play_count = ?, skip_count = ?, added_at = ?, last_played_at = ?, '
      'favorite = ?, file_size_bytes = 1000000 WHERE id = ?',
      variables: [
        Variable<String>(genre),
        Variable<int>(plays),
        Variable<int>(skips),
        Variable<DateTime>(added ?? now),
        Variable<DateTime>(last),
        Variable<bool>(fav),
        Variable<int>(id),
      ],
      updates: {db.songs},
    );
    return id;
  }

  test('an empty library has nothing to show', () async {
    expect((await loadInsights(db, now: now)).isEmpty, isTrue);
  });

  group('the numbers', () {
    setUp(() async {
      await add('One', 'Ann', 'Alpha', genre: 'Rock', plays: 5, skips: 1, last: now.subtract(const Duration(days: 1)), fav: true);
      await add('Two', 'Ann', 'Alpha', genre: 'rock', plays: 2, last: now.subtract(const Duration(days: 30)));
      await add('Three', 'Bob', 'Beta', genre: 'Jazz', skips: 4, added: DateTime(2026, 9, 10));
      await add('Four', 'Unknown artist', 'Unknown album');
    });

    test('totals: songs, time, size, artists, albums, favorites, never played, this week', () async {
      final d = await loadInsights(db, now: now);
      expect(d.songs, 4);
      expect(d.seconds, 800);
      expect(d.bytes, 4000000);
      expect(d.artists, 3);
      expect(d.albums, 3);
      expect(d.favorites, 1);
      expect(d.neverPlayed, 2);
      expect(d.playedThisWeek, 1);
    });

    test('genres are counted without minding capitals, biggest first', () async {
      final d = await loadInsights(db, now: now);
      expect(d.genres.map((g) => g.value), [2, 1]);
      expect(d.genres.last.label, 'Jazz');
    });

    test('top artists leave out unknown ones', () async {
      final d = await loadInsights(db, now: now);
      expect(d.topArtists.map((a) => a.label), ['Ann', 'Bob']);
      expect(d.topArtists.first.value, 2);
    });

    test('most played, most skipped and recently played carry the artist', () async {
      final d = await loadInsights(db, now: now);
      expect(d.mostPlayed.first.label, 'One');
      expect(d.mostPlayed.first.value, 5);
      expect(d.mostPlayed.first.detail, 'Ann');
      expect(d.mostSkipped.first.label, 'Three');
      expect(d.mostSkipped.map((s) => s.label), ['Three', 'One']);
      expect(d.recentlyPlayed.map((s) => s.label), ['One', 'Two']);
    });

    test('songs added: twelve months, the quiet ones as zero', () async {
      final d = await loadInsights(db, now: now);
      expect(d.addedByMonth, hasLength(12));
      expect(d.addedByMonth.first.label, '2025-12');
      expect(d.addedByMonth.last.label, '2026-11');
      expect(d.addedByMonth.last.value, 3);
      expect(d.addedByMonth.firstWhere((m) => m.label == '2026-09').value, 1);
      expect(d.addedByMonth.firstWhere((m) => m.label == '2026-03').value, 0);
    });
  });

  group('the screen', () {
    Future<void> show(WidgetTester tester, LibraryInsights d) async {
      tester.view.physicalSize = const Size(500, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: InsightsView(insights: d))));
    }

    testWidgets('says so when there is nothing yet', (tester) async {
      await show(tester, const LibraryInsights());
      expect(find.textContaining('Nothing to show yet'), findsOneWidget);
    });

    testWidgets('shows the totals, the lists and the months', (tester) async {
      await show(
        tester,
        LibraryInsights(
          songs: 128,
          seconds: 9 * 3600 + 7 * 60 + 26,
          bytes: 3 * 1024 * 1024 * 1024,
          artists: 10,
          albums: 20,
          genres: const [InsightItem('Rock', 60), InsightItem('Jazz', 30)],
          topArtists: const [InsightItem('Ann', 12)],
          addedByMonth: [for (var i = 1; i <= 12; i++) InsightItem('2026-${i.toString().padLeft(2, '0')}', i == 3 ? 7 : 0)],
          mostPlayed: const [InsightItem('One', 5, detail: 'Ann')],
        ),
      );
      expect(find.text('128'), findsOneWidget);
      expect(find.text('9:07:26'), findsOneWidget);
      expect(find.text('3.0 GB'), findsOneWidget);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('60 songs'), findsOneWidget);
      expect(find.text('5 plays'), findsOneWidget);
      expect(find.text('Songs added, last 12 months'), findsOneWidget);
      expect(find.text('7 songs'), findsOneWidget);
      expect(find.text('Nothing skipped yet.'), findsOneWidget);
      // The bar of the biggest is full; the other is half.
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('bar-Genres-Rock'))).value, 1.0);
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('bar-Genres-Jazz'))).value, 0.5);
    });
  });
}
