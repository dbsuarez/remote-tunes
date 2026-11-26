import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
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
  Uint8List? file;
  @override
  Future<bool> save(BuildContext context, String fileName, Uint8List bytes) async {
    saved[fileName] = bytes;
    return true;
  }

  @override
  Future<Uint8List?> pickFile(BuildContext context) async => file;
  @override
  Future<String?> pickFolder(BuildContext context) async => null;
}

class _NoTags implements MetadataExtractor {
  @override
  Future<ExtractedMetadata> extract(String path) async => const ExtractedMetadata();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  BackupService service(AppDatabase d) => BackupService(
      db: d, settings: SettingsRepository(d), exclusions: MemoryExclusionStore(), copiedSongsDir: '/app/library');

  /// An old phone with two songs: one played (and hearted), one only heard once with no heart.
  Future<(BackupService, AppDatabase)> oldPhone() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final r = LibraryRepository(db);
    final a = await r.addSong(title: 'Alpha', artist: 'Ann', album: 'First', filePath: '/old/a.mp3', durationSeconds: 100);
    final b = await r.addSong(title: 'Beta', artist: 'Bob', album: 'Second', filePath: '/old/b.mp3', durationSeconds: 90);
    await r.addSong(title: 'Never', artist: 'Cy', album: 'Third', filePath: '/old/c.mp3', durationSeconds: 80);
    await r.setFavorite(a, true);
    await r.recordPlayEvent(a, DateTime.fromMillisecondsSinceEpoch(1700000000000), 100, 'finished');
    await r.recordPlayEvent(a, DateTime.fromMillisecondsSinceEpoch(1700001000000), 12, 'skipped');
    await r.recordPlayEvent(b, DateTime.fromMillisecondsSinceEpoch(1700002000000), 60, 'stopped');
    return (service(db), db);
  }

  group('in the file', () {
    test('the play history is in the backup by default, and survives being saved and read', () async {
      final (s, _) = await oldPhone();
      final data = await s.create();
      expect(data.playLog, hasLength(3));
      final back = BackupData.decode(data.encode());
      expect(back.playLog, hasLength(3));
      expect(back.playLog.map((e) => e.outcome), ['finished', 'skipped', 'stopped']);
      expect(back.playLog.first.heardSeconds, 100);
      expect(back.playLog.first.startedAt, 1700000000);
      expect(back.songs[back.playLog.first.songIndex].title, 'Alpha');
    });

    test('a song with history only carries no heart or counts', () async {
      final (s, _) = await oldPhone();
      final data = await s.create();
      final beta = data.songs.firstWhere((x) => x.title == 'Beta');
      expect(beta.favorite, isFalse);
      expect(beta.plays, 0);
      final alpha = data.songs.firstWhere((x) => x.title == 'Alpha');
      expect(alpha.favorite, isTrue);
    });

    test('with the switch off there is no history, and songs only there are left out', () async {
      final (s, _) = await oldPhone();
      final data = await s.create(history: false);
      expect(data.playLog, isEmpty);
      expect(data.songs.map((x) => x.title), ['Alpha'], reason: 'only the hearted one');
    });

    test('history alone: the songs are in, with no activity', () async {
      final (s, _) = await oldPhone();
      final data = await s.create(activity: false, settings: false, lyrics: false);
      expect(data.playLog, hasLength(3));
      expect(data.favorites, 0);
      expect(data.playlists, isEmpty);
    });

    test('a damaged history is skipped, not trusted', () {
      final data = BackupData(created: DateTime(2026), songs: [
        BackupSong(title: 'A', artist: '', album: '', durationSeconds: 1),
      ], playLog: const [
        BackupPlay(0, 1700000000, 50, 'finished'),
      ]);
      final json = data.toJson();
      (json['plays'] as List)
        ..add(['x', 1, 2, 'finished'])
        ..add([5, 1700000000, 10, 'finished']) // a song that is not there
        ..add([0, 1700000500, 999999, 'weird'])
        ..add([0, 1]);
      final back = BackupData.decode(utf8.encode(jsonEncode(json)));
      expect(back.playLog, hasLength(2));
      expect(back.playLog.last.heardSeconds, 86400, reason: 'an absurd length is capped');
      expect(back.playLog.last.outcome, 'stopped', reason: 'an unknown ending is just "stopped"');
    });
  });

  group('putting it back', () {
    Future<(AppDatabase, LibraryRepository)> newPhone() async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final r = LibraryRepository(db);
      await r.addSong(title: 'Alpha', artist: 'Ann', album: 'First', filePath: '/new/a.mp3', durationSeconds: 100);
      await r.addSong(title: 'Beta', artist: 'Bob', album: 'Second', filePath: '/new/b.mp3', durationSeconds: 90);
      return (db, r);
    }

    test('the plays arrive on the matching songs', () async {
      final (s, _) = await oldPhone();
      final data = await s.create();
      final (db, repo) = await newPhone();
      final report = await service(db).restore(data);
      expect(report.historyAdded, 3);
      expect(await repo.playEventCount(), 3);
      final rows = await db
          .customSelect('SELECT s.title AS t, e.heard_seconds AS h, e.outcome AS o FROM play_events e JOIN songs s ON s.id = e.song_id ORDER BY e.started_at')
          .get();
      expect(rows.map((r) => r.read<String>('t')), ['Alpha', 'Alpha', 'Beta']);
      expect(rows.map((r) => r.read<int>('h')), [100, 12, 60]);
    });

    test('restoring twice adds nothing twice', () async {
      final (s, _) = await oldPhone();
      final data = await s.create();
      final (db, repo) = await newPhone();
      await service(db).restore(data);
      final again = await service(db).restore(data);
      expect(again.historyAdded, 0);
      expect(await repo.playEventCount(), 3);
    });

    test('plays of a song that is not found here are left out', () async {
      final (s, _) = await oldPhone();
      final data = await s.create();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LibraryRepository(db);
      await repo.addSong(title: 'Alpha', artist: 'Ann', album: 'First', filePath: '/new/a.mp3', durationSeconds: 100);
      final report = await service(db).restore(data);
      expect(report.historyAdded, 2);
    });

    test('with the history unticked nothing is added', () async {
      final (s, _) = await oldPhone();
      final data = await s.create();
      final (db, repo) = await newPhone();
      final report = await service(db).restore(data, includeHistory: false);
      expect(report.historyAdded, 0);
      expect(await repo.playEventCount(), 0);
    });

    test('plays already here are kept alongside', () async {
      final (s, _) = await oldPhone();
      final data = await s.create();
      final (db, repo) = await newPhone();
      final id = (await repo.songs(query: 'Alpha')).items.single.id;
      await repo.recordPlayEvent(id, DateTime.fromMillisecondsSinceEpoch(1800000000000), 30, 'stopped');
      await service(db).restore(data);
      expect(await repo.playEventCount(), 4);
    });
  });

  group('the screen', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late _Picker picker;
    late Directory dir;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      picker = _Picker();
      dir = Directory.systemTemp.createTempSync('bkh');
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 2200);
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
                libraryDir: Directory('${dir.path}/library'),
                artDir: Directory('${dir.path}/art'),
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

    Future<void> seedPlays() async {
      final id = await repo.addSong(title: 'Alpha', artist: 'Ann', album: 'First', filePath: '/m/a.mp3', durationSeconds: 100);
      await repo.recordPlayEvent(id, DateTime.now(), 100, 'finished');
    }

    testWidgets('the switch is on by default, and "lyrics and art only" turns it off', (tester) async {
      await open(tester);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('backup-history'))).value, isTrue);
      await tester.tap(find.byKey(const Key('lyrics-art-only')));
      await tester.pump();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('backup-history'))).value, isFalse);
    });

    testWidgets('a backup made with the switch on holds the history; off, it does not', (tester) async {
      await seedPlays();
      await open(tester);
      await tester.tap(find.text('Back up to a file'));
      await settle(tester);
      expect(BackupData.decode(picker.saved.values.single).playLog, hasLength(1));
      await tester.tap(find.text('OK'));
      await settle(tester);
      picker.saved.clear();
      await tester.tap(find.byKey(const Key('backup-history')));
      await tester.pump();
      await tester.tap(find.text('Back up to a file'));
      await settle(tester);
      expect(BackupData.decode(picker.saved.values.single).playLog, isEmpty);
    });

    testWidgets('a chosen file shows its history with a box to leave it out', (tester) async {
      final (s, _) = await oldPhone();
      picker.file = (await s.create()).encode();
      await repo.addSong(title: 'Alpha', artist: 'Ann', album: 'First', filePath: '/new/a.mp3', durationSeconds: 100);
      await open(tester);
      await tester.tap(find.text('Choose a backup file'));
      await settle(tester);
      expect(find.textContaining('3 plays in the history'), findsOneWidget);
      expect(find.byKey(const Key('restore-history')), findsOneWidget);
      await tester.tap(find.byKey(const Key('restore-button')));
      await settle(tester);
      expect(find.text('Plays added to the history'), findsOneWidget);
      expect(await repo.playEventCount(), 2, reason: 'Beta is not on this phone');
    });
  });
}
