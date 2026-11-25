import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/library/import_actions.dart' show quietRescanWith;
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/features/library/settings_exclusion_store.dart';

/// Gives every file its own tags, taken from its name: "one.mp3" is the song "one".
class _NameTags implements MetadataExtractor {
  @override
  Future<ExtractedMetadata> extract(String path) async => ExtractedMetadata(
        title: p.basenameWithoutExtension(path),
        artist: 'Artist',
        album: 'Album',
        durationSeconds: 100,
      );
}

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late Directory root;
  late Directory music;
  late MemoryExclusionStore out;
  late MemoryMusicFoldersStore folders;
  late LibraryImportService service;

  Future<String> make(String relative, {int bytes = 64}) async {
    final f = File(p.join(music.path, relative));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(Uint8List.fromList(List.filled(bytes, 3)));
    return f.path;
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    root = await Directory.systemTemp.createTemp('rescan');
    music = await Directory(p.join(root.path, 'Music')).create();
    out = MemoryExclusionStore();
    folders = MemoryMusicFoldersStore();
    service = LibraryImportService(
      library: repo,
      extractor: _NameTags(),
      libraryDir: Directory(p.join(root.path, 'library')),
      artDir: Directory(p.join(root.path, 'art')),
      exclusions: out,
      folders: folders,
    );
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  group('remembering the folders that were added', () {
    test('adding a folder remembers it, with how many songs and which folders it had', () async {
      await make('Rock/a.mp3');
      await make('Rock/Live/b.mp3');
      await make('c.mp3');
      await service.importFolder(music.path);
      final f = (await service.musicFolders()).single;
      expect(f.path, music.path);
      expect(f.songCount, 3);
      expect(f.knownDirs, {'', 'Rock', p.join('Rock', 'Live')});
      expect(f.lastScan, isNotNull);
    });

    test('adding the same folder again keeps one entry, with the new count', () async {
      await make('a.mp3');
      await service.importFolder(music.path);
      await make('b.mp3');
      await service.importFolder(music.path);
      final list = await service.musicFolders();
      expect(list, hasLength(1));
      expect(list.single.songCount, 2);
    });

    test('a folder inside one that is remembered is covered by it', () async {
      await make('Rock/a.mp3');
      await service.importFolder(music.path);
      await service.importFolder(p.join(music.path, 'Rock'));
      expect((await service.musicFolders()).map((f) => f.path), [music.path]);
    });

    test('adding a folder that holds remembered ones replaces them', () async {
      await make('Rock/a.mp3');
      await make('Jazz/b.mp3');
      await service.importFolder(p.join(music.path, 'Rock'));
      await service.importFolder(p.join(music.path, 'Jazz'));
      expect(await service.musicFolders(), hasLength(2));
      await service.importFolder(music.path);
      expect((await service.musicFolders()).map((f) => f.path), [music.path]);
    });

    test('a folder can be forgotten; its songs stay', () async {
      await make('a.mp3');
      await service.importFolder(music.path);
      await service.forgetFolder(music.path);
      expect(await service.musicFolders(), isEmpty);
      expect(await repo.count(), 1);
    });

    test('the list survives being saved as text, and junk is ignored', () async {
      final store = SettingsMusicFoldersStore(SettingsRepository(db));
      expect(await store.load(), isEmpty);
      await store.save([
        MusicFolder(
            path: '/m',
            lastScan: DateTime.fromMillisecondsSinceEpoch(1700000000000),
            knownDirs: {'', 'A'},
            songCount: 5),
      ]);
      final back = (await store.load()).single;
      expect(back.path, '/m');
      expect(back.knownDirs, {'', 'A'});
      expect(back.songCount, 5);
      await SettingsRepository(db).writeValue(SettingsMusicFoldersStore.key, 'junk');
      expect(await store.load(), isEmpty);
      await SettingsRepository(db)
          .writeValue(SettingsMusicFoldersStore.key, '[{"path":""},5,{"path":"/ok"}]');
      expect((await store.load()).map((f) => f.path), ['/ok']);
    });
  });

  group('the plan', () {
    Future<void> start() async {
      await make('Rock/a.mp3');
      await make('Jazz/b.mp3');
      await service.importFolder(music.path);
    }

    test('new songs in a folder that was known need no question', () async {
      await start();
      await make('Rock/new.mp3');
      final plan = await service.planRescan();
      expect(plan.folders, hasLength(1));
      expect(plan.newFolders, isEmpty);
      expect(plan.unreachable, isEmpty);
    });

    test('a folder that was not there before is asked about, with its song count', () async {
      await start();
      await make('Podcasts/ep1.mp3');
      await make('Podcasts/ep2.mp3');
      final plan = await service.planRescan();
      expect(plan.newFolders, hasLength(1));
      expect(plan.newFolders.single.name, 'Podcasts');
      expect(plan.newFolders.single.songCount, 2);
      expect(plan.newFolders.single.path, p.join(music.path, 'Podcasts'));
    });

    test('a new folder inside another new folder is asked about as the outer one', () async {
      await start();
      await make('New/x.mp3');
      await make('New/Deep/y.mp3');
      final plan = await service.planRescan();
      expect(plan.newFolders.map((f) => f.name), ['New']);
    });

    test('a folder that is already left out is not asked about', () async {
      await start();
      out.paths = {p.join(music.path, 'Podcasts')};
      await make('Podcasts/ep1.mp3');
      expect((await service.planRescan()).newFolders, isEmpty);
    });

    test('a remembered folder that cannot be reached is named, not scanned', () async {
      await start();
      await music.rename(p.join(root.path, 'Elsewhere'));
      final plan = await service.planRescan();
      expect(plan.unreachable, [music.path]);
      expect(plan.folders, isEmpty);
    });

    test('planning changes nothing', () async {
      await start();
      await make('Podcasts/ep1.mp3');
      final before = await repo.count();
      await service.planRescan();
      expect(await repo.count(), before);
      expect((await service.musicFolders()).single.knownDirs, {'', 'Rock', 'Jazz'});
    });
  });

  group('the rescan', () {
    test('adds the new songs and says how many folders it went through', () async {
      await make('Rock/a.mp3');
      await service.importFolder(music.path);
      await make('Rock/new1.mp3');
      await make('Rock/new2.mp3');
      final r = await service.rescan(await service.planRescan());
      expect(r.added, 2);
      expect(r.duplicates, 1);
      expect(r.foldersScanned, 1);
      expect(await repo.count(), 3);
    });

    test('a song that was moved is followed, and is not missing', () async {
      final old = await make('Inbox/one.mp3');
      await service.importFolder(music.path);
      final home = File(p.join(music.path, 'Rock', 'one.mp3'));
      await home.parent.create(recursive: true);
      await File(old).rename(home.path);
      final r = await service.rescan(await service.planRescan());
      expect(r.relinked, 1);
      expect(r.added, 0);
      expect(r.missing, isEmpty);
      expect(await repo.count(), 1);
    });

    test('new folders the user did not want are left out, remembered, and not added', () async {
      await make('Rock/a.mp3');
      await service.importFolder(music.path);
      await make('Podcasts/ep1.mp3');
      final plan = await service.planRescan();
      final r = await service.rescan(plan, leaveOut: {plan.newFolders.single.path});
      expect(r.added, 0);
      expect(r.excluded, 1);
      expect(out.paths, {p.join(music.path, 'Podcasts')});
      expect(await repo.count(), 1);
      // The next time it is not asked about again.
      expect((await service.planRescan()).newFolders, isEmpty);
    });

    test('new folders the user did want are added, and not asked about again', () async {
      await make('Rock/a.mp3');
      await service.importFolder(music.path);
      await make('Jazz/b.mp3');
      final plan = await service.planRescan();
      expect(plan.newFolders, hasLength(1));
      final r = await service.rescan(plan);
      expect(r.added, 1);
      expect((await service.planRescan()).newFolders, isEmpty);
    });

    test('songs whose file is gone are listed as missing, with their names', () async {
      final a = await make('Rock/a.mp3');
      await make('Rock/b.mp3');
      await service.importFolder(music.path);
      File(a).deleteSync();
      final r = await service.rescan(await service.planRescan());
      expect(r.missing.map((m) => m.title), ['a']);
      expect(r.missing.single.path, p.normalize(a));
      expect(r.checked, 2);
      expect(r.mostMissing, isFalse);
    });

    test('when most songs are missing it says so (the storage is probably not there)', () async {
      final paths = [for (var i = 0; i < 12; i++) await make('s$i.mp3', bytes: 64 + i)];
      await service.importFolder(music.path);
      for (final path in paths.take(9)) {
        File(path).deleteSync();
      }
      final r = await service.rescan(await service.planRescan());
      expect(r.missing, hasLength(9));
      expect(r.mostMissing, isTrue);
    });

    test('songs of a folder that cannot be reached are not called missing', () async {
      await make('a.mp3');
      await service.importFolder(music.path);
      await music.rename(p.join(root.path, 'Elsewhere'));
      final r = await service.rescan(await service.planRescan());
      expect(r.unreachable, [music.path]);
      expect(r.missing, isEmpty);
      expect(r.foldersScanned, 0);
    });

    test('missing songs can be removed without going on the left-out list', () async {
      final a = await make('a.mp3');
      await service.importFolder(music.path);
      File(a).deleteSync();
      final r = await service.rescan(await service.planRescan());
      await service.removeSongs(r.missing.map((m) => m.id));
      expect(await repo.count(), 0);
      expect(out.paths, isEmpty);
    });

    test('a removed missing song comes back when the file does', () async {
      final a = await make('a.mp3');
      await service.importFolder(music.path);
      File(a).deleteSync();
      await service.removeSongs((await service.rescan(await service.planRescan())).missing.map((m) => m.id));
      await make('a.mp3');
      final r = await service.rescan(await service.planRescan());
      expect(r.added, 1);
    });

    test('playlists, hearts and counts of a moved song are kept through a rescan', () async {
      final old = await make('Inbox/one.mp3');
      await service.importFolder(music.path);
      final id = (await db.customSelect('SELECT id FROM songs').getSingle()).read<int>('id');
      final list = await repo.createPlaylist('Mine');
      await repo.addToPlaylist(list, [id]);
      await repo.setFavorite(id, true);
      await repo.markPlayed(id);
      final home = File(p.join(music.path, 'Rock', 'one.mp3'));
      await home.parent.create(recursive: true);
      await File(old).rename(home.path);
      await service.rescan(await service.planRescan());
      final row = await db.customSelect(
          'SELECT id, favorite, play_count, file_path FROM songs WHERE id = ?',
          variables: [Variable<int>(id)]).getSingle();
      expect(row.read<bool>('favorite'), isTrue);
      expect(row.read<int>('play_count'), 1);
      expect(row.read<String>('file_path'), home.path);
    });

    test('an empty list of folders rescans nothing', () async {
      final plan = await service.planRescan();
      expect(plan.folders, isEmpty);
      final r = await service.rescan(plan);
      expect(r.foldersScanned, 0);
      expect(r.added, 0);
    });
  });

  group('the quiet rescan when the app opens', () {
    test('says nothing with no remembered folders', () async {
      expect(await quietRescanWith(service), isNull);
    });

    test('adds new songs without asking, and says how many', () async {
      await make('Rock/a.mp3');
      await service.importFolder(music.path);
      await make('Rock/b.mp3');
      await make('Rock/c.mp3');
      expect(await quietRescanWith(service), 'Rescan: 2 new songs added');
      expect((await repo.songs()).total, 3);
      await make('Rock/d.mp3');
      expect(await quietRescanWith(service), 'Rescan: 1 new song added');
    });

    test('says nothing when nothing is new', () async {
      await make('a.mp3');
      await service.importFolder(music.path);
      expect(await quietRescanWith(service), isNull);
    });

    test('a new folder is not added; the user is pointed to the one-tap rescan', () async {
      await make('Rock/a.mp3');
      await service.importFolder(music.path);
      await make('Jazz/j.mp3');
      final msg = await quietRescanWith(service);
      expect(msg, contains('new folder'));
      expect((await repo.songs()).total, 1, reason: 'nothing added behind their back');
      expect(await out.load(), isEmpty, reason: 'and not left out either');
    });

    test('a missing song is never removed', () async {
      final a = await make('a.mp3');
      await make('b.mp3');
      await service.importFolder(music.path);
      File(a).deleteSync();
      await quietRescanWith(service);
      expect((await repo.songs()).total, 2);
    });

    test('a folder that cannot be reached says nothing and does no harm', () async {
      await make('a.mp3');
      await service.importFolder(music.path);
      music.deleteSync(recursive: true);
      expect(await quietRescanWith(service), isNull);
      expect((await repo.songs()).total, 1);
    });
  });
}
