import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/backup/backup_models.dart';
import 'package:remote_tunes/features/backup/backup_screen.dart';
import 'package:remote_tunes/features/backup/backup_service.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/providers/library_providers.dart';
import 'package:remote_tunes/providers/providers.dart';

class _Picker implements BackupPicker {
  Uint8List? file;
  String? folder;
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;
  @override
  Future<Uint8List?> pickFile() async => file;
  @override
  Future<String?> pickFolder() async => folder;
}

class _NoTags implements MetadataExtractor {
  @override
  Future<ExtractedMetadata> extract(String path) async => const ExtractedMetadata();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;
  late Directory root;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    root = Directory.systemTemp.createTempSync('bkf');
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  BackupService service(AppDatabase d, {String copies = '/app/library'}) => BackupService(
      db: d,
      settings: SettingsRepository(d),
      exclusions: MemoryExclusionStore(),
      copiedSongsDir: copies);

  /// An old phone whose one song has a name the new phone does not know.
  Future<BackupData> oldPhone() async {
    final other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    final r = LibraryRepository(other);
    final a = await r.addSong(
        title: 'Song (Live)', artist: 'Ann', album: 'Live', filePath: '/old/a.mp3', durationSeconds: 100);
    final b = await r.addSong(
        title: 'Beta', artist: 'Ann', album: 'First', filePath: '/old/b.mp3', durationSeconds: 90);
    final pl = await r.createPlaylist('Gym');
    await r.addToPlaylist(pl, [a, b]);
    await r.setFavorite(a, true);
    return service(other).create();
  }

  group('matching by hand', () {
    test('a song that was not found lists where it is in the backup', () async {
      await repo.addSong(title: 'Song', artist: 'Ann', album: 'Studio', filePath: '/new/s.mp3', durationSeconds: 150);
      final data = await oldPhone();
      final report = await service(db).restore(data);
      expect(report.notFound, hasLength(2));
      expect(report.notFoundIndexes, [0, 1]);
      expect(report.picked, 0);
    });

    test('a picked song stands in: playlist, heart and counts go to it', () async {
      final mine = await repo.addSong(
          title: 'Song', artist: 'Ann', album: 'Studio', filePath: '/new/s.mp3', durationSeconds: 150);
      final data = await oldPhone();
      final i = data.songs.indexWhere((s) => s.title == 'Song (Live)');
      final report = await service(db).restore(data, picks: {i: mine});
      expect(report.picked, 1);
      expect(report.found, 1);
      expect(report.notFound, hasLength(1), reason: 'the other one is still not found');
      final fav = await db.customSelect('SELECT favorite AS f FROM songs').getSingle();
      expect(fav.read<bool>('f'), isTrue);
      final inList = await db.customSelect('SELECT song_id FROM playlist_songs').get();
      expect(inList.map((r) => r.read<int>('song_id')), [mine]);
    });

    test('a pick never replaces a song that was found, and a bad number is ignored', () async {
      final mine = await repo.addSong(
          title: 'Beta', artist: 'Ann', album: 'First', filePath: '/new/b.mp3', durationSeconds: 90);
      final other = await repo.addSong(
          title: 'Else', artist: 'Zed', album: 'Z', filePath: '/new/z.mp3', durationSeconds: 10);
      final data = await oldPhone();
      final beta = data.songs.indexWhere((s) => s.title == 'Beta');
      final report = await service(db).restore(data, picks: {beta: other, 99: other, -1: other});
      expect(report.picked, 0);
      expect(report.found, 1);
      final inList = await db.customSelect('SELECT song_id FROM playlist_songs').get();
      expect(inList.map((r) => r.read<int>('song_id')), [mine]);
    });

    test('restoring again with the pick adds nothing twice', () async {
      final mine = await repo.addSong(
          title: 'Song', artist: 'Ann', album: 'Studio', filePath: '/new/s.mp3', durationSeconds: 150);
      final data = await oldPhone();
      final i = data.songs.indexWhere((s) => s.title == 'Song (Live)');
      await service(db).restore(data);
      await service(db).restore(data, picks: {i: mine});
      await service(db).restore(data, picks: {i: mine});
      final inList = await db.customSelect('SELECT song_id FROM playlist_songs').get();
      expect(inList, hasLength(1));
    });
  });

