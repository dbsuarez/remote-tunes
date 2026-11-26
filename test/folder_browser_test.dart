import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/core/file_access.dart';
import 'package:remote_tunes/features/backup/backup_screen.dart' show writeNewFile;
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

class _Access extends FileAccess {
  bool allowed = false;
  int opened = 0;
  @override
  Future<bool> canWriteAll() async => allowed;
  @override
  Future<void> openSettings() async => opened++;
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

  group('choosing a file', () {
    Future<void> openFiles(WidgetTester tester, {Set<String> types = const {'mp3', 'wav'}}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [folderSourceProvider.overrideWithValue(folders)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await showFileBrowser(context, title: 'Choose a sound', extensions: types);
                  answered = true;
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('a tap on a file gives it; there is no folder button', (tester) async {
      folders.tree['/phone/Music'] = ['Rock', 'one.mp3', 'two.m4a', 'three.wav'];
      await openFiles(tester);
      await into(tester, 'Music');
      expect(find.byKey(const Key('browser-choose')), findsNothing);
      expect(find.text('two.m4a'), findsNothing, reason: 'not a type that can be chosen');
      expect(find.byKey(const ValueKey('browser-folder-Rock')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('browser-file-three.wav')));
      await tester.pumpAndSettle();
      expect(chosen, '/phone/Music/three.wav');
    });

    testWidgets('a folder with nothing of those types says which', (tester) async {
      await openFiles(tester, types: const {'flac'});
      await into(tester, 'Podcasts');
      expect(find.text('No folders or FLAC files here.'), findsOneWidget);
    });
  });

  group('choosing several files', () {
    List<String>? many;

    Future<void> openMany(WidgetTester tester) async {
      many = null;
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [folderSourceProvider.overrideWithValue(folders)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => many = await showFilesBrowser(context, title: 'Add songs', extensions: const {'mp3'}),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('files from more than one folder are added together', (tester) async {
      await openMany(tester);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('browser-add'))).onPressed, isNull);
      await into(tester, 'Music');
      await tester.tap(find.byKey(const ValueKey('browser-file-two.mp3')));
      await tester.pumpAndSettle();
      await tap(tester, 'browser-up');
      await into(tester, 'Podcasts');
      await tap(tester, 'browser-select-all');
      expect(find.text('Add 2 files'), findsOneWidget);
      await tap(tester, 'browser-add');
      expect(many, ['/phone/Music/two.mp3', '/phone/Podcasts/show.mp3']);
    });

    testWidgets('All picks the folder, None lets it go', (tester) async {
      await openMany(tester);
      await into(tester, 'Music');
      await tap(tester, 'browser-select-all');
      expect(find.text('Add 2 files'), findsOneWidget);
      await tap(tester, 'browser-select-all');
      expect(find.text('Tap the files to add'), findsOneWidget);
      await tap(tester, 'browser-close');
      expect(many, isNull);
    });
  });

  group('files Android hides', () {
    testWidgets('it asks for All files access, and shows them once it is on', (tester) async {
      final access = _Access();
      folders.tree['/phone'] = ['Download'];
      folders.tree['/phone/Download'] = [];
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [folderSourceProvider.overrideWithValue(folders), fileAccessProvider.overrideWithValue(access)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => chosen = await showFileBrowser(context,
                    title: 'Choose a backup', extensions: const {'rtbackup'}, needsAllFiles: true),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await into(tester, 'Download');
      expect(find.textContaining('All files access'), findsOneWidget);
      await tap(tester, 'browser-allow');
      expect(access.opened, 1);
      access.allowed = true;
      folders.tree['/phone/Download'] = ['mine.rtbackup'];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('All files access'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('browser-file-mine.rtbackup')));
      await tester.pumpAndSettle();
      expect(chosen, '/phone/Download/mine.rtbackup');
    });
  });

  test('a saved backup never replaces a file', () async {
    final dir = await Directory.systemTemp.createTemp('rt_save_');
    addTearDown(() => dir.delete(recursive: true));
    final bytes = Uint8List.fromList([1]);
    final names = [for (var i = 0; i < 3; i++) p.basename((await writeNewFile(dir.path, 'a.rtbackup', bytes)).path)];
    expect(names, ['a.rtbackup', 'a (2).rtbackup', 'a (3).rtbackup']);
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
    expect(c.files.map(p.basename), ['A.flac', 'b.mp3', 'notes.txt'], reason: 'the screen picks the types it wants');
    await expectLater(PhoneFolderSource().list(p.join(root.path, 'nothing')), throwsA(isA<FileSystemException>()));
  });
}
