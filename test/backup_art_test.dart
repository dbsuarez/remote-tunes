import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/backup/backup_models.dart';
import 'package:remote_tunes/features/backup/backup_service.dart';
import 'package:remote_tunes/features/library/import_service.dart';

class _Phone {
  _Phone(this.artDir) {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepository(db);
    out = MemoryExclusionStore();
    service = BackupService(
      db: db,
      settings: SettingsRepository(db),
      exclusions: out,
      copiedSongsDir: '/data/user/0/app/files/library',
      artDir: artDir,
    );
  }

  final String artDir;
  late final AppDatabase db;
  late final LibraryRepository library;
  late final MemoryExclusionStore out;
  late final BackupService service;

  Future<void> song(String title, String artist, String album, String path) => library.addSong(
      title: title, artist: artist, album: album, filePath: path, durationSeconds: 200);

  Future<void> giveArt(String title, String path) => db.customUpdate(
        'UPDATE songs SET album_art_path = ? WHERE title = ?',
        variables: [Variable<String>(path)] + [Variable<String>(title)],
        updates: {db.songs},
      );

  Future<void> close() => db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late _Phone old;
  late _Phone fresh;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('bkart');
    old = _Phone('${dir.path}/oldart');
    fresh = _Phone('${dir.path}/newart');
    await old.song('Alpha', 'Ann', 'First', '/old/Music/Rock/alpha.mp3');
    await old.song('Bravo', 'Bob', 'Second', '/old/Music/Rock/bravo.mp3');
    await old.song('Charlie', 'Cy', 'Third', '/old/Music/Jazz/charlie.mp3');
    await old.song('Delta', 'Di', 'Fourth', '/old/Music/Jazz/delta.mp3');
  });

  tearDown(() async {
    await old.close();
    await fresh.close();
    dir.deleteSync(recursive: true);
  });

  /// A picture file on the old phone.
  String cover(String name, List<int> bytes) {
    final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  group('album art', () {
    test('covers come along, one per album, with their size known beforehand', () async {
      final a = cover('a.jpg', List.filled(100, 1));
      final c = cover('c.png', List.filled(300, 3));
      await old.giveArt('Alpha', a);
      await old.giveArt('Bravo', a);
      await old.giveArt('Charlie', c);
      final summary = await old.service.artSummary();
      expect(summary.count, 2);
      expect(summary.bytes, 400);
      final data = await old.service.create(art: true);
      expect(data.art.map((x) => '${x.artist}|${x.album}|${x.ext}').toSet(),
          {'Ann|First|jpg', 'Bob|Second|jpg', 'Cy|Third|png'});
      expect((await old.service.create()).art, isEmpty, reason: 'off unless asked for');
    });

    test('they survive the file and land on the right albums of the new phone', () async {
      await old.giveArt('Alpha', cover('a.jpg', [1, 2, 3, 4]));
      final data = BackupData.decode((await old.service.create(art: true)).encode());
      expect(data.art.single.bytes, [1, 2, 3, 4]);
      await fresh.song('Alpha', 'Ann', 'First', '/new/a.mp3');
      await fresh.song('Alpha 2', 'Ann', 'First', '/new/b.mp3');
      await fresh.song('Other', 'Zed', 'Z', '/new/z.mp3');
      final r = await fresh.service.restore(data, newRoot: '/new');
      expect(r.artRestored, 1);
      final rows =
          await fresh.db.customSelect('SELECT title, album_art_path AS p FROM songs').get();
      final by = {for (final x in rows) x.read<String>('title'): x.readNullable<String>('p')};
      expect(by['Alpha'], isNotNull);
      expect(by['Alpha 2'], by['Alpha'], reason: 'the whole album gets it');
      expect(by['Other'], isNull, reason: 'another album is untouched');
      expect(File(by['Alpha']!).readAsBytesSync(), [1, 2, 3, 4]);
      expect(by['Alpha'], startsWith(fresh.artDir));
    });

    test('a picture this phone already has is never replaced', () async {
      await old.giveArt('Alpha', cover('a.jpg', [9, 9]));
      final data = await old.service.create(art: true);
      await fresh.song('Alpha', 'Ann', 'First', '/new/a.mp3');
      final mine = cover('mine.jpg', [5, 5, 5]);
      await fresh.giveArt('Alpha', mine);
      final r = await fresh.service.restore(data, newRoot: '/new');
      expect(r.artRestored, 0);
      final p = (await fresh.db.customSelect('SELECT album_art_path AS p FROM songs').getSingle())
          .read<String>('p');
      expect(p, mine);
    });

    test('a picture whose file is gone counts as missing and is filled in', () async {
      await old.giveArt('Alpha', cover('a.jpg', [9, 9]));
      final data = await old.service.create(art: true);
      await fresh.song('Alpha', 'Ann', 'First', '/new/a.mp3');
      await fresh.giveArt('Alpha', '${dir.path}/deleted.jpg');
      final r = await fresh.service.restore(data, newRoot: '/new');
      expect(r.artRestored, 1);
    });

    test('an album that is not on this phone is counted, not made up', () async {
      await old.giveArt('Alpha', cover('a.jpg', [1]));
      final data = await old.service.create(art: true);
      final r = await fresh.service.restore(data);
      expect(r.artRestored, 0);
      expect(r.artSkipped, 1);
    });

    test('covers can be switched off when restoring', () async {
      await old.giveArt('Alpha', cover('a.jpg', [1]));
      final data = await old.service.create(art: true);
      await fresh.song('Alpha', 'Ann', 'First', '/new/a.mp3');
      final r = await fresh.service.restore(data, newRoot: '/new', includeArt: false);
      expect(r.artRestored, 0);
      expect(Directory(fresh.artDir).existsSync(), isFalse);
    });

    test('a cover that is gone from the old phone is just left out', () async {
      await old.giveArt('Alpha', '${dir.path}/never-there.jpg');
      final data = await old.service.create(art: true);
      expect(data.art, isEmpty);
    });
  });

  group('edited song info', () {
    test('Edit info is remembered, and travels to the same file on the new phone', () async {
      final id =
          (await old.db.customSelect("SELECT id FROM songs WHERE title = 'Delta'").getSingle())
              .read<int>('id');
      expect(
          await old.library.updateSongInfo(id,
              title: 'Delta (fixed)', artist: 'Di Better', album: 'Fourth Fixed', trackNumber: 4),
          isTrue);
      final data = BackupData.decode((await old.service.create()).encode());
      final song = data.songs.firstWhere((s) => s.title == 'Delta (fixed)');
      expect(song.edited, isTrue);
      expect(song.trackNumber, 4);
      expect(data.edited, 1);

      await fresh.song('Delta', 'Di', 'Fourth', '/new/Jazz/delta.mp3');
      final r = await fresh.service.restore(data, newRoot: '/new');
      expect(r.infoRestored, 1);
      final row = await fresh.db
          .customSelect('SELECT title, artist, album, track_number, info_edited FROM songs')
          .getSingle();
      expect(row.read<String>('title'), 'Delta (fixed)');
      expect(row.read<String>('artist'), 'Di Better');
      expect(row.read<String>('album'), 'Fourth Fixed');
      expect(row.read<int>('track_number'), 4);
      expect(row.read<bool>('info_edited'), isTrue);
      final again = await fresh.service.restore(data, newRoot: '/new');
      expect(again.infoRestored, 0, reason: 'nothing more to change');
    });

    test('songs nobody edited are never rewritten', () async {
      final id =
          (await old.db.customSelect("SELECT id FROM songs WHERE title = 'Alpha'").getSingle())
              .read<int>('id');
      await old.library.setFavorite(id, true);
      await fresh.song('Alpha', 'Ann', 'First', '/new/Rock/alpha.mp3');
      final r = await fresh.service.restore(await old.service.create(), newRoot: '/new');
      expect(r.infoRestored, 0);
    });
  });

  group('lyrics and art only', () {
    test('a backup without the activity holds no songs, playlists or left-out list', () async {
      final id = (await old.db.customSelect("SELECT id FROM songs WHERE title = 'Alpha'").getSingle())
          .read<int>('id');
      await old.library.setFavorite(id, true);
      final list = await old.library.createPlaylist('Gym');
      await old.library.addToPlaylist(list, [id]);
      old.out.paths = {'/old/Music/Podcasts'};
      await old.giveArt('Alpha', cover('a.jpg', [1, 2, 3]));
      await old.db.into(old.db.lyricsCache).insert(LyricsCacheCompanion.insert(
          trackKey: 'alpha|ann|first|200',
          found: const Value(true),
          plainLyrics: const Value('words'),
          fetchedAt: DateTime.now()));
      final data = BackupData.decode(
          (await old.service.create(activity: false, settings: false, art: true)).encode());
      expect(data.songs, isEmpty);
      expect(data.playlists, isEmpty);
      expect(data.leftOut, 0);
      expect(data.settings, isEmpty);
      expect(data.lyrics, hasLength(1));
      expect(data.art, hasLength(1));
    });

    test('and it restores: lyrics and covers arrive, nothing else is touched', () async {
      await old.giveArt('Alpha', cover('a.jpg', [7, 7, 7]));
      await old.db.into(old.db.lyricsCache).insert(LyricsCacheCompanion.insert(
          trackKey: 'alpha|ann|first|200',
          found: const Value(true),
          plainLyrics: const Value('words'),
          fetchedAt: DateTime.now()));
      final data = BackupData.decode(
          (await old.service.create(activity: false, settings: false, art: true)).encode());
      await fresh.song('Alpha', 'Ann', 'First', '/new/a.mp3');
      final own = await fresh.library.createPlaylist('Mine');
      final r = await fresh.service.restore(data);
      expect(r.lyricsAdded, 1);
      expect(r.artRestored, 1);
      expect(r.playlistsCreated + r.playlistsMerged, 0);
      expect(r.favoritesSet, 0);
      expect(own, isPositive);
      final lists = await fresh.db.customSelect('SELECT COUNT(*) AS c FROM playlists').getSingle();
      expect(lists.read<int>('c'), 1, reason: 'only the one that was already there');
    });
  });
}
