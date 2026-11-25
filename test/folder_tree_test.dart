import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/music/folder_tree.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the folder tree in the library', () {
    late AppDatabase db;
    late LibraryRepository repo;

    Future<void> add(String title, String path) =>
        repo.addSong(title: title, artist: 'A', album: 'B', filePath: path);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      await add('a', '/storage/emulated/0/Music/Rock/a.mp3');
      await add('b', '/storage/emulated/0/Music/Rock/Live/b.mp3');
      await add('c', '/storage/emulated/0/Music/Rock/Live/c.mp3');
      await add('d', '/storage/emulated/0/Music/Jazz/d.mp3');
      await add('e', '/storage/emulated/0/Download/e.mp3');
    });

    tearDown(() => db.close());

    test('the top is where the paths first branch, not the phone\'s root', () async {
      final root = await repo.folderRoot();
      expect(root!.name, '0');
      expect(root.songCount, 5);
      expect(root.hasChildren, isTrue);
      final top = await repo.folderChildren();
      expect([for (final f in top.items) f.name], ['Download', 'Music']);
    });

    test('each folder counts every song under it and says if it has folders inside', () async {
      final top = await repo.folderChildren();
      final music = top.items.firstWhere((f) => f.name == 'Music');
      expect(music.songCount, 4);
      expect(music.hasChildren, isTrue);
      final download = top.items.firstWhere((f) => f.name == 'Download');
      expect(download.hasChildren, isFalse);
      expect(download.songCount, 1);
    });

    test('going in shows the folders inside, and so on down', () async {
      final top = await repo.folderChildren();
      final music = top.items.firstWhere((f) => f.name == 'Music');
      final level2 = await repo.folderChildren(parentId: music.id);
      expect([for (final f in level2.items) f.name], ['Jazz', 'Rock']);
      final rock = level2.items.firstWhere((f) => f.name == 'Rock');
      expect(rock.songCount, 3);
      final level3 = await repo.folderChildren(parentId: rock.id);
      expect([for (final f in level3.items) f.name], ['Live']);
      expect((await repo.folderChildren(parentId: level3.items.single.id)).items, isEmpty);
    });

    test('a folder\'s own songs are the ones directly in it', () async {
      final top = await repo.folderChildren();
      final music = top.items.firstWhere((f) => f.name == 'Music');
      final rock = (await repo.folderChildren(parentId: music.id))
          .items
          .firstWhere((f) => f.name == 'Rock');
      expect([for (final s in (await repo.songs(folderId: rock.id)).items) s.title], ['a']);
      final live = (await repo.folderChildren(parentId: rock.id)).items.single;
      expect([for (final s in (await repo.songs(folderId: live.id)).items) s.title], ['b', 'c']);
    });

    test('an unknown folder has nothing, and a search narrows the level', () async {
      expect((await repo.folderChildren(parentId: 424242)).items, isEmpty);
      final q = await repo.folderChildren(query: 'mus');
      expect([for (final f in q.items) f.name], ['Music']);
    });

    test('with no music from files there is no tree', () async {
      final empty = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(empty.close);
      expect(await LibraryRepository(empty).folderRoot(), isNull);
      expect((await LibraryRepository(empty).folderChildren()).items, isEmpty);
    });

    test('paths never leave the Player in what is sent', () async {
      final top = await repo.folderChildren();
      for (final f in top.items) {
        expect(f.toJson().toString(), isNot(contains('storage')));
      }
    });
  });

  group('the folder tree screen', () {
    late FakeMusicSource source;

    setUp(() {
      source = FakeMusicSource(songs: [
        song(1, 'Direct One'),
        song(2, 'Direct Two'),
        song(3, 'Deep Song'),
      ]);
      const root = RemoteFolder(id: 1, name: 'Music', songCount: 3, hasChildren: true);
      const rock = RemoteFolder(id: 2, name: 'Rock', parent: 'Music', songCount: 1, hasChildren: true);
      const live = RemoteFolder(id: 3, name: 'Live', parent: 'Rock', songCount: 1);
      source.treeRoot = root;
      source.treeChildren[1] = [rock];
      source.treeChildren[2] = [live];
      source.folderSongs[1] = [1, 2];
      source.folderSongs[3] = [3];
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(FolderTreeView(source: source)));
      await settleUi(tester);
    }

    testWidgets('starts at the top: its folders, then its own songs', (tester) async {
      await open(tester);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('Direct One'), findsOneWidget);
      expect(find.text('Direct Two'), findsOneWidget);
      expect(find.byTooltip('Up one folder'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded)).onPressed,
        isNull);
    });

    testWidgets('going in, the path shows, and up goes back with that folder marked',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('Rock'));
      await settleUi(tester);
      expect(find.text('Music › Rock'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      await tester.tap(find.text('Live'));
      await settleUi(tester);
      expect(find.text('Deep Song'), findsOneWidget);
      expect(find.text('Music › Rock › Live'), findsOneWidget);
      await tester.tap(find.byTooltip('Up one folder'));
      await settleUi(tester);
      expect(find.text('Music › Rock'), findsOneWidget);
      final tile = tester.widget<ListTile>(find.ancestor(of: find.text('Live'), matching: find.byType(ListTile)));
      expect(tile.tileColor, isNotNull, reason: 'the folder we came from is marked');
    });

    testWidgets('tapping a song plays the folder\'s songs from there', (tester) async {
      await open(tester);
      await tester.tap(find.text('Direct Two'));
      await settleUi(tester);
      expect(source.calls.any((c) => c.startsWith('play') && c.contains('1') && c.contains('2')), isTrue,
          reason: source.calls.toString());
    });

    testWidgets('no music from files says what to do', (tester) async {
      source.treeRoot = null;
      await open(tester);
      expect(find.textContaining('No music from files'), findsOneWidget);
    });

    testWidgets('an error is shown plainly', (tester) async {
      source.failWith = StateError('offline');
      await open(tester);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    });
  });
}
