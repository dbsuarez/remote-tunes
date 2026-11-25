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
import 'package:remote_tunes/features/library/folder_choice.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/providers/library_providers.dart';

class _Tags implements MetadataExtractor {
  @override
  Future<ExtractedMetadata> extract(String path) async => ExtractedMetadata(
      title: p.basenameWithoutExtension(path), artist: 'A', album: 'B', durationSeconds: 100);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('a rule matches a file name', () {
    bool m(String rule, String name) => LibraryImportService.matchesRule(rule, name);

    test('plain text: any name that contains it, whatever the capitals', () {
      expect(m('intro', 'Album Intro.mp3'), isTrue);
      expect(m('INTRO', 'the intro track.flac'), isTrue);
      expect(m('intro', 'Outro.mp3'), isFalse);
    });

    test('* is any text and ? is one character', () {
      expect(m('*intro*', '01 Intro (live).mp3'), isTrue);
      expect(m('*.wav', 'a.WAV'), isTrue);
      expect(m('*.wav', 'a.wav.mp3'), isFalse);
      expect(m('track??.mp3', 'track01.mp3'), isTrue);
      expect(m('track??.mp3', 'track1.mp3'), isFalse);
      expect(m('01*', '01 - Song.mp3'), isTrue);
      expect(m('01*', 'Song 01.mp3'), isFalse, reason: 'it must start with it');
    });

    test('characters that mean something to a pattern engine are just characters', () {
      expect(m('(live)', 'Song (live).mp3'), isTrue);
      expect(m('a+b*', 'a+b.mp3'), isTrue);
      expect(m('a+b*', 'aab.mp3'), isFalse);
      expect(m('[x]', 'a [x] b.mp3'), isTrue);
    });

    test('an empty rule matches nothing', () {
      expect(m('', 'a.mp3'), isFalse);
      expect(m('   ', 'a.mp3'), isFalse);
    });
  });

