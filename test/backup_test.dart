import 'dart:convert';
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

/// One phone: its own library, settings and left-out list.
class _Phone {
  _Phone() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepository(db);
    settings = SettingsRepository(db);
    out = MemoryExclusionStore();
    service = BackupService(
      db: db,
      settings: settings,
      exclusions: out,
      copiedSongsDir: '/data/user/0/app/files/library',
    );
  }

  late final AppDatabase db;
  late final LibraryRepository library;
  late final SettingsRepository settings;
  late final MemoryExclusionStore out;
  late final BackupService service;

  Future<int> song(String title, String artist, String album, String path,
      {int seconds = 200}) =>
      library.addSong(
          title: title,
          artist: artist,
          album: album,
          filePath: path,
          durationSeconds: seconds,
          fileSizeBytes: 1000);

  Future<List<String>> playlistSongs(String name) async {
    final rows = await db.customSelect(
      'SELECT s.title AS t FROM playlist_songs ps JOIN songs s ON s.id = ps.song_id '
      'JOIN playlists p ON p.id = ps.playlist_id WHERE p.name = ? ORDER BY ps.position',
      variables: [Variable<String>(name)],
    ).get();
    return [for (final r in rows) r.read<String>('t')];
  }

  Future<Map<String, Object?>> row(String title) async {
    final r = await db.customSelect(
      'SELECT favorite, play_count, skip_count, last_played_at FROM songs WHERE title = ?',
      variables: [Variable<String>(title)],
    ).getSingle();
    return {
      'fav': r.read<bool>('favorite'),
      'plays': r.read<int>('play_count'),
      'skips': r.read<int>('skip_count'),
      'last': r.readNullable<DateTime>('last_played_at'),
    };
  }

  Future<void> close() => db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _Phone old;
  late _Phone fresh;

  setUp(() async {
    old = _Phone();
    fresh = _Phone();
    // The old phone: music in /storage/emulated/0/Music.
    final a = await old.song('Alpha', 'Ann', 'First', '/storage/emulated/0/Music/Rock/alpha.mp3');
    final b = await old.song('Bravo', 'Bob', 'Second', '/storage/emulated/0/Music/Rock/bravo.mp3');
    final c = await old.song('Charlie', 'Cy', 'Third', '/storage/emulated/0/Music/Jazz/charlie.mp3');
    await old.song('Delta', 'Di', 'Fourth', '/storage/emulated/0/Music/Jazz/delta.mp3');
    await old.song('Echo', 'Ed', 'Fifth', '/storage/emulated/0/Music/Echo.mp3');
    final p = await old.library.createPlaylist('Gym');
    await old.library.addToPlaylist(p, [c, a, b]);
    await old.library.setFavorite(a, true);
    await old.library.markPlayed(b);
    await old.library.markPlayed(b);
    await old.library.markPlayed(b);
    await old.library.markSkipped(c);
  });

  tearDown(() async {
    await old.close();
    await fresh.close();
  });

  group('making a backup', () {
    test('keeps only songs that have something worth keeping', () async {
      final data = await old.service.create();
      expect(data.songs.map((s) => s.title).toSet(), {'Alpha', 'Bravo', 'Charlie'});
    });

    test('the root is the folder all the music is in, and paths are relative to it', () async {
      final data = await old.service.create();
      expect(data.root, '/storage/emulated/0/Music');
      expect(data.songs.map((s) => s.relativePath).toSet(),
          {'Rock/alpha.mp3', 'Rock/bravo.mp3', 'Jazz/charlie.mp3'});
    });

    test('playlists keep their order, hearts and counts come along', () async {
      final data = await old.service.create();
      final names = [for (final i in data.playlists.single.songIndexes) data.songs[i].title];
      expect(names, ['Charlie', 'Alpha', 'Bravo']);
      expect(data.favorites, 1);
      final bravo = data.songs.firstWhere((s) => s.title == 'Bravo');
      expect(bravo.plays, 3);
      expect(bravo.lastPlayed, isNotNull);
      expect(data.songs.firstWhere((s) => s.title == 'Charlie').skips, 1);
    });

    test('songs kept inside the app (copies) have no path, only their tags', () async {
      await old.song('Copy', 'Cat', 'Z', '/data/user/0/app/files/library/uuid_copy.mp3');
      final id = (await old.db.customSelect("SELECT id FROM songs WHERE title = 'Copy'").getSingle())
          .read<int>('id');
      await old.library.setFavorite(id, true);
      final data = await old.service.create();
      expect(data.songs.firstWhere((s) => s.title == 'Copy').relativePath, isNull);
      expect(data.root, '/storage/emulated/0/Music', reason: 'the copy does not move the root');
    });

    test('left-out folders are saved relative to the root, others as they are', () async {
      old.out.paths = {
        '/storage/emulated/0/Music/Podcasts',
        '/storage/emulated/0/Music/Rock/skit.mp3',
        '/storage/emulated/0/Download/junk',
      };
      final data = await old.service.create();
      expect(data.leftOutRelative, ['Podcasts', 'Rock/skit.mp3']);
      expect(data.leftOutAbsolute, ['/storage/emulated/0/Download/junk']);
    });

    test('lyrics that were found come along (misses do not), and can be left out', () async {
      await old.db.into(old.db.lyricsCache).insert(LyricsCacheCompanion.insert(
          trackKey: 'alpha|ann|first|200',
          found: const Value(true),
          syncedLyrics: const Value('[00:01.00] hello'),
          source: const Value('LRCLIB'),
          fetchedAt: DateTime.now()));
      await old.db.into(old.db.lyricsCache).insert(LyricsCacheCompanion.insert(
          trackKey: 'none|x|y|1', fetchedAt: DateTime.now()));
      final data = await old.service.create();
      expect(data.lyrics.map((l) => l.trackKey), ['alpha|ann|first|200']);
      expect(data.lyrics.single.synced, contains('hello'));
      expect((await old.service.create(lyrics: false)).lyrics, isEmpty);
    });

    test('settings: the safe ones only, never keys, names or pairing', () async {
      await old.settings.writeValue('skin_id', 'ember');
      await old.settings.writeValue('crossfade_seconds', '4');
      await old.settings.writeValue('eq_default', '{"enabled":true}');
      await old.settings.writeValue('eq_output_bluetooth', '{"enabled":false}');
      await old.settings.writeValue('supabase_url', 'https://secret.example');
      await old.settings.writeValue('supabase_anon_key', 'sb_publishable_xxx');
      await old.settings.writeValue('device_name', 'GT30 Pro');
      await old.settings.writeValue('player_room_code', '123456');
      final data = await old.service.create();
      expect(data.settings.keys.toSet(),
          {'skin_id', 'crossfade_seconds', 'eq_default', 'eq_output_bluetooth'});
      expect(jsonEncode(data.toJson()), isNot(contains('secret.example')));
      expect(jsonEncode(data.toJson()), isNot(contains('sb_publishable')));
      expect((await old.service.create(settings: false)).settings, isEmpty);
    });
  });

  group('the file', () {
    test('goes out and comes back the same, compressed', () async {
      final data = await old.service.create();
      final bytes = data.encode();
      expect(bytes[0], 0x1f, reason: 'gzip');
      final back = BackupData.decode(bytes);
      expect(back.root, data.root);
      expect(back.songs.length, data.songs.length);
      expect(back.playlists.single.name, 'Gym');
      expect([for (final i in back.playlists.single.songIndexes) back.songs[i].title],
          ['Charlie', 'Alpha', 'Bravo']);
      expect(back.songs.firstWhere((s) => s.title == 'Bravo').plays, 3);
    });

    test('plain JSON is read too', () {
      final json = jsonEncode({
        'app': 'RemoteTunes',
        'format': 1,
        'created': '2026-01-01T00:00:00Z',
        'songs': [
          {'t': 'X', 'a': 'Y'}
        ],
      });
      expect(BackupData.decode(utf8.encode(json)).songs.single.title, 'X');
    });

    test('files that are not backups say so plainly', () {
      void bad(List<int> bytes, String text) {
        try {
          BackupData.decode(bytes);
          fail('accepted');
        } on BackupException catch (e) {
          expect(e.message, contains(text));
        }
      }

      bad(const [], 'empty');
      bad(utf8.encode('hello'), 'not a RemoteTunes backup');
      bad(utf8.encode('{"app":"Other","format":1}'), 'not a RemoteTunes backup');
      bad(gzip.encode(utf8.encode('{"app":"RemoteTunes","format":99}')), 'newer version');
      bad([0x1f, 0x8b, 1, 2, 3], 'not a RemoteTunes backup');
    });

    test('broken entries are skipped and the others keep their places', () {
      final json = jsonEncode({
        'app': 'RemoteTunes',
        'format': 1,
        'created': 'not a date',
        'songs': [
          {'t': 'One'},
          'garbage',
          {'t': 'Three'},
        ],
        'playlists': [
          {'name': 'L', 'songs': [0, 1, 2, 99, 'x']},
          {'name': '  ', 'songs': [0]},
          5,
        ],
        'lyrics': [
          {'k': 'a|b|c|1', 'p': 'text'},
          {'p': 'no key'},
        ],
        'settings': {'a': 'b', 'c': 5},
      });
      final d = BackupData.decode(utf8.encode(json));
      expect(d.songs.map((s) => s.title), ['One', 'Three']);
      expect(d.playlists, hasLength(1));
      expect([for (final i in d.playlists.single.songIndexes) d.songs[i].title], ['One', 'Three']);
      expect(d.lyrics, hasLength(1));
      expect(d.settings, {'a': 'b'});
    });
  });

  group('putting it on another phone', () {
    Future<BackupData> backup() async => BackupData.decode((await old.service.create()).encode());

    Future<void> newPhoneLibrary() async {
      // Same music, copied to another folder; one file renamed, one in another folder,
      // one song missing, one with only its title in common.
      await fresh.song('Alpha', 'Ann', 'First', '/sdcard/Songs/Rock/alpha.mp3');
      await fresh.song('Bravo', 'Bob', 'Second', '/sdcard/Songs/Rock/Bravo (renamed).mp3');
      await fresh.song('Charlie', 'Cy', 'Third', '/sdcard/Songs/Misc/charlie.mp3', seconds: 201);
      await fresh.song('Delta', 'Di', 'Fourth', '/sdcard/Songs/Jazz/delta.mp3');
    }

    test('songs are found by path under the new root, then by tags (a second out is fine)',
        () async {
      await newPhoneLibrary();
      final r = await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect(r.songsInBackup, 3);
      expect(r.byPath, 1, reason: 'Alpha: same place under the new root');
      expect(r.byTags, 2, reason: 'Bravo was renamed and Charlie is 1 s different');
      expect(r.notFound, isEmpty);
      expect(r.found, 3);
    });

    test('hearts, play and skip counts and the last played time come across', () async {
      await newPhoneLibrary();
      await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect((await fresh.row('Alpha'))['fav'], isTrue);
      final bravo = await fresh.row('Bravo');
      expect(bravo['plays'], 3);
      expect(bravo['last'], isNotNull);
      expect((await fresh.row('Charlie'))['skips'], 1);
      expect((await fresh.row('Delta'))['plays'], 0, reason: 'it was not in the backup');
    });

    test('a playlist comes across in its order', () async {
      await newPhoneLibrary();
      final r = await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect(await fresh.playlistSongs('Gym'), ['Charlie', 'Alpha', 'Bravo']);
      expect(r.playlistsCreated, 1);
      expect(r.playlistSongsAdded, 3);
    });

    test('songs that are not on the new phone are listed, never guessed', () async {
      await fresh.song('Alpha', 'Ann', 'First', '/sdcard/Songs/Rock/alpha.mp3');
      await fresh.song('Other', 'Nobody', 'Nowhere', '/sdcard/Songs/x.mp3');
      final r = await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect(r.found, 1);
      expect(r.notFound, ['Bravo (Bob)', 'Charlie (Cy)']);
      expect(await fresh.playlistSongs('Gym'), ['Alpha'], reason: 'only what was found');
    });

    test('with only title and artist in common, a single match is used (and said)', () async {
      await fresh.song('Alpha', 'Ann', 'A Different Album', '/sdcard/Elsewhere/a.mp3', seconds: 300);
      final r = await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect(r.looseMatches, 1);
      expect(r.byPath, 0);
      expect((await fresh.row('Alpha'))['fav'], isTrue);
    });

    test('two songs with the same title and artist are not guessed between', () async {
      await fresh.song('Alpha', 'Ann', 'Album One', '/sdcard/1/a.mp3', seconds: 100);
      await fresh.song('Alpha', 'Ann', 'Album Two', '/sdcard/2/a.mp3', seconds: 150);
      final r = await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect(r.looseMatches, 0);
      expect(r.notFound, contains('Alpha (Ann)'));
    });

    test('on the same phone the old paths still work with no new root', () async {
      final again = await backup();
      final r = await old.service.restore(again);
      expect(r.byPath, 3);
      expect(r.playlistsMerged, 1, reason: 'the Gym playlist is already there');
      expect(await old.playlistSongs('Gym'), ['Charlie', 'Alpha', 'Bravo'],
          reason: 'nothing is added twice');
    });

    test('it only adds: what is on the new phone stays, same-name playlists are merged', () async {
      await newPhoneLibrary();
      final own = await fresh.library.createPlaylist('gym'); // another case: same list
      final delta = (await fresh.db.customSelect("SELECT id FROM songs WHERE title = 'Delta'").getSingle())
          .read<int>('id');
      await fresh.library.addToPlaylist(own, [delta]);
      await fresh.library.markPlayed(delta);
      final r = await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect(r.playlistsMerged, 1);
      expect(r.playlistsCreated, 0);
      expect(await fresh.playlistSongs('gym'), ['Delta', 'Charlie', 'Alpha', 'Bravo']);
      expect((await fresh.row('Delta'))['plays'], 1, reason: 'untouched');
    });

    test('counts keep the larger number', () async {
      await newPhoneLibrary();
      final alpha = (await fresh.db.customSelect("SELECT id FROM songs WHERE title = 'Alpha'").getSingle())
          .read<int>('id');
      for (var i = 0; i < 5; i++) {
        await fresh.library.markPlayed(alpha);
      }
      final bravo = (await fresh.db.customSelect("SELECT id FROM songs WHERE title = 'Bravo'").getSingle())
          .read<int>('id');
      await fresh.library.markPlayed(bravo);
      await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect((await fresh.row('Bravo'))['plays'], 3, reason: 'the backup had more');
      expect((await fresh.row('Alpha'))['plays'], 5, reason: 'this phone had more');
    });

    test('left-out folders are put under the new root', () async {
      old.out.paths = {'/storage/emulated/0/Music/Podcasts', '/storage/emulated/0/Download/junk'};
      await newPhoneLibrary();
      final r = await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect(fresh.out.paths, {'/sdcard/Songs/Podcasts', '/storage/emulated/0/Download/junk'});
      expect(r.leftOutAdded, 2);
    });

    test('lyrics are added, but never replace what this phone found itself', () async {
      for (final p in [old, fresh]) {
        await p.db.into(p.db.lyricsCache).insert(LyricsCacheCompanion.insert(
            trackKey: 'same|a|b|1',
            found: const Value(true),
            plainLyrics: Value(identical(p, old) ? 'OLD PHONE' : 'NEW PHONE'),
            fetchedAt: DateTime.now()));
      }
      await old.db.into(old.db.lyricsCache).insert(LyricsCacheCompanion.insert(
          trackKey: 'only|a|b|1',
          found: const Value(true),
          plainLyrics: const Value('only on the old one'),
          fetchedAt: DateTime.now()));
      final r = await fresh.service.restore(await backup());
      expect(r.lyricsAdded, 1);
      final kept = await fresh.db.customSelect(
          "SELECT plain_lyrics AS p FROM lyrics_cache WHERE track_key = 'same|a|b|1'").getSingle();
      expect(kept.read<String>('p'), 'NEW PHONE');
    });

    test('settings are applied, only the safe ones, and can be skipped', () async {
      await old.settings.writeValue('skin_id', 'forest');
      await old.settings.writeValue('eq_default', '{"enabled":true}');
      final data = await backup();
      // A file written by hand could try to slip something in.
      final evil = BackupData(
        created: DateTime.now(),
        settings: {...data.settings, 'supabase_url': 'https://evil.example', 'device_name': 'x'},
      );
      final r = await fresh.service.restore(evil);
      expect(r.settingsApplied, 2);
      expect(await fresh.settings.readValue('skin_id'), 'forest');
      expect(await fresh.settings.readValue('eq_default'), contains('enabled'));
      expect(await fresh.settings.readValue('supabase_url'), isNull);
      expect(await fresh.settings.readValue('device_name'), isNull);

      final other = _Phone();
      addTearDown(other.close);
      final skipped = await other.service.restore(evil, includeSettings: false);
      expect(skipped.settingsApplied, 0);
      expect(await other.settings.readValue('skin_id'), isNull);
    });

    test('an empty library just gives a report that nothing was found', () async {
      final r = await fresh.service.restore(await backup(), newRoot: '/sdcard/Songs');
      expect(r.found, 0);
      expect(r.notFound, hasLength(3));
      expect(r.playlistsCreated, 1, reason: 'the empty playlist is still made');
      expect(await fresh.playlistSongs('Gym'), isEmpty);
    });
  });

  group('the common folder', () {
    test('is the deepest folder that holds every file', () {
      expect(BackupService.commonDir(['/a/b/c/x.mp3', '/a/b/d/y.mp3']), '/a/b');
      expect(BackupService.commonDir(['/a/b/x.mp3']), '/a/b');
      expect(BackupService.commonDir(['/a/x.mp3', '/b/y.mp3']), '/');
      expect(BackupService.commonDir([]), '');
    });
  });
}
