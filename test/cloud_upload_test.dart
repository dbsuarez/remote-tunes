import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/cloud/cloud_config_store.dart';
import 'package:remote_tunes/features/cloud/cloud_models.dart';
import 'package:remote_tunes/features/cloud/cloud_service.dart';
import 'package:remote_tunes/features/cloud/cloud_upload_flow.dart';
import 'package:remote_tunes/features/music/music_browser.dart';
import 'package:remote_tunes/providers/library_providers.dart';

import 'cloud_library_view_test.dart' show MemoryCloudStore;
import 'cloud_test.dart' show FakeR2, config;
import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;
  late Directory dir;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    dir = Directory.systemTemp.createTempSync('cloudup');
  });
  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // A file still being read by a test that ended early: the temp folder is cleaned later.
    }
  });

  Future<int> add(String title, {String artist = 'Ann', String album = 'Alpha', String genre = 'Rock', int bytes = 1000, bool file = true, int dur = 200, String ext = 'mp3'}) async {
    final path = p.join(dir.path, '$title.$ext');
    if (file) File(path).writeAsBytesSync(List.filled(bytes, 5));
    final id = await repo.addSong(title: title, artist: artist, album: album, filePath: path, durationSeconds: dur);
    await db.customUpdate("UPDATE songs SET genre = '$genre', year = 1999, track_number = 4 WHERE id = $id", updates: {db.songs});
    return id;
  }

  group('what would go up', () {
    test('the tags, the size, and what is wrong', () async {
      final a = await add('Hello', bytes: 1234);
      final gone = await add('Gone', file: false);
      final unknown = await add('Mystery', artist: 'Unknown artist', album: 'Unknown album');
      final c = await loadUploadCandidates(repo, [a, gone, unknown, 999], const CloudCatalog());
      expect(c, hasLength(3), reason: 'a song that is not in the library is skipped');
      expect((c[0].title, c[0].artist, c[0].album, c[0].genre, c[0].year, c[0].track, c[0].size), ('Hello', 'Ann', 'Alpha', 'Rock', 1999, 4, 1234));
      expect(c[0].canUpload, isTrue);
      expect(c[1].canUpload, isFalse);
      expect(c[1].problem, 'The file is missing');
      expect((c[2].artist, c[2].album), ('', ''), reason: '"Unknown" is not put in the cloud');
    });

    test('a song that seems to be in the cloud already is not ticked by default', () async {
      final a = await add('Hello', dur: 200);
      final b = await add('Other');
      final existing = CloudCatalog([
        CloudSong(id: 'x', title: 'Hello', artist: 'Ann', durationSeconds: 201, audioKey: 'songs/x.mp3'),
      ]);
      final c = await loadUploadCandidates(repo, [a, b], existing);
      expect(c[0].duplicate?.id, 'x');
      expect(c[0].tickedByDefault, isFalse);
      expect(c[1].tickedByDefault, isTrue);
    });

    test('uploads read the file as it is, and the cover from its file', () async {
      final a = await add('Hello', bytes: 50, ext: 'flac');
      final art = File(p.join(dir.path, 'cover.png'))..writeAsBytesSync(List.filled(40, 9));
      await db.customUpdate("UPDATE songs SET album_art_path = '${art.path.replaceAll("'", "''")}' WHERE id = $a", updates: {db.songs});
      final big = await add('Big');
      final bigArt = File(p.join(dir.path, 'big.jpg'))..writeAsBytesSync(List.filled(3 * 1024 * 1024 + 1, 1));
      await db.customUpdate("UPDATE songs SET album_art_path = '${bigArt.path.replaceAll("'", "''")}' WHERE id = $big", updates: {db.songs});
      final c = await loadUploadCandidates(repo, [a, big], const CloudCatalog());
      final ups = await toUploads(c);
      expect(ups[0].ext, 'flac');
      expect(ups[0].length, 50);
      expect(ups[0].artExt, 'png');
      expect(ups[0].art, hasLength(40));
      expect((await ups[0].open().expand((x) => x).toList()), hasLength(50));
      expect(ups[1].art, isNull, reason: 'a huge picture is left off');
    });
  });

  group('the review', () {
    List<UploadCandidate> cands() => [
          UploadCandidate(songId: 1, title: 'New', artist: 'Ann', path: '/a', size: 5 * 1024 * 1024),
          UploadCandidate(songId: 2, title: 'Same', artist: 'Ann', path: '/b', size: 3 * 1024 * 1024, duplicate: const CloudSong(id: 'x', title: 'Same', audioKey: 'songs/x.mp3')),
          UploadCandidate(songId: 3, title: 'Gone', path: '/c', size: 0, problem: 'The file is missing'),
        ];

    Future<List<UploadCandidate>?> show(WidgetTester tester, {int cloudBytes = 0, void Function(List<UploadCandidate>?)? done}) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      List<UploadCandidate>? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showUploadReview(context, cands(), cloudBytes: cloudBytes),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('ticks what can go and is new, explains the rest, and counts', (tester) async {
      await show(tester);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('upload-1'))).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('upload-2'))).value, isFalse);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('upload-3'))).onChanged, isNull);
      expect(find.textContaining('seems to be in the cloud already'), findsOneWidget);
      expect(find.textContaining('The file is missing'), findsOneWidget);
      expect(find.text('1 song · 5.0 MB'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('upload-2')));
      await tester.pump();
      expect(find.text('2 songs · 8.0 MB'), findsOneWidget);
      expect(find.text('Upload 2'), findsOneWidget);
    });

    testWidgets('warns when the free storage would be passed', (tester) async {
      await show(tester, cloudBytes: 10 * 1024 * 1024 * 1024 - 1024 * 1024);
      expect(find.byKey(const Key('upload-over')), findsOneWidget);
    });

    testWidgets('no warning with room to spare', (tester) async {
      await show(tester);
      expect(find.byKey(const Key('upload-over')), findsNothing);
    });

    testWidgets('Upload gives the ticked songs; with none ticked it waits', (tester) async {
      List<UploadCandidate>? got;
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => TextButton(onPressed: () async => got = await showUploadReview(context, cands()), child: const Text('go'))),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('upload-1')));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('upload-go'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('upload-1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('upload-go')));
      await tester.pumpAndSettle();
      expect(got!.map((c) => c.title), ['New']);
    });

    testWidgets('Cancel gives nothing', (tester) async {
      List<UploadCandidate>? got = [];
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => TextButton(onPressed: () async => got = await showUploadReview(context, cands()), child: const Text('go'))),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(got, isNull);
    });
  });

  group('the whole flow', () {
    late FakeR2 r2;
    setUp(() => r2 = FakeR2());

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Waits (with real time, so file reads can finish) until [finder] shows.
    Future<void> until(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester tester, List<int> ids, {CloudConfig? cfg}) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repo),
          cloudConfigStoreProvider.overrideWithValue(MemoryCloudStore(cfg ?? config)),
          cloudServiceFactoryProvider.overrideWithValue((c) => CloudLibraryService(
                c,
                client: MockClient((r) async => r2.handle(r)),
                newId: () => 'up1',
                now: () => DateTime.utc(2026),
              )),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(onPressed: () => uploadSongsToCloud(context, ref, ids), child: const Text('go')),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await settle(tester);
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('without keys it says to set up uploading first', (tester) async {
      final a = await add('Hello');
      await open(tester, [a], cfg: const CloudConfig(publicUrl: 'https://pub-123.r2.dev'));
      expect(find.text('Set up uploading first'), findsOneWidget);
      await tester.tap(find.byKey(const Key('upload-open-settings')));
      await settle(tester);
      expect(find.text('Cloud Library'), findsOneWidget, reason: 'the settings opened');
      expect(r2.log, isEmpty);
      await finish(tester);
    });

    testWidgets('review, upload, and the song is in the cloud and its listing', (tester) async {
      final a = await add('Hello', bytes: 777);
      await open(tester, [a]);
      expect(find.text('Upload to the cloud'), findsOneWidget);
      await tester.tap(find.byKey(const Key('upload-go')));
      await until(tester, find.text('Uploaded 1 song'));
      expect(find.text('Uploaded 1 song'), findsOneWidget);
      expect(r2.files['songs/up1.mp3'], hasLength(777));
      final cat = CloudCatalog.fromJson(jsonDecode(utf8.decode(r2.files['catalog.json']!)));
      expect(cat.songs.single.title, 'Hello');
      expect((cat.songs.single.artist, cat.songs.single.genre, cat.songs.single.year, cat.songs.single.track), ('Ann', 'Rock', 1999, 4));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await finish(tester);
    });

    testWidgets('refused keys are reported, with nothing listed', (tester) async {
      final a = await add('Hello');
      r2.refuse = true;
      await open(tester, [a]);
      await tester.tap(find.byKey(const Key('upload-go')));
      await until(tester, find.text('Uploaded 0 songs'));
      expect(find.text('Uploaded 0 songs'), findsOneWidget);
      expect(find.byKey(const Key('upload-stopped')), findsOneWidget);
      expect(find.textContaining('refused the keys'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await finish(tester);
    });
  });

  group('in the Library', () {
    testWidgets('picked songs get an upload button only where uploading is offered', (tester) async {
      final source = FakeMusicSource(songs: [song(1, 'Apple Song'), song(2, 'Banana Song')]);
      List<int>? sent;
      Future<void> open({required bool offered}) async {
        tester.view.physicalSize = const Size(500, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(host(MusicBrowser(
          source: source,
          onUploadToCloud: offered ? (ctx, ids) async => sent = ids : null,
        )));
        await settleUi(tester);
        await tester.longPress(find.text('Apple Song'));
        await settleUi(tester);
      }

      await open(offered: false);
      expect(find.byKey(const Key('upload-to-cloud')), findsNothing);
      await open(offered: true);
      await tester.tap(find.text('Banana Song'));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('upload-to-cloud')));
      await settleUi(tester);
      expect(sent!.toSet(), {1, 2});
      expect(find.text('2 selected'), findsNothing, reason: 'the picking ends after the upload');
    });
  });
}
