import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/lookup_models.dart';
import 'package:remote_tunes/features/library/tag_writer.dart';
import 'package:remote_tunes/features/tagging/tag_cleanup.dart';
import 'package:remote_tunes/features/tagging/tag_cleanup_service.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';

class _Writer extends TagWriter {
  _Writer();
  final writes = <String>[];
  final groups = <String>[];
  TagWriteResult result = TagWriteResult.written;

  @override
  TagWriteResult write(String path, {required String title, required String artist, required String album, int? trackNumber}) {
    writes.add('$path|$title|$artist|$album|$trackNumber');
    return result;
  }

  @override
  TagWriteResult writeGroup(String path, Map<String, Object?> changes) {
    groups.add('$path|$changes');
    return result;
  }
}

class _Lookup implements SongLookupService {
  final answers = <String, List<LookupMatch>>{};
  final asked = <String>[];
  Object? failOn;

  @override
  Future<List<LookupMatch>> search({required String title, String artist = '', String album = '', int durationSeconds = 0}) async {
    asked.add(title);
    if (failOn == title) throw const LookupException('MusicBrainz is busy. Try again in a moment.');
    return answers[title] ?? const [];
  }

  @override
  Future<LookupCover?> coverFor(LookupMatch m) async => null;
  @override
  Future<RemoteLyrics> lyricsFor(int songId) async => const RemoteLyrics();
  @override
  Future<void> discardLyrics(int songId) async {}
  @override
  Future<int> applyCover(int songId, LookupCover cover) async => 0;
}

class _CoverLookup extends _Lookup {
  final coverAsks = <String>[];
  final applied = <int>[];
  bool fail = false;

  @override
  Future<LookupCover?> coverFor(LookupMatch m) async {
    coverAsks.add(m.releaseId!);
    if (fail) throw const LookupException('busy');
    return LookupCover(Uint8List.fromList(List.filled(200, 1)), 'jpg');
  }

  @override
  Future<int> applyCover(int songId, LookupCover cover) async {
    applied.add(songId);
    return 1;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('reading a file name', () {
    test('track, artist and title', () {
      final g = parseFileName('01 - Ann - Hello World')!;
      expect((g.track, g.artist, g.title), (1, 'Ann', 'Hello World'));
      final h = parseFileName('12. Bob - Another One')!;
      expect((h.track, h.artist, h.title), (12, 'Bob', 'Another One'));
    });

    test('track and title only', () {
      final g = parseFileName('03. Just a Title')!;
      expect((g.track, g.artist, g.title), (3, null, 'Just a Title'));
      expect(parseFileName('7) Seven')!.track, 7);
      expect(parseFileName('01_-_Under_Scores')!.title, 'Under Scores');
    });

    test('artist and title only', () {
      final g = parseFileName('3 Doors Down - Here Without You')!;
      expect(g.artist, '3 Doors Down', reason: 'a number then a space is not a track number');
      expect(g.title, 'Here Without You');
      expect(g.track, isNull);
    });

    test('a plain name teaches nothing', () {
      expect(parseFileName('Kryptonite'), isNull);
      expect(parseFileName('21 Guns'), isNull, reason: 'no separator: not a track number');
      expect(parseFileName('   '), isNull);
    });

    test('names are compared loosely', () {
      expect(sameName('Hello, World!', 'hello world'), isTrue);
      expect(sameName('A', 'B'), isFalse);
      expect(sameName('', ''), isFalse);
    });
  });

  group('the service', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late _Writer writer;
    late TagCleanupService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      writer = _Writer();
      service = TagCleanupService(db: db, library: repo, writer: writer);
    });
    tearDown(() => db.close());

    Future<int> add(String title, String path, {String artist = 'Unknown artist', String album = 'Unknown album', int dur = 200, int? track}) async {
      final id = await repo.addSong(title: title, artist: artist, album: album, filePath: path, durationSeconds: dur);
      if (track != null) await db.customUpdate('UPDATE songs SET track_number = $track WHERE id = $id', updates: {db.songs});
      return id;
    }