  group('rules and the library', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late Directory root;
    late MemoryExclusionStore out;
    late MemoryMusicFoldersStore folders;
    late LibraryImportService service;

    Future<String> make(String relative) async {
      final f = File(p.join(root.path, 'Music', relative));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(Uint8List.fromList(List.filled(64, 3)));
      return f.path;
    }

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      root = await Directory.systemTemp.createTemp('rules');
      out = MemoryExclusionStore();
      folders = MemoryMusicFoldersStore();
      service = LibraryImportService(
        library: repo,
        extractor: _Tags(),
        libraryDir: Directory(p.join(root.path, 'library')),
        artDir: Directory(p.join(root.path, 'art')),
        exclusions: out,
        folders: folders,
      );
    });
    tearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    test('rules are added once, listed, and removed', () async {
      expect(await service.addNameRule('  *intro*  '), isTrue);
      expect(await service.addNameRule('*intro*'), isFalse, reason: 'already there');
      expect(await service.addNameRule('   '), isFalse);
      await service.addNameRule('*.wav');
      expect(await service.nameRules(), ['*.wav', '*intro*']);
      await service.removeNameRule('*.wav');
      expect(await service.nameRules(), ['*intro*']);
      expect(out.paths, {'glob:*intro*'}, reason: 'kept in the same list as folders left out');
    });

    test('adding a folder leaves out the files a rule matches, and says so in the report', () async {
      await make('Rock/song.mp3');
      await make('Rock/00 Intro.mp3');
      await make('Rock/skit.mp3');
      await service.addNameRule('intro');
      await service.addNameRule('sk?t.mp3');
      final r = await service.importFolder(p.join(root.path, 'Music'));
      expect(r.added, 1);
      expect(r.excluded, 2);
      expect((await repo.songs()).items.map((s) => s.title), ['song']);
    });

    test('a rescan keeps leaving them out, and a new matching file is not added', () async {
      await make('a.mp3');
      await service.importFolder(p.join(root.path, 'Music'));
      await service.addNameRule('intro');
      await make('new intro.mp3');
      await make('new song.mp3');
      final r = await service.rescan(await service.planRescan());
      expect(r.added, 1);
      expect((await repo.songs()).total, 2);
    });

    test('a rule does not disturb the folders chosen when adding a folder', () async {
      await make('Rock/a.mp3');
      await make('Jazz/b.mp3');
      await service.addNameRule('intro');
      await service.importFolder(p.join(root.path, 'Music'), exclude: {p.join(root.path, 'Music', 'Jazz')});
      expect(out.paths, containsAll(['glob:intro', p.join(root.path, 'Music', 'Jazz')]));
    });

    test('the songs already in the library that match are found, and can be taken out', () async {
      await make('a.mp3');
      await make('Intro 1.mp3');
      await make('Intro 2.mp3');
      await service.importFolder(p.join(root.path, 'Music'));
      expect((await service.songsMatchingRule('intro')), hasLength(2));
      expect(await service.songsMatchingRule('nothing'), isEmpty);
      await service.addNameRule('intro');
      expect(await service.removeSongsMatchingRule('intro'), 2);
      expect((await repo.songs()).items.map((s) => s.title), ['a']);
      expect(out.paths, {'glob:intro'}, reason: 'removing songs adds nothing to the list');
      // Their files stay on the phone.
      expect(File(p.join(root.path, 'Music', 'Intro 1.mp3')).existsSync(), isTrue);
    });

    test('taking a rule away lets the files in the next time', () async {
      await make('Intro 1.mp3');
      await service.addNameRule('intro');
      await service.importFolder(p.join(root.path, 'Music'));
      expect((await repo.songs()).total, 0);
      await service.removeNameRule('intro');
      await service.importFolder(p.join(root.path, 'Music'));
      expect((await repo.songs()).total, 1);
    });

    test('a rule also keeps audiobook folders from taking those files', () async {
      await make('Books/Intro.mp3');
      await make('Books/Chapter.mp3');
      await service.addNameRule('intro');
      await service.importFolder(p.join(root.path, 'Music', 'Books'), audiobooks: true);
      expect(await repo.audiobookIds(), hasLength(1));
    });
  });

  group('the Excluded from library screen', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late Directory root;
    late MemoryExclusionStore out;
    late LibraryImportService service;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      root = await Directory.systemTemp.createTemp('rulesui');
      out = MemoryExclusionStore();
      service = LibraryImportService(
        library: repo,
        extractor: _Tags(),
        libraryDir: Directory(p.join(root.path, 'library')),
        artDir: Directory(p.join(root.path, 'art')),
        exclusions: out,
        folders: MemoryMusicFoldersStore(),
      );
    });
    tearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [importServiceProvider.overrideWith((ref) async => service)],
        child: const MaterialApp(home: LeftOutScreen()),
      ));
      await settle(tester);
    }

    screenTest('shows the rules apart from the folders and songs that are left out', (tester) async {
      out.paths = {'glob:*intro*', '/music/Skip Me'};
      await open(tester);
      expect(find.text('Rules'), findsOneWidget);
      expect(find.byKey(const ValueKey('rule-*intro*')), findsOneWidget);
      expect(find.text('Skip Me'), findsOneWidget);
      expect(find.text('glob:*intro*'), findsNothing, reason: 'the prefix is not shown');
    });

    screenTest('adding a rule: it is saved, and songs that match can be removed', (tester) async {
      final f = File(p.join(root.path, 'Intro one.mp3'))..writeAsBytesSync([1, 2, 3]);
      await repo.addSong(title: 'Intro one', artist: 'A', album: 'B', filePath: f.path, durationSeconds: 100);
      await repo.addSong(title: 'Keep', artist: 'A', album: 'B', filePath: '/m/keep.mp3', durationSeconds: 100);
      await open(tester);
      await tester.tap(find.byKey(const Key('add-rule')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rule-field')), '*intro*');
      await tester.tap(find.byKey(const Key('rule-add')));
      await settle(tester);
      await settle(tester);
      expect(find.textContaining('1 song in your library match'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rule-remove')));
      await settle(tester);
      expect((await repo.songs()).items.map((s) => s.title), ['Keep']);
      expect(find.byKey(const ValueKey('rule-*intro*')), findsOneWidget);
      expect(out.paths, {'glob:*intro*'});
    });

    screenTest('keeping the matching songs leaves them in the library', (tester) async {
      await repo.addSong(title: 'Intro one', artist: 'A', album: 'B', filePath: '/m/intro.mp3', durationSeconds: 100);
      await open(tester);
      await tester.tap(find.byKey(const Key('add-rule')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rule-field')), 'intro');
      await tester.tap(find.byKey(const Key('rule-add')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('rule-keep')));
      await settle(tester);
      expect((await repo.songs()).total, 1);
    });

    screenTest('a rule with nothing matching just says it was added; an empty one is refused', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('add-rule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rule-add')));
      await settle(tester);
      expect(find.text('Type a name first.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('add-rule')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rule-field')), 'zzz');
      await tester.tap(find.byKey(const Key('rule-add')));
      await settle(tester);
      expect(find.textContaining('left out from now on'), findsOneWidget);
    });

    screenTest('a rule can be removed', (tester) async {
      out.paths = {'glob:intro'};
      await open(tester);
      await tester.tap(find.byTooltip('Remove the rule intro'));
      await settle(tester);
      expect(find.byKey(const ValueKey('rule-intro')), findsNothing);
      expect(out.paths, isEmpty);
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

/// A screen test that lets go of the screen at the end (no timers or dirty elements left behind).
void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(seconds: 1));
  });
}
