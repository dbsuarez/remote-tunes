import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';

/// Answers with the tags it was given for a file (what the file itself says).
class _Tags implements MetadataExtractor {
  final byName = <String, ExtractedMetadata>{};
  final failing = <String>{};

  @override
  Future<ExtractedMetadata> extract(String path) async {
    final name = p.basename(path);
    if (failing.contains(name)) throw StateError('unreadable');
    return byName[name] ?? const ExtractedMetadata();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;
  late Directory root;
  late _Tags tags;
  late LibraryImportService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    root = await Directory.systemTemp.createTemp('oldedits');
    tags = _Tags();
    service = LibraryImportService(
      library: repo,
      extractor: tags,
      libraryDir: Directory(p.join(root.path, 'library')),
      artDir: Directory(p.join(root.path, 'art')),
      exclusions: MemoryExclusionStore(),
      folders: MemoryMusicFoldersStore(),
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<int> add(String file, String title, {String artist = 'Unknown artist', String album = 'Unknown album', int? track, bool makeFile = true}) async {
    final path = p.join(root.path, file);
    if (makeFile) File(path).writeAsBytesSync([1, 2, 3]);
    final id = await repo.addSong(title: title, artist: artist, album: album, filePath: path, durationSeconds: 100);
    if (track != null) await db.customUpdate('UPDATE songs SET track_number = $track WHERE id = $id', updates: {db.songs});
    return id;
  }

  Future<bool> edited(int id) async =>
      (await db.customSelect('SELECT info_edited AS e FROM songs WHERE id = $id').getSingle()).read<bool>('e');

  test('a title changed in the library only is found', () async {
    final id = await add('a.mp3', 'My Better Title', artist: 'Ann', album: 'First');
    tags.byName['a.mp3'] = const ExtractedMetadata(title: 'Old Tag Title', artist: 'Ann', album: 'First');
    expect(await service.findEditedSongs(), 1);
    expect(await edited(id), isTrue);
  });

  test('a song that matches its file is not flagged, whatever the capitals or punctuation', () async {
    final id = await add('a.mp3', 'Hello, World!', artist: 'Ann', album: 'First', track: 3);
    tags.byName['a.mp3'] = const ExtractedMetadata(title: 'hello world', artist: 'ANN', album: 'First', trackNumber: 3);
    expect(await service.findEditedSongs(), 0);
    expect(await edited(id), isFalse);
  });

  test('an artist or album the library has but the file does not is an edit; unknown is not', () async {
    final a = await add('a.mp3', 'A', artist: 'Ann');
    final b = await add('b.mp3', 'B');
    final c = await add('c.mp3', 'C', album: 'Chosen Album');
    tags.byName['a.mp3'] = const ExtractedMetadata(title: 'A');
    tags.byName['b.mp3'] = const ExtractedMetadata(title: 'B');
    tags.byName['c.mp3'] = const ExtractedMetadata(title: 'C');
    expect(await service.findEditedSongs(), 2);
    expect(await edited(a), isTrue);
    expect(await edited(b), isFalse, reason: 'nothing known on either side');
    expect(await edited(c), isTrue);
  });

  test('a file with no title tag: the file name is the title, so only a different title is an edit', () async {
    final same = await add('Plain Name.mp3', 'Plain Name');
    final changed = await add('other.mp3', 'Renamed By Hand');
    expect(await service.findEditedSongs(), 1);
    expect(await edited(same), isFalse);
    expect(await edited(changed), isTrue);
  });

  test('a track number changed, or added where the file has none', () async {
    final a = await add('a.mp3', 'A', track: 5);
    final b = await add('b.mp3', 'B', track: 2);
    tags.byName['a.mp3'] = const ExtractedMetadata(title: 'A', trackNumber: 7);
    tags.byName['b.mp3'] = const ExtractedMetadata(title: 'B');
    expect(await service.findEditedSongs(), 2);
    expect(await edited(a), isTrue);
    expect(await edited(b), isTrue);
  });

  test('songs already flagged, missing files and unreadable files are left alone', () async {
    final flagged = await add('f.mp3', 'Flagged Title', artist: 'Ann');
    await repo.markInfoEdited([flagged]);
    final gone = await add('gone.mp3', 'Gone', artist: 'Ann', makeFile: false);
    final bad = await add('bad.mp3', 'Bad', artist: 'Ann');
    tags.failing.add('bad.mp3');
    tags.byName['f.mp3'] = const ExtractedMetadata(title: 'Other');
    expect(await service.findEditedSongs(), 0);
    expect(await edited(gone), isFalse);
    expect(await edited(bad), isFalse);
  });

  test('it only flags: nothing in the library changes, and running it again finds nothing new', () async {
    final id = await add('a.mp3', 'Mine', artist: 'Ann', album: 'First');
    tags.byName['a.mp3'] = const ExtractedMetadata(title: 'Theirs', artist: 'Ann', album: 'First');
    await service.findEditedSongs();
    final r = await db.customSelect('SELECT title, artist, album FROM songs WHERE id = $id').getSingle();
    expect((r.read<String>('title'), r.read<String>('artist'), r.read<String>('album')), ('Mine', 'Ann', 'First'));
    expect(await service.findEditedSongs(), 0, reason: 'already flagged');
  });

  test('reports its progress', () async {
    await add('a.mp3', 'A');
    await add('b.mp3', 'B');
    final seen = <int>[];
    await service.findEditedSongs(onProgress: (pr) => seen.add(pr.done));
    expect(seen.first, 0);
    expect(seen.last, 2);
  });
}
