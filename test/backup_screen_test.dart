import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  final saved = <String, Uint8List>{};
  bool cancelSave = false;
  Uint8List? file;
  String? folder;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (cancelSave) return false;
    saved[fileName] = bytes;
    return true;
  }

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
  late _Picker picker;
  late MemoryExclusionStore out;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    picker = _Picker();
    out = MemoryExclusionStore();
  });

  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('bk');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backupPickerProvider.overrideWithValue(picker),
        importServiceProvider.overrideWith((ref) async => LibraryImportService(
              library: repo,
              extractor: _NoTags(),
              libraryDir: Directory('${dir.path}/library'),
              artDir: Directory('${dir.path}/art'),
              exclusions: out,
            )),
      ],
      child: const MaterialApp(home: BackupScreen()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<Uint8List> oldPhoneBackup() async {
    final other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    final r = LibraryRepository(other);
    final a = await r.addSong(
        title: 'Alpha', artist: 'Ann', album: 'First', filePath: '/old/Music/a.mp3', durationSeconds: 100);
    final p = await r.createPlaylist('Gym');
    await r.addToPlaylist(p, [a]);
    await r.setFavorite(a, true);
    final s = BackupService(
        db: other,
        settings: SettingsRepository(other),
        exclusions: MemoryExclusionStore(),
        copiedSongsDir: '/app/library');
    return (await s.create()).encode();
  }

  testWidgets('Back up saves a file with today\'s date that can be read back', (tester) async {
    await repo.addSong(
        title: 'Alpha', artist: 'Ann', album: 'First', filePath: '/m/a.mp3', durationSeconds: 100);
    await open(tester);
    await tester.tap(find.text('Back up to a file'));
    await settle(tester);
    expect(picker.saved, hasLength(1));
    final name = picker.saved.keys.single;
    expect(name, matches(RegExp(r'^RemoteTunes-\d{4}-\d{2}-\d{2}\.rtbackup$')));
    expect(BackupData.decode(picker.saved.values.single), isA<BackupData>());
    expect(find.text('Backup saved'), findsOneWidget);
    expect(find.textContaining('Copy it to the other phone'), findsOneWidget);
  });

  testWidgets('cancelling the save says nothing was saved', (tester) async {
    picker.cancelSave = true;
    await open(tester);
    await tester.tap(find.text('Back up to a file'));
    await settle(tester);
    expect(find.text('Nothing was saved.'), findsOneWidget);
    expect(find.text('Backup saved'), findsNothing);
  });

  testWidgets('the switches decide what goes in', (tester) async {
    await db.into(db.lyricsCache).insert(LyricsCacheCompanion.insert(
        trackKey: 'a|b|c|1', found: const Value(true), plainLyrics: const Value('words'), fetchedAt: DateTime.now()));
    await SettingsRepository(db).writeValue('skin_id', 'ember');
    await open(tester);
    await tester.tap(find.text('Include lyrics'));
    await tester.tap(find.text('Include settings'));
    await tester.pump();
    await tester.tap(find.text('Back up to a file'));
    await settle(tester);
    final d = BackupData.decode(picker.saved.values.single);
    expect(d.lyrics, isEmpty);
    expect(d.settings, isEmpty);
  });

  testWidgets('Restore: choose a file, say where the music is, and it reports', (tester) async {
    // The new phone has the same song, somewhere else.
    await repo.addSong(
        title: 'Alpha', artist: 'Ann', album: 'First', filePath: '/new/Songs/a.mp3', durationSeconds: 100);
    picker.file = await oldPhoneBackup();
    picker.folder = '/new/Songs';
    await open(tester);
    expect(find.byKey(const Key('restore-button')), findsNothing, reason: 'nothing chosen yet');

    await tester.tap(find.text('Choose a backup file'));
    await settle(tester);
    expect(find.textContaining('1 playlist'), findsOneWidget);
    expect(find.textContaining('On the old phone it was in /old/Music'), findsOneWidget);
    expect(find.text('Not chosen (songs are matched by their tags)'), findsOneWidget);

    await tester.tap(find.text('Choose'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('restore-root'))).data, '/new/Songs');

    await tester.tap(find.byKey(const Key('restore-button')));
    await settle(tester);
    expect(find.text('Restored'), findsOneWidget);
    expect(find.text('Found by their place'), findsOneWidget);
    expect(find.text('Playlists made'), findsOneWidget);
    expect(find.text('Favorites set'), findsOneWidget);
    // It really happened.
    final fav = await db.customSelect('SELECT favorite FROM songs').getSingle();
    expect(fav.read<bool>('favorite'), isTrue);
    final lists = await db.customSelect('SELECT name FROM playlists').get();
    expect(lists.single.read<String>('name'), 'Gym');
  });

  testWidgets('songs that are not on this phone are listed in the report', (tester) async {
    await repo.addSong(
        title: 'Other', artist: 'Zed', album: 'Z', filePath: '/new/z.mp3', durationSeconds: 10);
    picker.file = await oldPhoneBackup();
    await open(tester);
    await tester.tap(find.text('Choose a backup file'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('restore-button')));
    await settle(tester);
    expect(find.text('Not found on this phone'), findsOneWidget);
    expect(find.text('Alpha (Ann)'), findsOneWidget);
  });

  testWidgets('an empty library is warned about before restoring', (tester) async {
    picker.file = await oldPhoneBackup();
    await open(tester);
    await tester.tap(find.text('Choose a backup file'));
    await settle(tester);
    expect(find.textContaining('This phone has no songs yet'), findsOneWidget);
  });

  testWidgets('a file that is not a backup gets a plain message and nothing changes',
      (tester) async {
    picker.file = Uint8List.fromList('hello'.codeUnits);
    await open(tester);
    await tester.tap(find.text('Choose a backup file'));
    await settle(tester);
    expect(find.text('That is not a RemoteTunes backup.'), findsOneWidget);
    expect(find.byKey(const Key('restore-button')), findsNothing);
  });

  testWidgets('cancelling the file choice does nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Choose a backup file'));
    await settle(tester);
    expect(find.byKey(const Key('restore-button')), findsNothing);
  });
}