  group('exporting the copied songs', () {
    Future<(String, String)> copied() async {
      final lib = Directory(p.join(root.path, 'library'))..createSync();
      final a = File(p.join(lib.path, 'uuid1_a.mp3'))..writeAsBytesSync([1, 2, 3]);
      final b = File(p.join(lib.path, 'uuid2_b.mp3'))..writeAsBytesSync([4, 5]);
      await repo.addSong(title: 'Hello: World?', artist: 'Ann', album: 'X', filePath: a.path);
      await repo.addSong(title: 'Hello: World?', artist: 'Ann', album: 'X', filePath: b.path);
      await repo.addSong(title: 'Folder Song', artist: 'Zed', album: 'Y', filePath: p.join(root.path, 'Music', 'f.mp3'));
      return (lib.path, p.join(root.path, 'out'));
    }

    test('only the songs kept inside the app count as copies', () async {
      final (lib, _) = await copied();
      final list = await service(db, copies: lib).copiedSongs();
      expect(list.map((s) => s.title), ['Hello: World?', 'Hello: World?']);
    });

    test('they are copied to the folder under readable names, never over each other', () async {
      final (lib, out) = await copied();
      final r = await service(db, copies: lib).exportCopies(out);
      expect(r.copied, 2);
      expect(r.failed, 0);
      final names = Directory(out).listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(names, ['Ann - Hello_ World_ (2).mp3', 'Ann - Hello_ World_.mp3']);
      expect(File(p.join(out, 'Ann - Hello_ World_.mp3')).readAsBytesSync(), [1, 2, 3]);
    });

    test('a file that is gone is counted as failed, the rest still copy', () async {
      final (lib, out) = await copied();
      File(p.join(lib, 'uuid1_a.mp3')).deleteSync();
      final r = await service(db, copies: lib).exportCopies(out);
      expect(r.copied, 1);
      expect(r.failed, 1);
    });

    test('with no copies there is nothing to do', () async {
      expect(await service(db, copies: '').copiedSongs(), isEmpty);
    });
  });

  group('the screen', () {
    late _Picker picker;
    setUp(() => picker = _Picker());

    Future<void> open(WidgetTester tester, {String? copies}) async {
      tester.view.physicalSize = const Size(500, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          libraryRepositoryProvider.overrideWithValue(repo),
          backupPickerProvider.overrideWithValue(picker),
          importServiceProvider.overrideWith((ref) async => LibraryImportService(
                library: repo,
                extractor: _NoTags(),
                libraryDir: Directory(copies ?? p.join(root.path, 'library')),
                artDir: Directory(p.join(root.path, 'art')),
                exclusions: MemoryExclusionStore(),
              )),
        ],
        child: const MaterialApp(home: BackupScreen()),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('Match by hand: pick the song, apply, and it is restored again with it', (tester) async {
      final mine = await repo.addSong(
          title: 'Song', artist: 'Ann', album: 'Studio', filePath: '/new/s.mp3', durationSeconds: 150);
      picker.file = (await oldPhone()).encode();
      await open(tester);
      await tester.tap(find.text('Choose a backup file'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('restore-button')));
      await settle(tester);
      expect(find.byKey(const Key('match-by-hand')), findsOneWidget);
      await tester.tap(find.byKey(const Key('match-by-hand')));
      await settle(tester);
      expect(find.text('Match by hand'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('hand-apply'))).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('hand-0')));
      await settle(tester);
      expect(find.text('Which song is it?'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('pick-$mine')));
      await settle(tester);
      expect(find.textContaining('is Song'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hand-apply')));
      await settle(tester);

      // The report again, now with the song matched.
      expect(find.text('Matched by hand'), findsOneWidget);
      final inList = await db.customSelect('SELECT song_id FROM playlist_songs').get();
      expect(inList.map((r) => r.read<int>('song_id')), [mine]);
    });

    testWidgets('cancelling the hand match ends the restore with what was done', (tester) async {
      await repo.addSong(title: 'Song', artist: 'Ann', album: 'Studio', filePath: '/new/s.mp3', durationSeconds: 150);
      picker.file = (await oldPhone()).encode();
      await open(tester);
      await tester.tap(find.text('Choose a backup file'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('restore-button')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('match-by-hand')));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Restored'), findsNothing);
      expect(find.byKey(const Key('restore-button')), findsNothing);
    });

    testWidgets('the export button shows only when there are copied songs, and copies them', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('export-copies')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      final lib = Directory(p.join(root.path, 'library'))..createSync();
      final f = File(p.join(lib.path, 'u_a.mp3'))..writeAsBytesSync([9, 9]);
      await repo.addSong(title: 'Mine', artist: 'Ann', album: 'X', filePath: f.path);
      picker.folder = p.join(root.path, 'exported');
      await open(tester);
      expect(find.text('Export 1 copied song to a folder'), findsOneWidget);
      await tester.tap(find.byKey(const Key('export-copies')));
      await settle(tester);
      await settle(tester);
      for (var i = 0; i < 20 && find.byType(SnackBar).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Copied 1 song to the folder.'), findsOneWidget);
      expect(File(p.join(root.path, 'exported', 'Ann - Mine.mp3')).existsSync(), isTrue);
    });
  });
}