    Future<Map<String, Object?>> row(int id) async =>
        (await db.customSelect('SELECT title, artist, album, year, track_number FROM songs WHERE id = ?', variables: [Variable<int>(id)]).getSingle()).data;

    group('the report', () {
      test('counts what is missing, music only', () async {
        await add('Complete', '/m/a.mp3', artist: 'Ann', album: 'First');
        await add('NoArtist', '/m/b.mp3', album: 'First');
        await add('NoAlbum', '/m/c.mp3', artist: 'Ann');
        final book = await add('Book', '/m/d.mp3');
        await repo.setAudiobook([book], true);
        final r = await service.report();
        expect(r.songs, 3, reason: 'the audiobook is not counted');
        expect(r.complete, 1);
        expect(r.noArtist, 1);
        expect(r.noAlbum, 1);
        expect(r.noYear, 3);
        expect(r.noGenre, 3);
        expect(r.noCover, 3);
        expect(r.lastBatch, isNull);
      });

      test('a song is complete once artist and album are known', () async {
        await add('X', '/m/x.mp3', artist: 'Ann', album: 'First');
        expect((await service.report()).complete, 1);
      });
    });

    group('from file names', () {
      test('a title that is only the file name, and an unknown artist, are filled in', () async {
        final id = await add('01 - Ann - Hello World', '/m/01 - Ann - Hello World.mp3');
        final c = (await service.fileNameChanges()).single;
        expect(c.songId, id);
        expect(c.title, 'Hello World');
        expect(c.artist, 'Ann');
        expect(c.track, 1);
        expect(c.album, isNull);
        expect(c.lines, contains('artist: Unknown artist → Ann'));
      });

      test('a good tag is never replaced', () async {
        await add('Real Title', '/m/01 - Ann - Other Name.mp3', artist: 'Real Artist', album: 'X');
        final c = await service.fileNameChanges();
        expect(c.single.title, isNull, reason: 'the title tag says something else');
        expect(c.single.artist, isNull);
        expect(c.single.track, 1, reason: 'only the empty track number is filled');
      });

      test('the artist is trusted only when the title agrees with the file name', () async {
        await add('Different', '/m/Ann - Hello.mp3');
        expect(await service.fileNameChanges(), isEmpty);
        await add('Hello', '/m/Ann - Hello.mp3');
        final c = await service.fileNameChanges();
        expect(c.single.artist, 'Ann');
      });

      test('nothing to learn, nothing proposed; audiobooks are left alone', () async {
        await add('Kryptonite', '/m/Kryptonite.mp3');
        final book = await add('02 - Chapter', '/m/02 - Chapter.mp3');
        await repo.setAudiobook([book], true);
        expect(await service.fileNameChanges(), isEmpty);
      });

      test('the report counts them', () async {
        await add('01 - Ann - A', '/m/01 - Ann - A.mp3');
        await add('02 - Ann - B', '/m/02 - Ann - B.mp3');
        expect((await service.report()).fromFileNames, 2);
      });
    });

