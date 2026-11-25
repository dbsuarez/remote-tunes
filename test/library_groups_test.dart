import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/features/music/music_browser.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

class _Extractor implements MetadataExtractor {
  final byName = <String, ExtractedMetadata>{};
  final throwFor = <String>{};
  @override
  Future<ExtractedMetadata> extract(String path) async {
    final n = p.basename(path);
    if (throwFor.contains(n)) throw const FormatException('bad');
    return byName[n] ?? const ExtractedMetadata();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('genres, years and album artists in the library', () {
    late AppDatabase db;
    late LibraryRepository repo;

    Future<int> add(String title, String path,
            {String? albumArtist, String? genre, int? year}) =>
        repo.addSong(
            title: title,
            artist: 'Ann',
            album: 'A',
            filePath: path,
            albumArtist: albumArtist,
            genre: genre,
            year: year);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      await add('One', '/m/1.mp3', albumArtist: 'The Band', genre: 'Rock', year: 1999);
      await add('Two', '/m/2.mp3', albumArtist: 'The Band', genre: 'Rock', year: 2004);
      await add('Three', '/m/3.mp3', albumArtist: 'Various', genre: 'Jazz', year: 2004);
      await add('Four', '/m/4.mp3'); // no tags
    });

    tearDown(() => db.close());

    test('genres are listed with counts; songs without one are left out', () async {
      final g = await repo.groups(kind: GroupKind.genre);
      expect([for (final e in g.items) '${e.name}:${e.songCount}'], ['Jazz:1', 'Rock:2']);
      expect(g.total, 2);
    });

    test('years come newest first', () async {
      final g = await repo.groups(kind: GroupKind.year);
      expect([for (final e in g.items) '${e.name}:${e.songCount}'], ['2004:2', '1999:1']);
    });

    test('album artists', () async {
      final g = await repo.groups(kind: GroupKind.albumArtist);
      expect([for (final e in g.items) e.name], ['The Band', 'Various']);
    });

    test('a group can be searched and paged', () async {
      final g = await repo.groups(kind: GroupKind.genre, query: 'ro');
      expect([for (final e in g.items) e.name], ['Rock']);
      final page = await repo.groups(kind: GroupKind.genre, offset: 1, limit: 1);
      expect([for (final e in page.items) e.name], ['Rock']);
      expect(page.total, 2);
    });

    test('an unknown kind gives an empty list, not an error', () async {
      final g = await repo.groups(kind: 'nonsense; drop table songs');
      expect(g.items, isEmpty);
      expect(await repo.count(), 4);
    });

    test('opening a group lists only its songs', () async {
      Future<List<String>> titles(String kind, String value) async => [
            for (final s in (await repo.songs(groupKind: kind, groupValue: value)).items) s.title
          ];
      expect(await titles(GroupKind.genre, 'Rock'), ['One', 'Two']);
      expect(await titles(GroupKind.year, '2004'), ['Three', 'Two']);
      expect(await titles(GroupKind.albumArtist, 'Various'), ['Three']);
      expect(await titles(GroupKind.genre, 'Nothing'), isEmpty);
    });

    test('search works inside a group', () async {
      final page =
          await repo.songs(groupKind: GroupKind.genre, groupValue: 'Rock', query: 'tw');
      expect([for (final s in page.items) s.title], ['Two']);
    });

    test('tags are filled in later without touching anything else', () async {
      final id = (await repo.songs(query: 'Four')).items.single.id;
      await repo.updateSongTags(id, genre: 'Pop', year: 1985);
      final s = (await repo.songById(id))!;
      expect([s.genre, s.year, s.albumArtist, s.title], ['Pop', 1985, null, 'Four']);
      // A tag the file lacks keeps what is saved.
      await repo.updateSongTags(id, genre: null, year: null, albumArtist: 'X');
      final s2 = (await repo.songById(id))!;
      expect([s2.genre, s2.year, s2.albumArtist], ['Pop', 1985, 'X']);
    });
  });

  group('reading the tags again', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late _Extractor extractor;
    late Directory root;
    late LibraryImportService service;

    Future<String> makeFile(String name) async {
      final f = File(p.join(root.path, 'source', name));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(Uint8List.fromList(List.filled(32, 7)));
      return f.path;
    }

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      extractor = _Extractor();
      root = await Directory.systemTemp.createTemp('rt_tags_');
      service = LibraryImportService(
        library: repo,
        extractor: extractor,
        libraryDir: Directory(p.join(root.path, 'library')),
        artDir: Directory(p.join(root.path, 'art')),
      );
    });

    tearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    test('new songs keep their genre, year and album artist', () async {
      final f = await makeFile('a.mp3');
      extractor.byName['a.mp3'] = const ExtractedMetadata(
          title: 'A', artist: 'X', album: 'Y', albumArtist: 'The Band', genre: 'Rock', year: 1999);
      await service.importFiles([f]);
      final s = (await repo.songs()).items.single;
      expect([s.albumArtist, s.genre, s.year], ['The Band', 'Rock', 1999]);
    });

    test('old songs get theirs on refresh; titles and the rest are not changed', () async {
      final f = await makeFile('old.mp3');
      final id = await repo.addSong(title: 'Keep me', artist: 'Keep', album: 'Keep', filePath: f);
      extractor.byName['old.mp3'] = const ExtractedMetadata(
          title: 'Different', artist: 'Different', genre: 'Jazz', year: 1960);
      final progress = <String>[];
      final filled = await service.refreshTags(
          onProgress: (pr) => progress.add('${pr.done}/${pr.total}'));
      expect(filled, 1);
      final s = (await repo.songById(id))!;
      expect([s.genre, s.year, s.title, s.artist], ['Jazz', 1960, 'Keep me', 'Keep']);
      expect(progress.last, '1/1');
    });

    test('missing and unreadable files are skipped, the rest carry on', () async {
      final good = await makeFile('good.mp3');
      final bad = await makeFile('bad.mp3');
      await repo.addSong(title: 'Gone', artist: 'a', album: 'b', filePath: p.join(root.path, 'nope.mp3'));
      await repo.addSong(title: 'Bad', artist: 'a', album: 'b', filePath: bad);
      await repo.addSong(title: 'Good', artist: 'a', album: 'b', filePath: good);
      extractor.throwFor.add('bad.mp3');
      extractor.byName['good.mp3'] = const ExtractedMetadata(genre: 'Pop');
      expect(await service.refreshTags(), 1);
    });

    test('files with no extra tags count as nothing filled', () async {
      final f = await makeFile('plain.mp3');
      await repo.addSong(title: 'P', artist: 'a', album: 'b', filePath: f);
      expect(await service.refreshTags(), 0);
    });
  });

  group('in the Library', () {
    late FakeMusicSource source;

    setUp(() {
      source = FakeMusicSource(songs: [song(1, 'Alpha Song')]);
      source.groupsByKind[GroupKind.genre] = const [
        RemoteGroup(name: 'Rock', songCount: 4),
        RemoteGroup(name: 'Jazz', songCount: 1),
      ];
      source.groupsByKind[GroupKind.year] = const [RemoteGroup(name: '2004', songCount: 2)];
      source.groupsByKind[GroupKind.albumArtist] = const [
        RemoteGroup(name: 'The Band', songCount: 9),
      ];
    });

    Future<void> openHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(source: source, homeList: true)));
      await settleUi(tester);
    }

    testWidgets('the list has Genres, Years and Album Artists', (tester) async {
      await openHome(tester);
      for (final c in ['Genres', 'Years', 'Album Artists']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
    });

    testWidgets('Genres lists them with counts, and opening one lists its songs',
        (tester) async {
      await openHome(tester);
      await tester.tap(find.text('Genres'));
      await settleUi(tester);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('4 songs'), findsOneWidget);
      expect(find.text('1 song'), findsOneWidget);
      await tester.tap(find.text('Rock'));
      await settleUi(tester);
      expect(find.text('Play all'), findsOneWidget, reason: 'opened like an album');
    });

    testWidgets('Years and Album Artists open the same way', (tester) async {
      await openHome(tester);
      await tester.tap(find.text('Years'));
      await settleUi(tester);
      expect(find.text('2004'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to the Library'));
      await settleUi(tester);
      await tester.tap(find.text('Album Artists'));
      await settleUi(tester);
      expect(find.text('The Band'), findsOneWidget);
    });

    testWidgets('with no tags yet it says how to get them', (tester) async {
      source.groupsByKind.clear();
      await openHome(tester);
      await tester.tap(find.text('Genres'));
      await settleUi(tester);
      expect(find.textContaining('Update tags from files'), findsOneWidget);
    });
  });
}
