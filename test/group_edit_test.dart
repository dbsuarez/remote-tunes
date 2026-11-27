import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/lookup_models.dart';
import 'package:remote_tunes/features/library/cover_picker.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/tag_writer.dart';
import 'package:remote_tunes/features/music/group_info_dialog.dart';
import 'package:remote_tunes/features/music/music_browser.dart';
import 'package:remote_tunes/providers/library_providers.dart';

import 'music_widgets_test.dart' show FakeMusicSource, settleUi, song;

/// A tiny MP3: an empty ID3v2.4 tag, then a few silent MPEG frames.
Uint8List mp3() {
  final b = BytesBuilder();
  b.add([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0]);
  for (var i = 0; i < 6; i++) {
    b.add([0xFF, 0xFB, 0x90, 0x00]);
    b.add(Uint8List(413));
  }
  return b.toBytes();
}

Song _song({
  int id = 1,
  String title = 'T',
  String? artist = 'Ann',
  String? album = 'First',
  String? genre,
  int? year,
  String? albumArtist,
  String? composer,
  String? path,
}) =>
    Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      filePath: path,
      source: 'localFile',
      addedAt: DateTime(2026),
      favorite: false,
      albumArtist: albumArtist,
      genre: genre,
      year: year,
      composer: composer,
      playCount: 0,
      skipCount: 0,
      infoEdited: false,
    );

