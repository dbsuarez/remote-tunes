import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/core/list_memory.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/features/music/music_browser.dart';
import 'package:remote_tunes/features/player/audiobook_tracker.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';
import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

class _NameTags implements MetadataExtractor {
  @override
  Future<ExtractedMetadata> extract(String path) async => ExtractedMetadata(
        title: p.basenameWithoutExtension(path),
        artist: 'Author',
        album: p.basename(p.dirname(path)),
        durationSeconds: 3600,
      );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });
  tearDown(() => db.close());

  Future<int> add(String title, {String artist = 'Ann', String album = 'Alpha', String? genre, String? path}) async {
    final id = await repo.addSong(
        title: title, artist: artist, album: album, filePath: path ?? '/m/$title.mp3', durationSeconds: 200);
    if (genre != null) {
      await db.customUpdate("UPDATE songs SET genre = '$genre' WHERE id = $id", updates: {db.songs});
    }
    return id;
  }

  group('songs and audiobooks are told apart', () {
    test('marking, unmarking, and asking about some ids', () async {
      final a = await add('A');
      final b = await add('B');
      expect(await repo.setAudiobook([a, b], true), 2);
      expect(await repo.setAudiobook([a], true), 0, reason: 'already marked');
      expect(await repo.audiobookIds(), {a, b});
      expect(await repo.audiobookIdsAmong([a, 99]), {a});
      expect(await repo.audiobookIdsAmong([]), isEmpty);
      await repo.setAudiobook([a], false);
      expect(await repo.audiobookIds(), {b});
    });

    test('the genre or a folder name can say it is an audiobook; nothing is ever un-marked', () async {
      final g = await add('G', genre: 'Audiobook');
      final s = await add('S', genre: 'Spoken');
      final f = await add('F', path: '/phone/Audiobooks/Dune/ch1.mp3');
      await add('Music', genre: 'Rock');
      final manual = await add('Manual');
      await repo.setAudiobook([manual], true);
      expect(await repo.markAudiobooksByTags(), 3);
      expect(await repo.audiobookIds(), {g, s, f, manual});
      expect(await repo.markAudiobooksByTags(), 0);
    });

    test('the place in an audiobook is kept, and only for audiobooks', () async {
      final a = await add('A');
      final m = await add('Music');
      await repo.setAudiobook([a], true);
      expect(await repo.audiobookPosition(a), 0);
      await repo.saveAudiobookPosition(a, 1234);
      await repo.saveAudiobookPosition(m, 99);
      expect(await repo.audiobookPosition(a), 1234);
      expect(await repo.audiobookPosition(m), 0, reason: 'music has no place');
      await repo.setAudiobook([a], false);
      expect(await repo.audiobookPosition(a), 0, reason: 'music again: forgotten');
    });

    test('the place of a list is kept', () async {
      expect(await repo.listPosition('playlist:3'), isNull);
      await repo.saveListPosition('playlist:3', 7);
      await repo.saveListPosition('playlist:3', 9);
      expect(await repo.listPosition('playlist:3'), 9);
      expect(await repo.listPosition('album:x'), isNull);
    });

    test('a song knows it is an audiobook when it travels', () {
      final j = const RemoteSong(id: 1, title: 't', artist: 'a', album: 'b', audiobook: true).toJson();
      expect(j['audiobook'], isTrue);
      expect(RemoteSong.fromJson(j).audiobook, isTrue);
      expect(const RemoteSong(id: 1, title: 't', artist: 'a', album: 'b').toJson().containsKey('audiobook'), isFalse);
    });
  });

  group('audiobooks stay out of the music', () {
    late int book1;
    late int book2;
    late int music;

    setUp(() async {
      book1 = await add('Chapter 1', artist: 'Frank Herbert', album: 'Dune');
      book2 = await add('Chapter 2', artist: 'Frank Herbert', album: 'Dune');
      music = await add('Song', artist: 'Ann', album: 'Alpha');
      await repo.setAudiobook([book1, book2], true);
    });

    test('All Songs, artists, albums and the other lists leave them out', () async {
      expect((await repo.songs()).items.map((s) => s.id), [music]);
      expect((await repo.songs()).total, 1);
      expect((await repo.artists()).items.map((a) => a.name), ['Ann']);
      expect((await repo.albums()).items.map((a) => a.name), ['Alpha']);
      expect((await repo.songs(artist: 'Frank Herbert')).items, isEmpty);
      expect((await repo.songs(view: LibraryView.newest)).items.map((s) => s.id), [music]);
    });

    test('genres leave them out too', () async {
      await db.customUpdate("UPDATE songs SET genre = 'Rock'", updates: {db.songs});
      final g = await repo.groups(kind: GroupKind.genre);
      expect(g.items.single.songCount, 1);
    });

    test('they have their own list: one entry per book, in chapter order', () async {
      final books = await repo.groups(kind: GroupKind.audiobook);
      expect(books.items.map((b) => b.name), ['Dune']);
      expect(books.items.single.songCount, 2);
      await db.customUpdate('UPDATE songs SET track_number = 2 WHERE id = $book1', updates: {db.songs});
      await db.customUpdate('UPDATE songs SET track_number = 1 WHERE id = $book2', updates: {db.songs});
      final chapters = await repo.songs(groupKind: GroupKind.audiobook, groupValue: 'Dune');
      expect(chapters.items.map((s) => s.id), [book2, book1]);
    });

    test('a playlist or a folder can still hold them', () async {
      final pl = await repo.createPlaylist('Commute');
      await repo.addToPlaylist(pl, [book1]);
      expect((await repo.songs(playlistId: pl)).items.map((s) => s.id), [book1]);
    });

    test('a book marked as music comes back into the music', () async {
      await repo.setAudiobook([book1], false);
      expect((await repo.songs()).items.map((s) => s.id).toSet(), {music, book1});
    });
  });

  group('audiobook folders, scanned apart, in as many places as you like', () {
    late Directory root;
    late MemoryMusicFoldersStore folders;
    late LibraryImportService service;

    Future<String> make(String relative) async {
      final f = File(p.join(root.path, relative));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(Uint8List.fromList(List.filled(64, 3)));
      return f.path;
    }

    setUp(() async {
      root = Directory.systemTemp.createTempSync('books');
      folders = MemoryMusicFoldersStore();
      service = LibraryImportService(
        library: repo,
        extractor: _NameTags(),
        libraryDir: Directory(p.join(root.path, 'library')),
        artDir: Directory(p.join(root.path, 'art')),
        exclusions: MemoryExclusionStore(),
        folders: folders,
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('everything in an audiobook folder is an audiobook, and it is remembered as one', () async {
      await make('Books/Dune/c1.mp3');
      await make('Books/Dune/c2.mp3');
      final r = await service.importFolder(p.join(root.path, 'Books'), audiobooks: true);
      expect(r.added, 2);
      expect((await repo.audiobookIds()), hasLength(2));
      expect((await repo.songs()).total, 0, reason: 'not in the music');
      final f = (await service.musicFolders()).single;
      expect(f.audiobooks, isTrue);
      expect(MusicFolder.fromJson(f.toJson())!.audiobooks, isTrue);
    });

    test('songs already in the library from that folder become audiobooks too', () async {
      await make('Books/Dune/c1.mp3');
      await service.importFolder(p.join(root.path, 'Books'));
      expect((await repo.audiobookIds()), isEmpty);
      await service.importFolder(p.join(root.path, 'Books'), audiobooks: true);
      expect((await repo.audiobookIds()), hasLength(1));
    });

    test('several places: each is remembered, and one rescan goes through all of them', () async {
      await make('PhoneBooks/A/a1.mp3');
      await make('SD/Other Books/B/b1.mp3');
      await service.importFolder(p.join(root.path, 'PhoneBooks'), audiobooks: true);
      await service.importFolder(p.join(root.path, 'SD', 'Other Books'), audiobooks: true);
      expect((await service.musicFolders()).where((f) => f.audiobooks), hasLength(2));
      await make('PhoneBooks/A/a2.mp3');
      await make('SD/Other Books/B/b2.mp3');
      final plan = await service.planRescan(audiobooks: true);
      expect(plan.folders, hasLength(2));
      final r = await service.rescan(plan);
      expect(r.added, 2);
      expect(await repo.audiobookIds(), hasLength(4));
    });

    test('the music rescan and the audiobook rescan do not touch each other', () async {
      await make('Music/Rock/a.mp3');
      await make('Books/Dune/c1.mp3');
      await service.importFolder(p.join(root.path, 'Music'));
      await service.importFolder(p.join(root.path, 'Books'), audiobooks: true);
      expect((await service.planRescan()).folders.map((f) => p.basename(f.path)), ['Music']);
      expect((await service.planRescan(audiobooks: true)).folders.map((f) => p.basename(f.path)), ['Books']);
      await make('Music/Rock/b.mp3');
      await make('Books/Dune/c2.mp3');
      final music = await service.rescan(await service.planRescan());
      expect(music.added, 1, reason: 'only the new song of the music folder');
      final books = await service.rescan(await service.planRescan(audiobooks: true));
      expect(books.added, 1);
      expect((await repo.songs()).total, 2);
    });

    test('an audiobook folder inside the music folder is not taken for music', () async {
      await make('Stuff/Rock/a.mp3');
      await make('Stuff/Audiobooks/Dune/c1.mp3');
      await service.importFolder(p.join(root.path, 'Stuff', 'Audiobooks'), audiobooks: true);
      final r = await service.importFolder(p.join(root.path, 'Stuff'));
      expect(r.added, 1, reason: 'just the rock song');
      expect((await repo.songs()).total, 1);
      expect(await repo.audiobookIds(), hasLength(1));
      // And a rescan of the music still leaves the books alone.
      final plan = await service.planRescan();
      final again = await service.rescan(plan);
      expect(again.added, 0);
      expect((await repo.songs()).total, 1);
    });
  });

  group('the player and the audiobooks', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;
    late AudiobookTracker tracker;
    var remember = true;

    PlayableSong track(int id, {int duration = 3600}) => PlayableSong(
          id: id,
          title: 'T$id',
          artist: 'A',
          album: 'B',
          filePath: '/m/$id.mp3',
          durationSeconds: duration,
        );

    setUp(() async {
      remember = true;
      for (var i = 1; i <= 3; i++) {
        await repo.addSong(title: 'T$i', artist: 'A', album: 'B', filePath: '/m/$i.mp3', durationSeconds: 3600);
      }
      tracker = AudiobookTracker(repo, enabled: () => remember);
      backend = FakeAudioBackend();
      engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true, audiobooks: tracker);
    });
    tearDown(() => engine.dispose());

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

    Future<void> listen(double from, double to) async {
      var t = from;
      while (t < to) {
        t += 0.5;
        backend.emitPosition(Duration(milliseconds: (t * 1000).round()));
        await Future<void>.delayed(Duration.zero);
      }
      await settle();
    }

    test('an audiobook carries on where it was left; music starts at the beginning', () async {
      await repo.setAudiobook([1], true);
      await repo.saveAudiobookPosition(1, 1500);
      await repo.saveAudiobookPosition(2, 1500); // music: ignored
      await tracker.load();
      await engine.playSongs([track(1)]);
      await settle();
      expect(backend.position, const Duration(seconds: 1500));
      expect(backend.seekCount, 1);
      await engine.playSongs([track(2)]);
      await settle();
      expect(backend.seekCount, 1, reason: 'music did not seek');
      expect(backend.position, isNot(const Duration(seconds: 1500)));
    });

    test('a place near the very start or the very end is not used', () async {
      await repo.setAudiobook([1, 2], true);
      await repo.saveAudiobookPosition(1, 5);
      await repo.saveAudiobookPosition(2, 3590);
      await tracker.load();
      await engine.playSongs([track(1)]);
      await settle();
      await engine.playSongs([track(2)]);
      await settle();
      expect(backend.seekCount, 0);
    });

    test('the place is saved as it plays, when paused, and when leaving', () async {
      await repo.setAudiobook([1], true);
      await tracker.load();
      await engine.playSongs([track(1), track(2)]);
      await settle();
      await listen(0, 25);
      expect(await repo.audiobookPosition(1), inInclusiveRange(10, 25), reason: 'about every ten seconds');
      await listen(25, 33);
      await engine.pause();
      await settle();
      expect(await repo.audiobookPosition(1), inInclusiveRange(32, 34));
      await engine.play();
      await settle();
      await engine.next();
      await settle();
      expect(await repo.audiobookPosition(1), inInclusiveRange(32, 40), reason: 'left where it was');
    });

    test('a chapter that played to its end starts again from the beginning next time', () async {
      await repo.setAudiobook([1], true);
      await repo.saveAudiobookPosition(1, 3000);
      await tracker.load();
      await engine.playSongs([track(1), track(2)]);
      await settle();
      await listen(3000, 3010);
      backend.emitCompleted();
      await settle();
      expect(await repo.audiobookPosition(1), 0);
    });

    test('with "remember my place" off nothing is saved or restored', () async {
      remember = false;
      await repo.setAudiobook([1], true);
      await repo.saveAudiobookPosition(1, 1500);
      await tracker.load();
      await engine.playSongs([track(1)]);
      await settle();
      expect(backend.seekCount, 0);
      await listen(0, 25);
      await engine.pause();
      await settle();
      expect(await repo.audiobookPosition(1), 1500, reason: 'untouched');
    });

    test('no fading or lining up gaplessly into an audiobook', () async {
      backend.canCrossfade = true;
      await engine.setCrossfade(3);
      await repo.setAudiobook([2], true);
      await tracker.load();
      await engine.playSongs([track(1, duration: 200), track(2)]);
      await settle();
      await engine.next();
      await settle();
      expect(backend.crossfades, isEmpty, reason: 'the book starts the ordinary way');
      expect(backend.loaded.last, '/m/2.mp3');
    });

    test('a list remembers which audiobook it was at, and only audiobooks', () async {
      await repo.setAudiobook([1, 2], true);
      await tracker.load();
      tracker.setActive('playlist:5');
      await engine.playSongs([track(1), track(2), track(3)], startIndex: 1);
      await settle();
      expect(await tracker.positionFor('playlist:5'), 2);
      // Music of the same list is not remembered.
      tracker.setActive('album:x');
      await engine.playSongs([track(3)]);
      await settle();
      expect(await tracker.positionFor('album:x'), isNull);
      // Not from a list: nothing is saved.
      tracker.setActive(null);
      await engine.playSongs([track(1)]);
      await settle();
      expect(await repo.listPosition('playlist:5'), 2, reason: 'unchanged');
    });
  });

  group('the library screen', () {
    late FakeMusicSource source;
    late _Memory memory;
    final marked = <(List<int>, bool)>[];

    setUp(() {
      marked.clear();
      memory = _Memory();
      source = FakeMusicSource(songs: [
        song(1, 'Apple Song'),
        const RemoteSong(id: 2, title: 'Chapter 1', artist: 'Author', album: 'Dune', durationSeconds: 3600, audiobook: true),
      ]);
      source.groupsByKind[GroupKind.audiobook] = const [RemoteGroup(name: 'Dune', songCount: 12)];
    });

    Future<void> open(WidgetTester tester, {bool homeList = false, bool withTools = true}) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        homeList: homeList,
        listMemory: withTools ? memory : null,
        onSetAudiobook: withTools ? (ids, book) async => marked.add((ids, book)) : null,
      )));
      await settleUi(tester);
    }

    testWidgets('the Audiobooks category shows when there are audiobooks, with how many books', (tester) async {
      await open(tester, homeList: true);
      expect(find.text('Audiobooks'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('count-audiobooks'))).data, '1');
    });

    testWidgets('and is not there when there are none', (tester) async {
      source.groupsByKind.clear();
      await open(tester, homeList: true);
      expect(find.text('Audiobooks'), findsNothing);
    });

    testWidgets('an audiobook row has a book icon; music does not', (tester) async {
      source = FakeMusicSource(songs: [
        song(1, 'Apple Song'),
        const RemoteSong(id: 2, title: 'Chapter 1', artist: 'Author', album: 'Dune', audiobook: true),
      ]);
      await open(tester);
      expect(find.byKey(const Key('audiobook-icon')), findsOneWidget);
    });

    testWidgets('the song menu marks a song as an audiobook, or as music', (tester) async {
      await open(tester);
      final menus = find.byTooltip('More');
      await tester.tap(menus.first);
      await tester.pumpAndSettle();
      expect(find.text('Mark as audiobook'), findsOneWidget);
      await tester.tap(find.text('Mark as audiobook'));
      await tester.pumpAndSettle();
      expect(marked.single.$1, [1]);
      expect(marked.single.$2, isTrue);
      await tester.tap(menus.last);
      await tester.pumpAndSettle();
      expect(find.text('Mark as music'), findsOneWidget);
      await tester.tap(find.text('Mark as music'));
      await tester.pumpAndSettle();
      expect(marked.last.$1, [2]);
      expect(marked.last.$2, isFalse);
    });

    testWidgets('without the tools (the web Controller) there is no such menu item', (tester) async {
      await open(tester, withTools: false);
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      expect(find.text('Mark as audiobook'), findsNothing);
    });

    testWidgets('Play all on a book carries on at the chapter it was left at', (tester) async {
      source = FakeMusicSource(songs: [
        const RemoteSong(id: 5, title: 'Ch 1', artist: 'Author', album: 'Dune', audiobook: true),
        const RemoteSong(id: 6, title: 'Ch 2', artist: 'Author', album: 'Dune', audiobook: true),
      ]);
      memory.left['album:Author|Dune'] = 6;
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        listMemory: memory,
        initialTarget: const LibraryTarget(title: 'Dune', artist: 'Author', album: 'Dune'),
      )));
      await settleUi(tester);
      await tester.tap(find.text('Play all'));
      await settleUi(tester);
      expect(source.calls.last, 'play [5, 6] start=6');
      expect(memory.active, 'album:Author|Dune');
    });

    testWidgets('Play all with nothing remembered starts at the first chapter', (tester) async {
      source = FakeMusicSource(songs: [
        const RemoteSong(id: 5, title: 'Ch 1', artist: 'Author', album: 'Dune', audiobook: true),
      ]);
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        listMemory: memory,
        initialTarget: const LibraryTarget(title: 'Dune', artist: 'Author', album: 'Dune'),
      )));
      await settleUi(tester);
      await tester.tap(find.text('Play all'));
      await settleUi(tester);
      expect(source.calls.last, 'play [5] start=null');
    });

    testWidgets('selected songs can be marked in one go', (tester) async {
      await open(tester);
      await tester.longPress(find.text('Apple Song'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Audiobook or music'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as audiobooks'));
      await tester.pumpAndSettle();
      expect(marked.single.$1, [1]);
      expect(marked.single.$2, isTrue);
    });
  });

  test('a list has the same name every time', () {
    expect(listKeyFor(playlistId: 3), 'playlist:3');
    expect(listKeyFor(groupKind: 'audiobook', groupValue: 'Dune'), 'group:audiobook|Dune');
    expect(listKeyFor(artist: 'A', album: 'B'), 'album:A|B');
    expect(listKeyFor(artist: 'A'), 'artist:A');
    expect(listKeyFor(), 'songs');
  });
}

class _Memory implements ListMemory {
  String? active;
  final left = <String, int>{};
  @override
  Future<int?> positionFor(String key) async => left[key];
  @override
  void setActive(String? key) => active = key;
}
