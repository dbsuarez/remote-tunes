import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/core/permissions.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/folder_choice.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/features/library/music_folders_screen.dart';
import 'package:remote_tunes/providers/library_providers.dart';

class _NameTags implements MetadataExtractor {
  @override
  Future<ExtractedMetadata> extract(String path) async => ExtractedMetadata(
      title: p.basenameWithoutExtension(path), artist: 'Artist', album: 'Album', durationSeconds: 100);
}

class _Allowed implements AppPermissions {
  PermissionOutcome outcome = PermissionOutcome.granted;
  @override
  Future<PermissionOutcome> ensureMusicAccess() async => outcome;
  @override
  Future<PermissionOutcome> ensureNotifications() async => PermissionOutcome.granted;
  @override
  Future<void> openSettings() async {}
}

void main() {
  group('the new folders question', () {
    final folders = [
      const NewFolder('/m/Podcasts', 'Podcasts', 12),
      const NewFolder('/m/Rock/New', 'New', 3),
    ];
    Set<String>? answer;
    var answered = false;

    Future<void> open(WidgetTester tester) async {
      answer = null;
      answered = false;
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await showNewFolders(context, folders);
              answered = true;
            },
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('everything starts ticked, and the button says how many songs it adds', (tester) async {
      await open(tester);
      expect(find.text('New folders'), findsOneWidget);
      expect(find.text('Add 15 songs'), findsOneWidget);
      expect(find.text('12 songs'), findsOneWidget);
      expect(find.text('3 songs'), findsOneWidget);
      await tester.tap(find.text('Add 15 songs'));
      await tester.pumpAndSettle();
      expect(answer, isEmpty, reason: 'nothing to leave out');
    });

    testWidgets('an unticked folder is returned to be left out', (tester) async {
      await open(tester);
      await tester.tap(find.text('Podcasts'));
      await tester.pump();
      expect(find.text('Add 3 songs'), findsOneWidget);
      await tester.tap(find.text('Add 3 songs'));
      await tester.pumpAndSettle();
      expect(answer, {'/m/Podcasts'});
    });

    testWidgets('unticking all of them leaves them all out', (tester) async {
      await open(tester);
      await tester.tap(find.text('Podcasts'));
      await tester.tap(find.text('New'));
      await tester.pump();
      expect(find.text('Leave them out'), findsOneWidget);
      await tester.tap(find.text('Leave them out'));
      await tester.pumpAndSettle();
      expect(answer, {'/m/Podcasts', '/m/Rock/New'});
    });

    testWidgets('Cancel gives nothing, so nothing is rescanned', (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answered, isTrue);
      expect(answer, isNull);
    });
  });

  group('the missing songs question', () {
    ImportResult result(int missing, {int checked = 100}) {
      final r = ImportResult()..checked = checked;
      for (var i = 0; i < missing; i++) {
        r.missing.add(MissingSong(id: i, title: 'Song $i', artist: 'Band', path: '/m/$i.mp3'));
      }
      return r;
    }

    bool? answer;

    Future<void> open(WidgetTester tester, ImportResult r) async {
      answer = null;
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await showMissingSongs(context, r),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('names the songs, and Keep is the main button', (tester) async {
      await open(tester, result(3));
      expect(find.text('3 songs not found'), findsOneWidget);
      expect(find.text('Song 0 · Band'), findsOneWidget);
      expect(find.text('Remove 3 from the library'), findsOneWidget);
      await tester.tap(find.byKey(const Key('missing-keep')));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('Remove says yes', (tester) async {
      await open(tester, result(1));
      expect(find.text('1 song not found'), findsOneWidget);
      await tester.tap(find.byKey(const Key('missing-remove')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('a long list is cut, with how many more', (tester) async {
      await open(tester, result(20));
      expect(find.text('…and 8 more.'), findsOneWidget);
    });

    testWidgets('when most are missing it asks if the storage is connected', (tester) async {
      await open(tester, result(60));
      expect(find.textContaining('Is the storage'), findsOneWidget);
      expect(find.text('Remove anyway'), findsOneWidget);
    });
  });

  group('the report', () {
    testWidgets('has the new rows: folders scanned, missing, and folders that could not be reached',
        (tester) async {
      final r = ImportResult()
        ..foldersScanned = 2
        ..added = 3
        ..found = 10;
      r.missing.add(const MissingSong(id: 1, title: 'X', artist: '', path: '/m/x.mp3'));
      r.unreachable.add('/storage/sdcard/Music');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ImportReportDialog(result: r))));
      expect(find.text('Folders scanned'), findsOneWidget);
      expect(find.text('Missing (file not found)'), findsOneWidget);
      expect(find.textContaining('/storage/sdcard/Music'), findsOneWidget);
      expect(find.textContaining('is the storage connected'), findsOneWidget);
    });

    testWidgets('an ordinary add shows none of them', (tester) async {
      final r = ImportResult()
        ..added = 3
        ..found = 3;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ImportReportDialog(result: r))));
      expect(find.text('Folders scanned'), findsNothing);
      expect(find.text('Missing (file not found)'), findsNothing);
    });
  });

  group('the Music folders screen', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late Directory root;
    late Directory music;
    late MemoryMusicFoldersStore store;
    late MemoryExclusionStore out;
    late _Allowed permissions;

    // Plain (synchronous) file work: the widget test clock cannot wait for real I/O.
    Future<void> make(String relative) async {
      final f = File(p.join(music.path, relative));
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(Uint8List.fromList(List.filled(64, 3)));
    }

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      root = Directory.systemTemp.createTempSync('rescanui');
      music = Directory(p.join(root.path, 'Music'))..createSync();
      store = MemoryMusicFoldersStore();
      out = MemoryExclusionStore();
      permissions = _Allowed();
    });

    tearDown(() async {
      await db.close();
      root.deleteSync(recursive: true);
    });

    LibraryImportService service() => LibraryImportService(
          library: repo,
          extractor: _NameTags(),
          libraryDir: Directory(p.join(root.path, 'library')),
          artDir: Directory(p.join(root.path, 'art')),
          exclusions: out,
          folders: store,
        );

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = service();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          importServiceProvider.overrideWith((ref) async => s),
          permissionsProvider.overrideWithValue(permissions),
        ],
        child: const MaterialApp(home: MusicFoldersScreen()),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// Waits (real time, with the screen moving on) until [finder] shows: the rescan does real
    /// file work, one step after another.
    Future<void> until(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('with no folders it says how to add one', (tester) async {
      await open(tester);
      expect(find.textContaining('No folders yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rescan-now')));
      await settle(tester);
      expect(find.text('No music folders yet'), findsOneWidget);
    });

    testWidgets('it lists the folders that were added, with their size', (tester) async {
      await make('a.mp3');
      await make('b.mp3');
      await tester.runAsync(() => service().importFolder(music.path));
      await open(tester);
      expect(find.text('Music'), findsOneWidget);
      expect(find.textContaining('2 songs'), findsOneWidget);
      expect(find.textContaining('scanned just now'), findsOneWidget);
    });

    testWidgets('one tap: new songs are added and the report says so', (tester) async {
      await make('a.mp3');
      await tester.runAsync(() => service().importFolder(music.path));
      await make('new1.mp3');
      await make('new2.mp3');
      await open(tester);
      await tester.tap(find.byKey(const Key('rescan-now')));
      await until(tester, find.text('Folders scanned'));
      expect(find.text('Folders scanned'), findsOneWidget);
      expect(find.text('Added'), findsOneWidget);
      expect(await tester.runAsync(() => repo.count()), 3);
    });

    testWidgets('a new folder is asked about; leaving it out keeps it out', (tester) async {
      await make('a.mp3');
      await tester.runAsync(() => service().importFolder(music.path));
      await make('Podcasts/ep1.mp3');
      await open(tester);
      await tester.tap(find.byKey(const Key('rescan-now')));
      await until(tester, find.text('A new folder'));
      expect(find.text('A new folder'), findsOneWidget);
      expect(find.text('Podcasts'), findsOneWidget);
      await tester.tap(find.text('Podcasts'));
      await tester.pump();
      await tester.tap(find.text('Leave them out'));
      await until(tester, find.text('Folders scanned'));
      expect(await tester.runAsync(() => repo.count()), 1);
      expect(out.paths, {p.join(music.path, 'Podcasts')});
    });

    testWidgets('missing songs are offered for removal, and Remove takes them out', (tester) async {
      await make('a.mp3');
      await make('b.mp3');
      await tester.runAsync(() => service().importFolder(music.path));
      File(p.join(music.path, 'a.mp3')).deleteSync();
      await open(tester);
      await tester.tap(find.byKey(const Key('rescan-now')));
      await until(tester, find.text('Missing (file not found)'));
      expect(find.text('Missing (file not found)'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await until(tester, find.text('1 song not found'));
      expect(find.text('1 song not found'), findsOneWidget);
      await tester.tap(find.byKey(const Key('missing-remove')));
      await settle(tester);
      expect(await tester.runAsync(() => repo.count()), 1);
    });

    testWidgets('Keep leaves the missing songs alone', (tester) async {
      await make('a.mp3');
      await tester.runAsync(() => service().importFolder(music.path));
      File(p.join(music.path, 'a.mp3')).deleteSync();
      await open(tester);
      await tester.tap(find.byKey(const Key('rescan-now')));
      await until(tester, find.text('OK'));
      await tester.tap(find.text('OK'));
      await until(tester, find.byKey(const Key('missing-keep')));
      await tester.tap(find.byKey(const Key('missing-keep')));
      await settle(tester);
      expect(await tester.runAsync(() => repo.count()), 1);
    });

    testWidgets('without the music permission nothing is scanned', (tester) async {
      await make('a.mp3');
      await tester.runAsync(() => service().importFolder(music.path));
      await make('late.mp3');
      permissions.outcome = PermissionOutcome.denied;
      await open(tester);
      await tester.tap(find.byKey(const Key('rescan-now')));
      await settle(tester);
      expect(find.text('Allow access to music'), findsOneWidget);
      expect(await tester.runAsync(() => repo.count()), 1);
    });

    testWidgets('a folder can be forgotten, and the songs stay', (tester) async {
      await make('a.mp3');
      await tester.runAsync(() => service().importFolder(music.path));
      await open(tester);
      await tester.tap(find.byTooltip('Forget Music'));
      await settle(tester);
      expect(find.textContaining('No folders yet'), findsOneWidget);
      expect(await tester.runAsync(() => repo.count()), 1);
    });
  });
}