class _NoTags implements MetadataExtractor {
  @override
  Future<ExtractedMetadata> extract(String path) async => throw UnimplementedError();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the library change', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late List<int> ids;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      ids = [
        for (var i = 1; i <= 3; i++)
          await repo.addSong(
              title: 'Song $i',
              artist: 'Old Artist',
              album: 'Old Album',
              filePath: '/m/$i.mp3',
              trackNumber: i,
              genre: 'Rock',
              year: 1990),
      ];
    });
    tearDown(() => db.close());

    Future<Map<String, Object?>> row(int id) async {
      final r = await db.customSelect(
          'SELECT title, track_number, artist, album, album_artist, genre, year, composer, info_edited '
          'FROM songs WHERE id = ?',
          variables: [Variable<int>(id)]).getSingle();
      return r.data;
    }

    test('changes the shared fields on every picked song, and only those', () async {
      final n = await repo.updateGroupInfo(ids.take(2).toList(),
          {'artist': 'New Artist', 'year': 2001, 'composer': 'Bach', 'albumArtist': 'Various'});
      expect(n, 2);
      final a = await row(ids[0]);
      expect(a['artist'], 'New Artist');
      expect(a['year'], 2001);
      expect(a['composer'], 'Bach');
      expect(a['album_artist'], 'Various');
      expect(a['album'], 'Old Album', reason: 'not asked to change');
      expect(a['genre'], 'Rock');
      expect((await row(ids[2]))['artist'], 'Old Artist', reason: 'not picked');
    });

    test('titles and track numbers are never touched, and the song is marked as edited', () async {
      await repo.updateGroupInfo(ids, {'album': 'Greatest Hits'});
      for (var i = 0; i < 3; i++) {
        final r = await row(ids[i]);
        expect(r['title'], 'Song ${i + 1}');
        expect(r['track_number'], i + 1);
        expect(r['info_edited'], 1);
      }
    });

    test('clearing: an empty artist or album reads Unknown, other fields become empty', () async {
      await repo.updateGroupInfo([ids[0]], {'artist': '  ', 'album': null, 'genre': null, 'year': null});
      final r = await row(ids[0]);
      expect(r['artist'], 'Unknown artist');
      expect(r['album'], 'Unknown album');
      expect(r['genre'], isNull);
      expect(r['year'], isNull);
    });

    test('a silly year is dropped, long text is cut, nothing to do changes nothing', () async {
      await repo.updateGroupInfo([ids[0]], {'year': 123456});
      expect((await row(ids[0]))['year'], isNull);
      await repo.updateGroupInfo([ids[1]], {'genre': 'g' * 500});
      expect(((await row(ids[1]))['genre'] as String).length, LibraryRepository.maxTagLength);
      expect(await repo.updateGroupInfo([], {'artist': 'x'}), 0);
      expect(await repo.updateGroupInfo(ids, {}), 0);
      expect(await repo.updateGroupInfo(ids, {'title': 'nope'}), 0, reason: 'not a group field');
      expect((await row(ids[0]))['title'], 'Song 1');
    });
  });

  group('writing into the files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('grp'));
    tearDown(() => dir.deleteSync(recursive: true));

    File file(String name) => File('${dir.path}/$name')..writeAsBytesSync(mp3());

    test('the shared fields go into a real file and read back; the title is left alone', () {
      final f = file('a.mp3');
      updateMetadata(f, (m) {
        m.setTitle('Keep This Title');
        m.setTrackNumber(7);
      });
      final r = const TagWriter().writeGroup(
          f.path, {'artist': 'New Artist', 'album': 'New Album', 'genre': 'Jazz', 'year': 1999, 'composer': 'Bach'});
      expect(r, TagWriteResult.written);
      final back = readMetadata(f, getImage: false);
      expect(back.artist, 'New Artist');
      expect(back.album, 'New Album');
      expect(back.title, 'Keep This Title');
      expect(back.trackNumber, 7);
      expect(back.genres, ['Jazz']);
      expect(back.year?.year, 1999);
    });

    test('a field can be cleared in the file (the composer, here)', () {
      final f = file('b.mp3');
      const TagWriter().writeGroup(f.path, {'composer': 'Bach', 'artist': 'X'});
      expect((readAllMetadata(f) as Mp3Metadata).composer, 'Bach');
      const TagWriter().writeGroup(f.path, {'composer': null});
      expect((readAllMetadata(f) as Mp3Metadata).composer, isNull);
      expect(readMetadata(f, getImage: false).artist, 'X');
    });

    test('a missing file, and a file that is not music, are reported and left alone', () {
      expect(const TagWriter().writeGroup('${dir.path}/none.mp3', {'artist': 'x'}),
          TagWriteResult.missing);
      final f = File('${dir.path}/notes.mp3')..writeAsStringSync('just text');
      expect(const TagWriter().writeGroup(f.path, {'artist': 'x'}), isNot(TagWriteResult.written));
      expect(f.readAsStringSync(), 'just text');
    });
  });

  group('the dialog', () {
    GroupInfoEdit? result;

    Future<void> open(WidgetTester tester, List<Song> songs, {bool canWrite = true}) async {
      result = null;
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showGroupInfoDialog(context, songs, canWriteFile: canWrite),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    final two = [
      _song(id: 1, title: 'One', artist: 'Ann', album: 'First', genre: 'Rock', year: 1999),
      _song(id: 2, title: 'Two', artist: 'Ann', album: 'Second', genre: 'Rock', year: 2001),
    ];

    testWidgets('has the shared fields only, never title or track number', (tester) async {
      await open(tester, two);
      expect(find.text('Edit info of 2 songs'), findsOneWidget);
      for (final l in ['Artist', 'Album', 'Album artist', 'Genre', 'Year', 'Composer']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.text('Title'), findsNothing);
      expect(find.text('Track number'), findsNothing);
    });

    testWidgets('a value the songs share is shown; where they differ it says (different)',
        (tester) async {
      await open(tester, two);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('group-artist'))).controller!.text, 'Ann');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('group-genre'))).controller!.text, 'Rock');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('group-album'))).controller!.text, '');
      String? hint(String key) =>
          tester.widget<TextField>(find.byKey(ValueKey('group-$key'))).decoration!.hintText;
      expect(hint('album'), '(different)');
      expect(hint('year'), '(different)');
      expect(hint('albumArtist'), '(none)');
      expect(hint('composer'), '(none)');
    });

    testWidgets('Save waits for a change, and only what was changed is returned', (tester) async {
      await open(tester, two);
      expect(tester.widget<FilledButton>(find.byKey(const Key('group-save'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('group-album')), 'Greatest Hits');
      await tester.pump();
      await tester.tap(find.byKey(const Key('group-save')));
      await tester.pumpAndSettle();
      expect(result!.changes, {'album': 'Greatest Hits'});
      expect(result!.writeToFile, isTrue, reason: 'ticked from the start');
    });

    testWidgets('emptying a field that had a value clears it', (tester) async {
      await open(tester, two);
      await tester.enterText(find.byKey(const ValueKey('group-genre')), '');
      await tester.pump();
      await tester.tap(find.byKey(const Key('group-save')));
      await tester.pumpAndSettle();
      expect(result!.changes, {'genre': null});
    });

    testWidgets('typing the same value again is not a change', (tester) async {
      await open(tester, two);
      await tester.enterText(find.byKey(const ValueKey('group-artist')), 'Ann');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('group-save'))).onPressed, isNull);
    });

    testWidgets('a year must be a year', (tester) async {
      await open(tester, two);
      await tester.enterText(find.byKey(const ValueKey('group-year')), '0');
      await tester.pump();
      expect(find.text('A year, like 1999'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('group-save'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('group-year')), '2005');
      await tester.pump();
      await tester.tap(find.byKey(const Key('group-save')));
      await tester.pumpAndSettle();
      expect(result!.changes, {'year': 2005});
    });

    testWidgets('unticking the files box keeps the change in the library only', (tester) async {
      await open(tester, two);
      await tester.tap(find.byKey(const Key('group-write')));
      await tester.enterText(find.byKey(const ValueKey('group-composer')), 'Bach');
      await tester.pump();
      await tester.tap(find.byKey(const Key('group-save')));
      await tester.pumpAndSettle();
      expect(result!.writeToFile, isFalse);
    });

    testWidgets('Cancel gives nothing', (tester) async {
      await open(tester, two);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('the Select bar', () {
    Future<void> open(WidgetTester tester, FakeMusicSource source,
        {Future<bool> Function(BuildContext, List<int>)? onEdit}) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MusicBrowser(source: source, onEditSongs: onEdit)),
      ));
      await settleUi(tester);
    }

    testWidgets('offers Edit info for the picked songs, and hands over their numbers', (tester) async {
      final source = FakeMusicSource(songs: [song(1, 'Apple Song'), song(2, 'Banana Song'), song(3, 'Cherry Song')]);
      List<int>? got;
      await open(tester, source, onEdit: (c, ids) async {
        got = ids;
        return true;
      });
      await tester.longPress(find.text('Apple Song'));
      await settleUi(tester);
      await tester.tap(find.text('Cherry Song'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Edit info of the selected songs'));
      await settleUi(tester);
      expect(got, [1, 3]);
      expect(find.textContaining('selected'), findsNothing, reason: 'the selection ends after a change');
    });

    testWidgets('nothing changed: the selection stays', (tester) async {
      final source = FakeMusicSource(songs: [song(1, 'Apple Song'), song(2, 'Banana Song')]);
      await open(tester, source, onEdit: (c, ids) async => false);
      await tester.longPress(find.text('Apple Song'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Edit info of the selected songs'));
      await settleUi(tester);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('another phone\'s library has no such button', (tester) async {
      final source = FakeMusicSource(songs: [song(1, 'Apple Song')]);
      await open(tester, source);
      await tester.longPress(find.text('Apple Song'));
      await settleUi(tester);
      expect(find.byTooltip('Edit info of the selected songs'), findsNothing);
    });
  });

  group('the whole thing', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late Directory dir;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      dir = Directory.systemTemp.createTempSync('grpflow');
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    testWidgets('the library and the files change, and a message says how many', (tester) async {
      final paths = [
        for (var i = 1; i <= 2; i++) (File('${dir.path}/s$i.mp3')..writeAsBytesSync(mp3())).path,
      ];
      final ids = [
        for (var i = 0; i < 2; i++)
          await repo.addSong(
              title: 'Song $i', artist: 'Old', album: 'A$i', filePath: paths[i], durationSeconds: 100),
      ];
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext ctx;
      late WidgetRef widgetRef;
      await tester.pumpWidget(ProviderScope(
        overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            ctx = context;
            widgetRef = ref;
            return const Scaffold(body: Text('home'));
          }),
        ),
      ));
      bool? changed;
      editSelectedSongs(ctx, widgetRef, ids).then((v) => changed = v);
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 300 && !ready(); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await waitFor(() => find.byKey(const ValueKey('group-artist')).evaluate().isNotEmpty);
      await tester.enterText(find.byKey(const ValueKey('group-artist')), 'New Artist');
      await tester.enterText(find.byKey(const ValueKey('group-genre')), 'Jazz');
      await tester.pump();
      await tester.tap(find.byKey(const Key('group-save')));
      await waitFor(() => changed != null);
      await tester.pump(const Duration(milliseconds: 300));
      expect(changed, isTrue);
      expect(find.textContaining('Changed 2 songs'), findsOneWidget);
      expect(find.textContaining('written into 2 files'), findsOneWidget);
      final r = await tester.runAsync(() => db.customSelect('SELECT artist, genre, info_edited FROM songs').get());
      for (final x in r!) {
        expect(x.read<String>('artist'), 'New Artist');
        expect(x.read<String>('genre'), 'Jazz');
        expect(x.read<bool>('info_edited'), isTrue);
      }
      for (final p in paths) {
        final back = readMetadata(File(p), getImage: false);
        expect(back.artist, 'New Artist');
        expect(back.genres, ['Jazz']);
      }
    });
  });

  group('a cover for several songs', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late Directory dir;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      dir = Directory.systemTemp.createTempSync('grpcover');
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    testWidgets('goes on the picked songs and into their files, not on others of the album', (tester) async {
      final picture = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);
      final paths = [for (var i = 1; i <= 3; i++) (File('${dir.path}/s$i.mp3')..writeAsBytesSync(mp3())).path];
      final ids = [
        for (var i = 0; i < 3; i++)
          await repo.addSong(title: 'Song $i', artist: 'Same', album: 'One', filePath: paths[i], durationSeconds: 100),
      ];
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext ctx;
      late WidgetRef widgetRef;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repo),
          coverPickerProvider.overrideWithValue((_) async => LookupCover(picture, 'jpg')),
          importServiceProvider.overrideWith((ref) async => LibraryImportService(
                library: repo,
                extractor: _NoTags(),
                libraryDir: Directory('${dir.path}/library'),
                artDir: Directory('${dir.path}/art'),
                exclusions: MemoryExclusionStore(),
              )),
        ],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            ctx = context;
            widgetRef = ref;
            return const Scaffold(body: Text('home'));
          }),
        ),
      ));
      bool? changed;
      editSelectedSongs(ctx, widgetRef, ids.sublist(0, 2)).then((v) => changed = v);
      Future<void> waitFor(bool Function() ready) async {
        for (var i = 0; i < 300 && !ready(); i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await waitFor(() => find.byKey(const Key('choose-cover')).evaluate().isNotEmpty);
      expect(tester.widget<FilledButton>(find.byKey(const Key('group-save'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('choose-cover')));
      await tester.pump();
      expect(find.text('Save puts this picture on these 2 songs, and into the music files.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('group-save')));
      await waitFor(() => changed != null);
      await tester.pump(const Duration(milliseconds: 300));
      expect(changed, isTrue);
      expect(find.textContaining('Cover written into 2 music files'), findsOneWidget);
      final art = await tester.runAsync(() => db.customSelect('SELECT album_art_path AS a FROM songs ORDER BY id').get());
      final shown = [for (final r in art!) r.readNullable<String>('a')];
      expect(shown[0], isNotNull);
      expect(shown[1], shown[0]);
      expect(shown[2], isNull);
      expect(File(shown[0]!).readAsBytesSync(), picture);
      expect(readMetadata(File(paths[0]), getImage: true).pictures.single.bytes, picture);
      expect(File(paths[2]).readAsBytesSync(), mp3(), reason: 'not picked');
    });
  });
}

