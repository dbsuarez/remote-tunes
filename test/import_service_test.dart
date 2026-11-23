import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';

/// Returns canned metadata keyed by file name; can throw for chosen files.
class FakeExtractor implements MetadataExtractor {
  final Map<String, ExtractedMetadata> byName = {};
  final Set<String> throwFor = {};

  @override
  Future<ExtractedMetadata> extract(String path) async {
    final name = p.basename(path);
    if (throwFor.contains(name)) throw const FormatException('unreadable tags');
    return byName[name] ?? const ExtractedMetadata();
  }
}

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late FakeExtractor extractor;
  late Directory root;
  late Directory source; // where "picked" or "scanned" files live
  late Directory libraryDir;
  late Directory artDir;
  late LibraryImportService service;

  Future<String> makeFile(String relative, {int bytes = 64, Directory? in_}) async {
    final f = File(p.normalize(p.join((in_ ?? source).path, relative)));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(Uint8List.fromList(List.filled(bytes, 7)));
    return f.path;
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    extractor = FakeExtractor();
    root = await Directory.systemTemp.createTemp('rt_import_test_');
    source = await Directory(p.join(root.path, 'source')).create();
    libraryDir = Directory(p.join(root.path, 'library'));
    artDir = Directory(p.join(root.path, 'art'));
    service = LibraryImportService(
      library: repo,
      extractor: extractor,
      libraryDir: libraryDir,
      artDir: artDir,
    );
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  group('importFiles (copied into the library)', () {
    test('copies files, reads tags and falls back to the file name', () async {
      final tagged = await makeFile('tagged.mp3');
      final plain = await makeFile('My Plain Song.flac');
      extractor.byName['tagged.mp3'] = const ExtractedMetadata(
        title: 'Real Title',
        artist: 'Real Artist',
        album: 'Real Album',
        durationSeconds: 215,
        trackNumber: 4,
      );

      final r = await service.importFiles([tagged, plain]);
      expect(r.added, 2);
      expect(r.failed, 0);

      final songs = (await repo.songs()).items;
      final a = songs.firstWhere((s) => s.title == 'Real Title');
      expect(a.artist, 'Real Artist');
      expect(a.album, 'Real Album');
      expect(a.durationSeconds, 215);
      expect(a.trackNumber, 4);
      expect(a.mimeType, 'audio/mpeg');
      expect(a.fileSizeBytes, 64);

      final b = songs.firstWhere((s) => s.title == 'My Plain Song');
      expect(b.artist, unknownArtist);
      expect(b.album, unknownAlbum);
      expect(b.mimeType, 'audio/flac');

      // Stored under the library dir, not at the original location.
      for (final s in songs) {
        expect(p.isWithin(libraryDir.path, s.filePath!), isTrue);
        expect(await File(s.filePath!).exists(), isTrue);
      }
    });

    test('the copy survives when the original (cache) file is deleted', () async {
      final path = await makeFile('cached.mp3');
      await service.importFiles([path]);
      await File(path).delete();
      final song = (await repo.songs()).items.single;
      expect(await File(song.filePath!).exists(), isTrue);
    });

    test('importing the same file twice adds it once', () async {
      final path = await makeFile('dup.mp3');
      final first = await service.importFiles([path]);
      final second = await service.importFiles([path]);
      expect(first.added, 1);
      expect(second.added, 0);
      expect(second.duplicates, 1);
      expect(await repo.count(), 1);
      expect(libraryDir.listSync(), hasLength(1), reason: 'no extra copy');
    });

    test('unsupported, empty and missing files are reported; others still import',
        () async {
      final good = await makeFile('good.mp3');
      final txt = await makeFile('notes.txt');
      final empty = await makeFile('empty.mp3', bytes: 0);
      final missing = p.join(source.path, 'ghost.mp3');

      final r = await service.importFiles([txt, empty, missing, good]);
      expect(r.added, 1);
      expect(r.failed, 3);
      final reasons = {for (final f in r.failures) f.fileName: f.reason};
      expect(reasons['notes.txt'], contains('not a supported'));
      expect(reasons['empty.mp3'], contains('empty'));
      expect(reasons['ghost.mp3'], contains("Couldn't open"));
      expect(r.summary, 'Added 1 song · 3 skipped');
    });

    test('unreadable tags do not stop the import', () async {
      final path = await makeFile('weird.mp3');
      extractor.throwFor.add('weird.mp3');
      final r = await service.importFiles([path]);
      expect(r.added, 1);
      expect((await repo.songs()).items.single.title, 'weird');
    });

    test('reports progress for every file', () async {
      final a = await makeFile('a.mp3');
      final b = await makeFile('b.mp3');
      final seen = <String>[];
      await service.importFiles([a, b], onProgress: (pr) {
        seen.add('${pr.done}/${pr.total}');
      });
      expect(seen, ['0/2', '1/2', '2/2']);
    });
  });

  group('importFolder (referenced in place)', () {
    test('scans recursively, keeps original paths, ignores non-audio and hidden',
        () async {
      final a = await makeFile('top.mp3');
      final b = await makeFile('sub/deeper/inner.ogg');
      await makeFile('sub/cover.jpg');
      await makeFile('.hidden/secret.mp3');
      await makeFile('sub/.nomedia');

      final r = await service.importFolder(source.path);
      expect(r.added, 2);
      expect(r.failed, 0);

      final paths = (await repo.songs()).items.map((s) => s.filePath).toSet();
      expect(paths, {a, b});
      expect(libraryDir.existsSync(), isFalse, reason: 'nothing copied');
    });

    test('re-importing a folder adds nothing', () async {
      await makeFile('one.mp3');
      await makeFile('two.m4a');
      await service.importFolder(source.path);
      final again = await service.importFolder(source.path);
      expect(again.added, 0);
      expect(again.duplicates, 2);
      expect(await repo.count(), 2);
    });

    test('a folder with no audio reports "No songs found"', () async {
      await makeFile('readme.txt');
      final r = await service.importFolder(source.path);
      expect(r.added, 0);
      expect(r.summary, 'No songs found');
    });

    test('a missing folder is a clear error', () async {
      await expectLater(
        service.importFolder(p.join(root.path, 'nope')),
        throwsA(isA<ImportException>()),
      );
    });
  });

  group('album art', () {
    final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

    test('is saved once per album and shared by its songs', () async {
      final a = await makeFile('a.mp3');
      final b = await makeFile('b.mp3', bytes: 80);
      for (final n in ['a.mp3', 'b.mp3']) {
        extractor.byName[n] = ExtractedMetadata(
          title: n,
          artist: 'Band',
          album: 'Record',
          artBytes: png,
          artMimeType: 'image/png',
        );
      }
      await service.importFiles([a, b]);
      final songs = (await repo.songs()).items;
      expect(songs[0].albumArtPath, isNotNull);
      expect(songs[0].albumArtPath, songs[1].albumArtPath);
      expect(songs[0].albumArtPath, endsWith('.png'));
      expect(artDir.listSync(), hasLength(1));
      expect(await File(songs[0].albumArtPath!).readAsBytes(), png);
    });

    test('songs without art have none', () async {
      await service.importFiles([await makeFile('plain.mp3')]);
      expect((await repo.songs()).items.single.albumArtPath, isNull);
      expect(artDir.existsSync(), isFalse);
    });
  });

  group('removeSong', () {
    test('deletes the copied file, and art only when no song uses it', () async {
      final a = await makeFile('a.mp3');
      final b = await makeFile('b.mp3', bytes: 80);
      for (final n in ['a.mp3', 'b.mp3']) {
        extractor.byName[n] = ExtractedMetadata(
          title: n,
          artist: 'Band',
          album: 'Record',
          artBytes: Uint8List.fromList([1, 2, 3]),
          artMimeType: 'image/jpeg',
        );
      }
      await service.importFiles([a, b]);
      final songs = (await repo.songs()).items;
      final art = songs.first.albumArtPath!;

      await service.removeSong(songs[0].id);
      expect(await File(songs[0].filePath!).exists(), isFalse);
      expect(await File(art).exists(), isTrue, reason: 'still used by song 2');

      await service.removeSong(songs[1].id);
      expect(await File(art).exists(), isFalse);
      expect(await repo.count(), 0);
    });

    test('never deletes files that were only referenced in place', () async {
      final path = await makeFile('keep.mp3');
      await service.importFolder(source.path);
      final song = (await repo.songs()).items.single;
      await service.removeSong(song.id);
      expect(await File(path).exists(), isTrue);
      expect(await repo.count(), 0);
    });
  });
}
