import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/backup/backup_models.dart';
import 'package:remote_tunes/features/backup/backup_service.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/features/library/song_lookup.dart';
import 'package:remote_tunes/features/player/lyrics_service.dart';

import 'cloud_test.dart' show FakeR2, song;
import 'import_service_test.dart' show FakeExtractor;

/// Songs with no album tag are all stored as "Unknown album". That is not an album: they must never
/// take each other's cover.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;
  late FakeExtractor extractor;
  late Directory root;
  late Directory artDir;
  late LibraryImportService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    extractor = FakeExtractor();
    root = await Directory.systemTemp.createTemp('rt_borrowed_');
    artDir = Directory(p.join(root.path, 'art'));
    service = LibraryImportService(
      library: repo,
      extractor: extractor,
      libraryDir: Directory(p.join(root.path, 'library')),
      artDir: artDir,
    );
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  var size = 10;
  Future<String> file(String name) async {
    final f = File(p.join(root.path, 'source', name));
    await f.parent.create(recursive: true);
    // A different size each time, so no two files look like the same song.
    await f.writeAsBytes(List.filled(++size, 7));
    return f.path;
  }

  ExtractedMetadata tags({String? artist, String? album, List<int>? art}) =>
      ExtractedMetadata(artist: artist, album: album, artBytes: art == null ? null : Uint8List.fromList(art), artMimeType: 'image/jpeg');

  /// The cover bytes of every song, by title (null: no cover).
  Future<Map<String, List<int>?>> covers() async {
    final rows = await db.customSelect('SELECT title, album_art_path AS a FROM songs').get();
    return {
      for (final r in rows)
        r.read<String>('title'): r.readNullable<String>('a') == null ? null : File(r.read<String>('a')).readAsBytesSync(),
    };
  }

  Future<int> idOf(String title) async =>
      (await db.customSelect('SELECT id FROM songs WHERE title = ?', variables: [Variable<String>(title)]).getSingle()).read<int>('id');

  /// Gives songs a picture file directly, the way the old code left them.
  Future<String> borrow(List<String> titles, List<int> bytes) async {
    await artDir.create(recursive: true);
    final path = p.join(artDir.path, 'shared_${bytes.first}.jpg');
    await File(path).writeAsBytes(bytes);
    for (final t in titles) {
      await db.customUpdate('UPDATE songs SET album_art_path = ? WHERE title = ?',
          variables: [Variable<String>(path), Variable<String>(t)], updates: {db.songs});
    }
    return path;
  }

  group('adding songs', () {
    test('songs with no album keep their own cover, and one without a cover gets none', () async {
      extractor.byName['one.mp3'] = tags(art: [1, 1]);
      extractor.byName['two.mp3'] = tags(art: [2, 2]);
      extractor.byName['bare.mp3'] = tags();
      await service.importFiles([await file('one.mp3'), await file('two.mp3'), await file('bare.mp3')]);
      expect(await covers(), {
        'one': [1, 1],
        'two': [2, 2],
        'bare': null,
      });
    });

    test('songs of a real album still share one picture', () async {
      extractor.byName['one.mp3'] = tags(artist: 'Ann', album: 'First', art: [1, 1]);
      extractor.byName['two.mp3'] = tags(artist: 'Ann', album: 'First', art: [2, 2]);
      await service.importFiles([await file('one.mp3'), await file('two.mp3')]);
      expect(await covers(), {
        'one': [1, 1],
        'two': [1, 1],
      });
    });
  });

  group('a cover chosen with Look up', () {
    SongLookup lookup() => SongLookup(db: db, lyrics: LyricsService(library: repo, db: db), artDir: () async => artDir);
    LookupCover cover(List<int> bytes) => LookupCover(Uint8List.fromList(bytes), 'jpg');

    test('goes only to that song when it has no album', () async {
      await service.importFiles([await file('one.mp3'), await file('two.mp3')]);
      expect(await lookup().applyCover(await idOf('one'), cover([9])), 1);
      expect(await covers(), {
        'one': [9],
        'two': null,
      });
    });

    test('goes to the whole album when there is one', () async {
      extractor.byName['one.mp3'] = tags(artist: 'Ann', album: 'First');
      extractor.byName['two.mp3'] = tags(artist: 'Ann', album: 'First');
      await service.importFiles([await file('one.mp3'), await file('two.mp3')]);
      expect(await lookup().applyCover(await idOf('one'), cover([9])), 2);
    });
  });

  group('backups', () {
    BackupService backup(AppDatabase d) => BackupService(
          db: d,
          settings: SettingsRepository(d),
          exclusions: MemoryExclusionStore(),
          copiedSongsDir: '/app/library',
          artDir: artDir.path,
        );

    test('carry no cover for "Unknown album"', () async {
      await service.importFiles([await file('one.mp3')]);
      await borrow(['one'], [5]);
      final data = await backup(db).create(art: true);
      expect(data.art, isEmpty);
      expect((await backup(db).artSummary()).count, 0);
    });

    test('an older backup that has one gives it to nobody', () async {
      await service.importFiles([await file('one.mp3'), await file('two.mp3')]);
      final old = await backup(db).create(art: true);
      final data = BackupData(
        created: old.created,
        art: [
          BackupArt(artist: unknownArtist, album: unknownAlbum, bytes: Uint8List.fromList([5]), ext: 'jpg'),
        ],
      );
      final report = await backup(db).restore(data);
      expect(report.artRestored, 0);
      expect(await covers(), {'one': null, 'two': null});
    });
  });

  group('repairing covers already borrowed', () {
    test('each song gets its own cover back, or none; real albums are left alone', () async {
      extractor.byName['own.mp3'] = tags(art: [2, 2]);
      extractor.byName['lender.mp3'] = tags(art: [1, 1]);
      extractor.byName['bare.mp3'] = tags();
      extractor.byName['a.mp3'] = tags(artist: 'Ann', album: 'First');
      extractor.byName['b.mp3'] = tags(artist: 'Ann', album: 'First');
      // Added as a folder: the files stay where they are, so their tags can be read again.
      for (final name in ['own.mp3', 'lender.mp3', 'bare.mp3', 'a.mp3']) {
        await file(name);
      }
      await service.importFolder(p.dirname(await file('b.mp3')));
      await borrow(['own', 'lender', 'bare'], [1, 1]);
      await borrow(['a', 'b'], [3]);

      expect(await service.repairBorrowedArt(), 2);
      expect(await covers(), {
        'own': [2, 2],
        'lender': [1, 1],
        'bare': null,
        'a': [3],
        'b': [3],
      });
      expect(await service.repairBorrowedArt(), 0, reason: 'nothing left to repair');
    });

    test('a picture nobody uses any more is deleted', () async {
      await service.importFiles([await file('one.mp3'), await file('two.mp3')]);
      final shared = await borrow(['one', 'two'], [4]);
      expect(await service.repairBorrowedArt(), 2);
      expect(File(shared).existsSync(), isFalse);
    });

    test('a picture only one song has is kept (it may have been chosen by hand)', () async {
      await service.importFiles([await file('one.mp3')]);
      await borrow(['one'], [4]);
      expect(await service.repairBorrowedArt(), 0);
      expect((await covers())['one'], [4]);
    });

    test('a song whose file cannot be read is left as it is', () async {
      final gone = await file('gone.mp3');
      await service.importFolder(p.dirname(gone));
      await service.importFiles([await file('two.mp3')]);
      await borrow(['gone', 'two'], [4]);
      await File(gone).delete();
      expect(await service.repairBorrowedArt(), 1);
      expect(await covers(), {
        'gone': [4],
        'two': null,
      });
    });
  });

  group('uploading to the cloud', () {
    test('songs with no album each get their own cover file', () async {
      final r2 = FakeR2();
      var n = 0;
      await r2.service(ids: () => 'id${++n}').upload([
        song('One', album: unknownAlbum, art: Uint8List.fromList([1])),
        song('Two', album: unknownAlbum, art: Uint8List.fromList([2])),
        song('Three', album: '', art: Uint8List.fromList([3])),
      ]);
      final keys = r2.catalog.songs.map((s) => s.artKey!).toList();
      expect(keys.toSet(), hasLength(3));
      expect([for (final k in keys) r2.files[k]], [
        [1],
        [2],
        [3],
      ]);
    });
  });
}
