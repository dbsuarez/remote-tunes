import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/lookup_models.dart';
import 'package:remote_tunes/features/library/tag_writer.dart';
import 'package:remote_tunes/features/tagging/tag_cleanup.dart';
import 'package:remote_tunes/features/tagging/tag_cleanup_screen.dart';
import 'package:remote_tunes/features/tagging/tag_cleanup_service.dart';
import 'package:remote_tunes/features/tagging/tag_review_screen.dart';
import 'package:remote_tunes/providers/library_providers.dart';
import 'package:remote_tunes/providers/providers.dart';

class _Writer extends TagWriter {
  _Writer();
  final writes = <String>[];
  @override
  TagWriteResult write(String path, {required String title, required String artist, required String album, int? trackNumber}) {
    writes.add(path);
    return TagWriteResult.written;
  }

  @override
  TagWriteResult writeGroup(String path, Map<String, Object?> changes) => TagWriteResult.written;
}

class _Lookup implements SongLookupService {
  @override
  Future<List<LookupMatch>> search({required String title, String artist = '', String album = '', int durationSeconds = 0}) async =>
      [LookupMatch(title: title, artist: 'Real Artist', album: 'Real Album', year: 2001, score: 100, lengthSeconds: durationSeconds)];
  @override
  Future<LookupCover?> coverFor(LookupMatch m) async => null;
  @override
  Future<RemoteLyrics> lyricsFor(int songId) async => const RemoteLyrics();
  @override
  Future<void> discardLyrics(int songId) async {}
  @override
  Future<int> applyCover(int songId, LookupCover cover) async => 0;
}

class _CoverLookup extends _Lookup {
  final asked = <String>[];
  @override
  Future<LookupCover?> coverFor(LookupMatch m) async {
    asked.add(m.releaseId!);
    return LookupCover(Uint8List.fromList(List.filled(200, 1)), 'jpg');
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;
  late _Writer writer;
  late TagCleanupService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    writer = _Writer();
    service = TagCleanupService(db: db, library: repo, writer: writer);
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<int> add(String title, String path, {String artist = 'Unknown artist'}) =>
      repo.addSong(title: title, artist: artist, album: 'Unknown album', filePath: path, durationSeconds: 200);

  group('the review', () {
    Future<void> open(WidgetTester tester, List<TagChange> changes, {bool canSkip = false}) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: TagReviewScreen(title: 'From file names', changes: changes, service: service, canSkip: canSkip),
      ));
      await tester.pump();
    }