    group('applying and undoing', () {
      test('changes the library, logs the old values, and fills only what was proposed', () async {
        final id = await add('01 - Ann - Hello', '/m/01 - Ann - Hello.mp3', album: 'Kept Album');
        final result = await service.apply(await service.fileNameChanges());
        expect(result.applied, 1);
        expect(result.batchId, 1);
        final r = await row(id);
        expect((r['title'], r['artist'], r['album'], r['track_number']), ('Hello', 'Ann', 'Kept Album', 1));
        expect((await service.report()).lastBatch!.songs, 1);
      });

      test('with write-to-file the music file is written too, with the new values', () async {
        await add('01 - Ann - Hello', '/m/01 - Ann - Hello.mp3');
        final result = await service.apply(await service.fileNameChanges(), writeToFile: true);
        expect(result.written, 1);
        expect(writer.writes.single, '/m/01 - Ann - Hello.mp3|Hello|Ann|Unknown album|1');
      });

      test('a file Android will not let us change is counted, the library still changes', () async {
        final id = await add('01 - Ann - Hello', '/m/01 - Ann - Hello.mp3');
        writer.result = TagWriteResult.notAllowed;
        final result = await service.apply(await service.fileNameChanges(), writeToFile: true);
        expect((result.applied, result.written, result.notAllowed), (1, 0, 1));
        expect((await row(id))['title'], 'Hello');
      });

      test('undo puts the last batch back, in the library and in the files that were changed', () async {
        final id = await add('01 - Ann - Hello', '/m/01 - Ann - Hello.mp3');
        await service.apply(await service.fileNameChanges(), writeToFile: true);
        writer.writes.clear();
        final undone = await service.undoLast();
        expect(undone!.applied, 1);
        final r = await row(id);
        expect((r['title'], r['artist'], r['track_number']), ('01 - Ann - Hello', 'Unknown artist', null));
        expect(writer.writes, hasLength(1), reason: 'the file is put back too');
        expect((await service.report()).lastBatch, isNull);
        expect(await service.undoLast(), isNull, reason: 'nothing more to undo');
      });

      test('only the newest batch is undone', () async {
        await add('01 - Ann - A', '/m/01 - Ann - A.mp3');
        await service.apply(await service.fileNameChanges());
        final b = await add('02 - Bob - B', '/m/02 - Bob - B.mp3');
        final second = await service.apply(await service.fileNameChanges());
        expect(second.batchId, 2);
        await service.undoLast();
        expect((await row(b))['artist'], 'Unknown artist');
        expect((await service.report()).lastBatch!.id, 1, reason: 'the first batch is still there');
      });

      test('a year is applied and undone', () async {
        final id = await add('Song', '/m/s.mp3', artist: 'Ann');
        await service.apply([TagChange(songId: id, label: 'Song', source: 'musicbrainz', year: 1999)]);
        expect((await row(id))['year'], 1999);
        await service.undoLast();
        expect((await row(id))['year'], isNull);
      });

      test('an empty change does nothing', () async {
        final id = await add('Song', '/m/s.mp3');
        final r = await service.apply([TagChange(songId: id, label: 'Song', source: 'filename')]);
        expect(r.batchId, 0);
      });
    });

