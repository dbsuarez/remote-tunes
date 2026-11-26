import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/features/library/folder_browser.dart';

class FakeFolders implements FolderSource {
  FakeFolders({this.cards = false});

  final bool cards;
  final unreadable = <String>{};

  /// Folder path to what is in it (names; a name with a dot is a song).
  final tree = <String, List<String>>{
    '/phone': ['Music', 'Podcasts', 'Empty'],
    '/phone/Music': ['Rock', 'one.mp3', 'two.mp3'],
    '/phone/Music/Rock': ['deep.mp3'],
    '/phone/Podcasts': ['show.mp3'],
    '/phone/Empty': [],
    '/card': ['Books'],
    '/card/Books': ['ch1.mp3'],
  };

  @override
  Future<List<StorageRoot>> roots() async =>
      [const StorageRoot('Phone storage', '/phone'), if (cards) const StorageRoot('SD card', '/card')];

  @override
  Future<FolderContents> list(String path) async {
    if (unreadable.contains(path) || !tree.containsKey(path)) throw const FileSystemException('no');
    final names = tree[path]!;
    return FolderContents(
      [for (final n in names) if (!n.contains('.')) '$path/$n'],
      [for (final n in names) if (n.contains('.')) '$path/$n'],
    );
  }
}

void main() {
  late FakeFolders folders;
  String? chosen;
  var answered = false;

  setUp(() {
    folders = FakeFolders();
    chosen = null;
    answered = false;
  });

  Future<void> open(WidgetTester tester, {Future<String?> Function()? system, ProviderContainer? container}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              chosen = await showFolderBrowser(context, title: 'Add a folder', systemPicker: system);
              answered = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(container == null
        ? ProviderScope(overrides: [folderSourceProvider.overrideWithValue(folders)], child: app)
        : UncontrolledProviderScope(container: container, child: app));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  Future<void> into(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('browser-folder-$name')));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  String trail(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('browser-trail'))).data!;

  testWidgets('shows the folders with what is in them', (tester) async {
    await open(tester);
    expect(trail(tester), 'Phone storage');
    expect(find.text('2 songs · 1 folder'), findsOneWidget);
    expect(find.text('1 song'), findsOneWidget);
    expect(find.text('Empty'), findsNWidgets(2), reason: 'the folder called Empty, and what it says');
  });

  testWidgets('goes in, shows the songs, and gives the folder chosen', (tester) async {
    await open(tester);
    await into(tester, 'Music');
    expect(trail(tester), 'Phone storage › Music');
    expect(find.text('one.mp3'), findsOneWidget);
    expect(find.text('two.mp3'), findsOneWidget);
    expect(find.byKey(const ValueKey('browser-folder-Rock')), findsOneWidget);
    await tap(tester, 'browser-choose');
    expect(chosen, '/phone/Music');
  });

  testWidgets('Up and the Back button go up; at the top Back closes with nothing', (tester) async {
    await open(tester);
    await into(tester, 'Music');
    await into(tester, 'Rock');
    await tap(tester, 'browser-up');
    expect(trail(tester), 'Phone storage › Music');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(trail(tester), 'Phone storage');
    expect(tester.widget<IconButton>(find.byKey(const Key('browser-up'))).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect((answered, chosen), (true, null));
  });

  testWidgets('the close button leaves from anywhere', (tester) async {
    await open(tester);
    await into(tester, 'Music');
    await tap(tester, 'browser-close');
    expect((answered, chosen), (true, null));
  });

  testWidgets('with an SD card it starts at the list of storages', (tester) async {
    folders = FakeFolders(cards: true);
    await open(tester);
    expect(find.byKey(const Key('browser-choose')), findsNothing, reason: 'nothing to add yet');
    await tester.tap(find.byKey(const ValueKey('browser-root-SD card')));
    await tester.pumpAndSettle();
    await into(tester, 'Books');
    expect(trail(tester), 'SD card › Books');
    await tap(tester, 'browser-up');
    await tap(tester, 'browser-up');
    expect(find.byKey(const ValueKey('browser-root-Phone storage')), findsOneWidget);
  });

  testWidgets('a folder that cannot be read says so, and cannot be added', (tester) async {
    folders.unreadable.add('/phone/Music');
    await open(tester);
    expect(find.text("Can't be read"), findsOneWidget);
    await into(tester, 'Music');
    expect(find.text("This folder can't be read."), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('browser-choose'))).onPressed, isNull);
    await tap(tester, 'browser-up');
    expect(trail(tester), 'Phone storage');
  });

  testWidgets('an empty folder says so', (tester) async {
    await open(tester);
    await into(tester, 'Empty');
    expect(find.text('No folders or songs here.'), findsOneWidget);
  });

  testWidgets('opens again where it was last, and starts over if that folder is gone', (tester) async {
    final container = ProviderContainer(overrides: [folderSourceProvider.overrideWithValue(folders)]);
    addTearDown(container.dispose);
    await open(tester, container: container);
    await into(tester, 'Music');
    await tap(tester, 'browser-choose');
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(trail(tester), 'Phone storage › Music');
    await tap(tester, 'browser-close');
    folders.tree.remove('/phone/Music');
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(trail(tester), 'Phone storage');
  });

  testWidgets("Android's picker is still there in the menu", (tester) async {
    await open(tester, system: () async => '/elsewhere');
    await tap(tester, 'browser-menu');
    await tester.tap(find.text("Use Android's picker"));
    await tester.pumpAndSettle();
    expect(chosen, '/elsewhere');
  });

  test('the phone source lists folders and songs by name, without hidden ones', () async {
    final root = await Directory.systemTemp.createTemp('rt_browser_');
    addTearDown(() => root.delete(recursive: true));
    for (final d in ['zeta', 'Alpha', '.hidden']) {
      await Directory(p.join(root.path, d)).create();
    }
    for (final f in ['b.mp3', 'A.flac', 'notes.txt', '.secret.mp3']) {
      await File(p.join(root.path, f)).writeAsString('x');
    }
    final c = await PhoneFolderSource().list(root.path);
    expect(c.folders.map(p.basename), ['Alpha', 'zeta']);
    expect(c.songs.map(p.basename), ['A.flac', 'b.mp3']);
    await expectLater(PhoneFolderSource().list(p.join(root.path, 'nothing')), throwsA(isA<FileSystemException>()));
  });
}
