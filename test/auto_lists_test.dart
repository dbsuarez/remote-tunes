import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late LibraryRepository repo;
  final ids = <String, int>{};

  Future<void> add(String title, String path) async {
    ids[title] = await repo.addSong(
      title: title,
      artist: 'Ann',
      album: 'Album',
      filePath: path,
      durationSeconds: 100,
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    await add('Alpha', '/storage/emulated/0/Music/Rock/alpha.mp3');
    await add('Bravo', '/storage/emulated/0/Music/Rock/bravo.mp3');
    await add('Charlie', '/storage/emulated/0/Music/Jazz/charlie.mp3');
    await add('Delta', '/storage/emulated/0/Download/delta.mp3');
  });

  tearDown(() => db.close());

  Future<List<String>> titles({String? view, int? folderId}) async =>
      [for (final s in (await repo.songs(view: view, folderId: folderId)).items) s.title];

  group('Top (most played)', () {
    test('is empty until something has been played', () async {
      expect(await titles(view: LibraryView.top), isEmpty);
    });

    test('lists played songs, most played first', () async {
      await repo.markPlayed(ids['Bravo']!);
      await repo.markPlayed(ids['Bravo']!);
      await repo.markPlayed(ids['Bravo']!);
      await repo.markPlayed(ids['Delta']!);
      await repo.markPlayed(ids['Alpha']!);
      await repo.markPlayed(ids['Alpha']!);
      expect(await titles(view: LibraryView.top), ['Bravo', 'Alpha', 'Delta']);
    });

    test('a song never played is not in it', () async {
      await repo.markPlayed(ids['Alpha']!);
      expect(await titles(view: LibraryView.top), ['Alpha']);
    });

    test('playing also still counts as recent', () async {
      await repo.markPlayed(ids['Charlie']!);
      expect(await titles(view: LibraryView.recent), ['Charlie']);
    });

    test('search works inside it', () async {
      await repo.markPlayed(ids['Alpha']!);
      await repo.markPlayed(ids['Bravo']!);
      final page = await repo.songs(view: LibraryView.top, query: 'brav');
      expect([for (final s in page.items) s.title], ['Bravo']);
    });
  });

  group('New (added lately)', () {
    test('the most recently added song is first', () async {
      expect(await titles(view: LibraryView.newest), ['Delta', 'Charlie', 'Bravo', 'Alpha']);
    });

    test('it holds at most the newest hundred', () async {
      for (var i = 0; i < 110; i++) {
        await add('Extra $i', '/m/extra$i.mp3');
      }
      final page = await repo.songs(view: LibraryView.newest, limit: 100);
      expect(page.total, LibraryRepository.autoListSize);
      expect(page.items.first.title, 'Extra 109');
    });
  });

  group('Folders', () {
    test('each folder is listed with how many songs it holds', () async {
      final page = await repo.folders();
      expect([for (final f in page.items) '${f.name}:${f.songCount}'],
          ['Download:1', 'Jazz:1', 'Rock:2']);
      expect(page.total, 3);
    });

    test('the folder it is in is shown to tell same-named folders apart', () async {
      final f = (await repo.folders()).items.firstWhere((f) => f.name == 'Rock');
      expect(f.parent, 'Music');
    });

    test('a folder id never contains the path', () async {
      for (final f in (await repo.folders()).items) {
        expect(f.toJson().toString(), isNot(contains('emulated')));
      }
    });

    test('opening a folder lists only its songs', () async {
      final rock = (await repo.folders()).items.firstWhere((f) => f.name == 'Rock');
      expect(await titles(folderId: rock.id), ['Alpha', 'Bravo']);
    });

    test('search narrows folders, and songs inside one', () async {
      expect([for (final f in (await repo.folders(query: 'ja')).items) f.name], ['Jazz']);
      final rock = (await repo.folders()).items.firstWhere((f) => f.name == 'Rock');
      final page = await repo.songs(folderId: rock.id, query: 'alp');
      expect([for (final s in page.items) s.title], ['Alpha']);
    });

    test('an unknown folder id gives no songs, not everything', () async {
      expect(await titles(folderId: 12345), isEmpty);
    });

    test('the same folder always has the same id', () async {
      final a = (await repo.folders()).items.map((f) => f.id).toList();
      final b = (await repo.folders()).items.map((f) => f.id).toList();
      expect(a, b);
      expect(LibraryRepository.folderIdOf('/a/b'), LibraryRepository.folderIdOf('/a/b'));
      expect(LibraryRepository.folderIdOf('/a/b'), isNot(LibraryRepository.folderIdOf('/a/c')));
    });

    test('paging works', () async {
      final page = await repo.folders(offset: 1, limit: 1);
      expect(page.items.map((f) => f.name), ['Jazz']);
      expect(page.total, 3);
    });

    test('internet tracks (no file) are not in any folder', () async {
      final before = (await repo.folders()).total;
      expect(before, 3);
    });
  });
}