    group('suggestions from MusicBrainz', () {
      late _Lookup lookup;
      setUp(() => lookup = _Lookup());

      test('a sure match is flagged; only empty fields are proposed', () async {
        final id = await add('Hello', '/m/h.mp3', artist: 'Ann', dur: 200);
        lookup.answers['Hello'] = [
          const LookupMatch(title: 'Hello', artist: 'Ann', album: 'First', year: 1999, trackNumber: 4, score: 100, lengthSeconds: 201),
        ];
        expect(await service.findSuggestions(lookup), 1);
        final s = (await service.suggestionChanges()).single;
        expect(s.songId, id);
        expect(s.album, 'First');
        expect(s.year, 1999);
        expect(s.track, 4);
        expect(s.artist, isNull, reason: 'the artist was known');
        expect(s.high, isTrue);
      });

      test('a different length or title is not a sure match', () async {
        await add('Hello', '/m/h.mp3', artist: 'Ann', dur: 200);
        await add('World', '/m/w.mp3', artist: 'Ann', dur: 200);
        lookup.answers['Hello'] = [const LookupMatch(title: 'Hello', artist: 'Ann', album: 'A', year: 2000, score: 100, lengthSeconds: 300)];
        lookup.answers['World'] = [const LookupMatch(title: 'World (Remix)', artist: 'Ann', album: 'B', year: 2001, score: 100, lengthSeconds: 200)];
        await service.findSuggestions(lookup);
        final list = await service.suggestionChanges();
        expect(list, hasLength(2));
        expect(list.every((c) => !c.high), isTrue);
      });

      test('no answer is remembered as no match, and is not asked again', () async {
        await add('Obscure', '/m/o.mp3');
        await service.findSuggestions(lookup);
        expect(await service.suggestionChanges(), isEmpty);
        expect((await service.report()).noMatch, 1);
        lookup.asked.clear();
        expect(await service.findSuggestions(lookup), 0);
        expect(lookup.asked, isEmpty);
      });

      test('only songs that lack an album or a year are asked about; audiobooks never', () async {
        await add('Complete', '/m/c.mp3', artist: 'Ann', album: 'First');
        await db.customUpdate("UPDATE songs SET year = 2000, genre = 'Rock'", updates: {db.songs});
        final book = await add('Book', '/m/b.mp3');
        await repo.setAudiobook([book], true);
        await add('Needs', '/m/n.mp3', artist: 'Ann');
        await service.findSuggestions(lookup);
        expect(lookup.asked, ['Needs']);
      });

      test('it can be stopped and carried on', () async {
        for (final t in ['A', 'B', 'C']) {
          await add(t, '/m/$t.mp3');
        }
        var count = 0;
        await service.findSuggestions(lookup, cancelled: () => count++ >= 2);
        expect(lookup.asked, ['A', 'B']);
        lookup.asked.clear();
        await service.findSuggestions(lookup);
        expect(lookup.asked, ['C'], reason: 'the first two are not asked again');
      });

      test('a busy MusicBrainz stops it, keeping what was found', () async {
        await add('A', '/m/A.mp3');
        await add('B', '/m/B.mp3');
        lookup.answers['A'] = [const LookupMatch(title: 'A', artist: 'X', album: 'Al', score: 100)];
        lookup.failOn = 'B';
        await expectLater(service.findSuggestions(lookup), throwsA(isA<LookupException>()));
        expect((await service.suggestionChanges()).single.label, 'A');
      });

      test('applying a suggestion marks it done, and undo offers it again; skipped ones stay away', () async {
        final a = await add('A', '/m/A.mp3');
        final b = await add('B', '/m/B.mp3');
        lookup.answers['A'] = [const LookupMatch(title: 'A', artist: 'X', album: 'Al', year: 2001, score: 100)];
        lookup.answers['B'] = [const LookupMatch(title: 'B', artist: 'Y', album: 'Bl', score: 100)];
        await service.findSuggestions(lookup);
        final all = await service.suggestionChanges();
        await service.apply([all.firstWhere((c) => c.songId == a)]);
        await service.markSuggestions([b], 'skipped');
        expect(await service.suggestionChanges(), isEmpty);
        expect((await row(a))['album'], 'Al');
        await service.undoLast();
        expect((await service.suggestionChanges()).map((c) => c.songId), [a]);
        expect((await row(a))['album'], 'Unknown album');
      });

      test('the artist is filled when it was unknown', () async {
        await add('A', '/m/A.mp3');
        lookup.answers['A'] = [const LookupMatch(title: 'A', artist: 'Real Artist', album: 'Al', score: 100)];
        await service.findSuggestions(lookup);
        expect((await service.suggestionChanges()).single.artist, 'Real Artist');
      });

      test('a genre is suggested for a song without one, and never over one that is there', () async {
        final a = await add('A', '/m/A.mp3', artist: 'Ann', album: 'First');
        final b = await add('B', '/m/B.mp3', artist: 'Ann', album: 'First');
        await db.customUpdate("UPDATE songs SET year = 2000, genre = 'Jazz' WHERE id = $b", updates: {db.songs});
        await db.customUpdate('UPDATE songs SET year = 2000 WHERE id = $a', updates: {db.songs});
        lookup.answers['A'] = [const LookupMatch(title: 'A', artist: 'Ann', album: 'First', score: 100, genre: 'Rock')];
        lookup.answers['B'] = [const LookupMatch(title: 'B', artist: 'Ann', album: 'First', score: 100, genre: 'Pop')];
        await service.findSuggestions(lookup);
        expect(lookup.asked, ['A'], reason: 'B is complete, genre included');
        final s = (await service.suggestionChanges()).single;
        expect((s.songId, s.genre), (a, 'Rock'));
        expect(s.lines, ['genre: (empty) → Rock']);
        await service.apply([s]);
        expect((await db.customSelect('SELECT genre FROM songs WHERE id = $a').getSingle()).read<String>('genre'), 'Rock');
        await service.undoLast();
        expect((await db.customSelect('SELECT genre FROM songs WHERE id = $a').getSingle()).readNullable<String>('genre'), isNull);
      });

      test('the genre goes into the file too', () async {
        final a = await add('A', '/m/A.mp3', artist: 'Ann', album: 'First');
        await service.apply([TagChange(songId: a, label: 'A', source: 'musicbrainz', genre: 'Rock')], writeToFile: true);
        expect(writer.groups.single, '/m/A.mp3|{genre: Rock}');
      });

      test('songs asked about before genres were looked for are asked again, once', () async {
        final a = await add('A', '/m/A.mp3', artist: 'Ann', album: 'First');
        await db.customUpdate('UPDATE songs SET year = 2000 WHERE id = $a', updates: {db.songs});
        // An older search: asked, nothing found, genres not looked at.
        await db.customInsert("INSERT INTO tag_suggestions (song_id, status, asked_genre) VALUES ($a, 'nomatch', 0)");
        lookup.answers['A'] = [const LookupMatch(title: 'A', artist: 'Ann', album: 'First', score: 100, genre: 'Rock')];
        await service.findSuggestions(lookup);
        expect(lookup.asked, ['A']);
        expect((await service.suggestionChanges()).single.genre, 'Rock');
        lookup.asked.clear();
        await service.findSuggestions(lookup);
        expect(lookup.asked, isEmpty, reason: 'asked_genre is now 1');
      });

      test('a song set aside is not asked again for its genre', () async {
        final a = await add('A', '/m/A.mp3', artist: 'Ann', album: 'First');
        await db.customUpdate('UPDATE songs SET year = 2000 WHERE id = $a', updates: {db.songs});
        await db.customInsert("INSERT INTO tag_suggestions (song_id, status, asked_genre) VALUES ($a, 'skipped', 0)");
        await service.findSuggestions(lookup);
        expect(lookup.asked, isEmpty);
      });

      test('covers: one download per release, only for albums without a picture', () async {
        final a = await add('A', '/m/A.mp3', artist: 'Ann', album: 'First');
        final b = await add('B', '/m/B.mp3', artist: 'Ann', album: 'First');
        final c = await add('C', '/m/C.mp3', artist: 'Bob', album: 'Second');
        await db.customUpdate("UPDATE songs SET album_art_path = '/art/x.jpg' WHERE id = $c", updates: {db.songs});
        TagChange ch(int id, String rel) => TagChange(songId: id, label: 'S$id', source: 'musicbrainz', year: 2000, releaseId: rel);
        final covers = _CoverLookup();
        final r = await service.apply([ch(a, 'rel-1'), ch(b, 'rel-1'), ch(c, 'rel-2')], coverLookup: covers);
        expect(r.covers, 1);
        expect(covers.coverAsks, ['rel-1'], reason: 'rel-2 already has a picture; rel-1 only once');
        expect(covers.applied, [a]);
      });

      test('no cover lookup, no downloads; a busy archive stops the covers but not the changes', () async {
        final a = await add('A', '/m/A.mp3', artist: 'Ann', album: 'First');
        final change = TagChange(songId: a, label: 'S', source: 'musicbrainz', year: 2000, releaseId: 'rel-1');
        final none = await service.apply([change]);
        expect(none.covers, 0);
        await service.undoLast();
        final busy = _CoverLookup()..fail = true;
        final r = await service.apply([change], coverLookup: busy);
        expect((r.applied, r.covers), (1, 0));
      });

      test('clearing forgets what was found', () async {
        await add('A', '/m/A.mp3');
        await service.findSuggestions(lookup);
        expect(await service.clearSuggestions(), 1);
        lookup.asked.clear();
        await service.findSuggestions(lookup);
        expect(lookup.asked, ['A']);
      });
    });
  });
}