    testWidgets('lists what would change; nothing is ticked and Apply waits', (tester) async {
      await add('01 - Ann - Hello', '/m/01 - Ann - Hello.mp3');
      await open(tester, await service.fileNameChanges());
      expect(find.text('Unknown artist'), findsNothing);
      expect(find.textContaining('artist: Unknown artist → Ann'), findsOneWidget);
      expect(find.textContaining('title: 01 - Ann - Hello → Hello'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('review-apply'))).onPressed, isNull);
    });

    testWidgets('ticking and applying changes the song, and also the file by default', (tester) async {
      final id = await add('01 - Ann - Hello', '/m/01 - Ann - Hello.mp3');
      await open(tester, await service.fileNameChanges());
      await tester.tap(find.byKey(const Key('review-all')));
      await tester.pump();
      expect(find.text('Apply (1)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-apply')));
      await settle(tester);
      final r = await db.customSelect('SELECT title, artist FROM songs WHERE id = $id').getSingle();
      expect((r.read<String>('title'), r.read<String>('artist')), ('Hello', 'Ann'));
      expect(writer.writes, ['/m/01 - Ann - Hello.mp3']);
      expect(find.textContaining('Changed 1 song'), findsOneWidget);
      expect(find.text('Nothing left to review.'), findsOneWidget);
    });

    testWidgets('with the files unticked only the library changes', (tester) async {
      await add('01 - Ann - Hello', '/m/01 - Ann - Hello.mp3');
      await open(tester, await service.fileNameChanges());
      await tester.tap(find.byKey(const Key('review-write')));
      await tester.tap(find.byKey(const Key('review-all')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-apply')));
      await settle(tester);
      expect(writer.writes, isEmpty);
    });

    testWidgets('only what is ticked is applied', (tester) async {
      final a = await add('01 - Ann - A', '/m/01 - Ann - A.mp3');
      final b = await add('02 - Bob - B', '/m/02 - Bob - B.mp3');
      await open(tester, await service.fileNameChanges());
      await tester.tap(find.byKey(ValueKey('change-$a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-apply')));
      await settle(tester);
      expect((await db.customSelect('SELECT artist FROM songs WHERE id = $a').getSingle()).read<String>('artist'), 'Ann');
      expect((await db.customSelect('SELECT artist FROM songs WHERE id = $b').getSingle()).read<String>('artist'), 'Unknown artist');
      expect(find.byKey(ValueKey('change-$b')), findsOneWidget, reason: 'still waiting');
    });

    testWidgets('"Select the sure ones" picks only the sure matches', (tester) async {
      const sure = TagChange(songId: 1, label: 'Sure', source: 'musicbrainz', album: 'A', high: true, was: {'album': null});
      const maybe = TagChange(songId: 2, label: 'Maybe', source: 'musicbrainz', album: 'B', was: {'album': null});
      await open(tester, [sure, maybe], canSkip: true);
      await tester.tap(find.byKey(const Key('review-sure')));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('change-1'))).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('change-2'))).value, isFalse);
      expect(find.text('Select the sure ones (1)'), findsOneWidget);
    });

    testWidgets('sure matches with a release offer covers, which are downloaded when ticked', (tester) async {
      final id = await add('Hello', '/m/h.mp3', artist: 'Ann');
      final covers = _CoverLookup();
      final change = TagChange(songId: id, label: 'Hello - Ann', source: 'musicbrainz', year: 2001, releaseId: 'rel-1', high: true, was: const {'year': null});
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: TagReviewScreen(title: 'Suggestions', changes: [change], service: service, coverLookup: covers),
      ));
      await tester.pump();
      expect(find.byKey(const Key('review-covers')), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-all')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-apply')));
      await settle(tester);
      expect(covers.asked, ['rel-1']);
      expect(find.textContaining('1 cover downloaded'), findsOneWidget);
    });

    testWidgets('with the covers box unticked nothing is downloaded; without releases there is no box', (tester) async {
      final id = await add('Hello', '/m/h.mp3', artist: 'Ann');
      final covers = _CoverLookup();
      final change = TagChange(songId: id, label: 'Hello', source: 'musicbrainz', year: 2001, releaseId: 'rel-1', was: const {'year': null});
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: TagReviewScreen(title: 'S', changes: [change], service: service, coverLookup: covers),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-covers')));
      await tester.tap(find.byKey(const Key('review-all')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-apply')));
      await settle(tester);
      expect(covers.asked, isEmpty);
      await tester.pumpWidget(MaterialApp(
        home: TagReviewScreen(
            title: 'S',
            changes: [TagChange(songId: id, label: 'x', source: 'filename', title: 'T', was: const {})],
            service: service,
            coverLookup: covers),
      ));
      await tester.pump();
      expect(find.byKey(const Key('review-covers')), findsNothing);
    });

    testWidgets('Set aside marks suggestions as skipped and removes them', (tester) async {
      final id = await add('Hello', '/m/h.mp3');
      await db.customInsert("INSERT INTO tag_suggestions (song_id, album, status) VALUES ($id, 'X', 'new')");
      await open(tester, await service.suggestionChanges(), canSkip: true);
      await tester.tap(find.byKey(const Key('review-all')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-skip')));
      await settle(tester);
      expect(await service.suggestionChanges(), isEmpty);
      expect((await db.customSelect('SELECT status FROM tag_suggestions').getSingle()).read<String>('status'), 'skipped');
    });
  });

  group('the Tag cleanup screen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          libraryRepositoryProvider.overrideWithValue(repo),
          tagCleanupServiceProvider.overrideWithValue(service),
          songLookupProvider.overrideWithValue(_Lookup()),
        ],
        child: const MaterialApp(home: TagCleanupScreen()),
      ));
      await settle(tester);
    }

    testWidgets('shows what is missing and how many file names can help', (tester) async {
      await add('01 - Ann - A', '/m/01 - Ann - A.mp3');
      await add('Plain', '/m/plain.mp3', artist: 'Ann');
      await open(tester);
      expect(find.text('Tag cleanup'), findsWidgets);
      expect(find.text('What is missing'), findsOneWidget);
      expect(find.text('Review 1 song'), findsOneWidget);
      expect(find.text('Nothing to undo.'), findsOneWidget);
    });

    testWidgets('the file-name review opens, applies, and the screen then offers an undo', (tester) async {
      final id = await add('01 - Ann - A', '/m/01 - Ann - A.mp3');
      await open(tester);
      await tester.tap(find.byKey(const Key('from-filenames')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('review-all')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('review-apply')));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      expect(find.byKey(const Key('undo-last')), findsOneWidget);
      expect(find.text('Review 0 songs'), findsOneWidget);
      await tester.tap(find.byKey(const Key('undo-last')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Undo'));
      await settle(tester);
      final r = await db.customSelect('SELECT artist FROM songs WHERE id = $id').getSingle();
      expect(r.read<String>('artist'), 'Unknown artist');
      expect(find.text('Nothing to undo.'), findsOneWidget);
    });

    testWidgets('every batch is listed with its own Undo; an older one can be undone', (tester) async {
      final a = await add('01 - Ann - A', '/m/01 - Ann - A.mp3');
      final b = await add('02 - Bob - B', '/m/02 - Bob - B.mp3');
      final all = await service.fileNameChanges();
      await service.apply([all.firstWhere((c) => c.songId == a)]);
      await service.apply([all.firstWhere((c) => c.songId == b)]);
      await open(tester);
      expect(find.byKey(const Key('batch-1')), findsOneWidget);
      expect(find.byKey(const Key('batch-2')), findsOneWidget);
      expect(find.byKey(const Key('undo-last')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('undo-batch-1')));
      await tester.tap(find.byKey(const Key('undo-batch-1')));
      await tester.pumpAndSettle();
      expect(find.text('Undo this change?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Undo'));
      await settle(tester);
      expect((await db.customSelect('SELECT artist FROM songs WHERE id = $a').getSingle()).read<String>('artist'), 'Unknown artist');
      expect((await db.customSelect('SELECT artist FROM songs WHERE id = $b').getSingle()).read<String>('artist'), 'Bob');
      expect(find.byKey(const Key('batch-1')), findsNothing);
    });

    testWidgets('searching online finds suggestions to review', (tester) async {
      await add('Hello', '/m/hello.mp3');
      await open(tester);
      expect(find.byKey(const Key('review-suggestions')), findsNothing);
      await tester.tap(find.byKey(const Key('search-online')));
      await settle(tester);
      await settle(tester);
      expect(find.byKey(const Key('review-suggestions')), findsOneWidget);
      expect(find.text('Review 1 suggestion'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-suggestions')));
      await settle(tester);
      expect(find.textContaining('album: Unknown album → Real Album'), findsOneWidget);
      expect(find.textContaining('year: (empty) → 2001'), findsOneWidget);
    });
  });
}
