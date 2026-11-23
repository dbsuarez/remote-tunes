import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() => db.close());

  Future<int> add(
    String title, {
    String artist = 'Artist A',
    String album = 'Album X',
    int? track,
    String? path,
    int duration = 120,
    String? art,
    int size = 1000,
  }) =>
      repo.addSong(
        title: title,
        artist: artist,
        album: album,
        trackNumber: track,
        filePath: path ?? '/music/$title.mp3',
        durationSeconds: duration,
        albumArtPath: art,
        fileSizeBytes: size,
      );

  test('songs persist and can be looked up by id and path', () async {
    final id = await add('One');
    final byId = await repo.songById(id);
    expect(byId!.title, 'One');
    expect(byId.source, 'localFile');
    expect(byId.url, isNull);
    expect((await repo.findByPath('/music/One.mp3'))!.id, id);
    expect(await repo.findByPath('/nope'), isNull);
    expect(await repo.count(), 1);
  });

  test('a song cannot have neither a file path nor a url (schema check)', () async {
    await expectLater(
      db.customStatement(
          "INSERT INTO songs (title, source) VALUES ('x', 'localFile')"),
      throwsA(anything),
    );
  });

  test('songs are sorted by title ignoring case and paged with a total', () async {
    for (final t in ['banana', 'Apple', 'cherry', 'Date', 'elder']) {
      await add(t);
    }
    final p1 = await repo.songs(limit: 2);
    expect(p1.items.map((s) => s.title), ['Apple', 'banana']);
    expect(p1.total, 5);
    expect(p1.hasMore, isTrue);
    final p3 = await repo.songs(offset: 4, limit: 2);
    expect(p3.items.map((s) => s.title), ['elder']);
    expect(p3.hasMore, isFalse);
  });

  test('search matches title, artist and album; wildcards are literal', () async {
    await add('Hello World', artist: 'Adele', album: '25');
    await add('Other', artist: 'Someone', album: 'Hello Album');
    await add('Unrelated', artist: 'Nobody', album: 'Nothing');
    await add('100% Pure', artist: 'Pct', album: 'Pure');
    await add('Under_score', artist: 'Pct', album: 'Pure');

    expect((await repo.songs(query: 'hello')).items.map((s) => s.title),
        ['Hello World', 'Other']);
    expect((await repo.songs(query: 'ADELE')).total, 1);
    expect((await repo.songs(query: '%')).items.map((s) => s.title), ['100% Pure']);
    expect((await repo.songs(query: '_')).items.map((s) => s.title), ['Under_score']);
    expect((await repo.songs(query: 'zzz')).total, 0);
  });

  test('album songs are ordered by track number; artist songs by album then track',
      () async {
    await add('Third', album: 'Alpha', track: 3);
    await add('First', album: 'Alpha', track: 1);
    await add('Second', album: 'Alpha', track: 2);
    await add('Beta Song', album: 'Beta', track: 1);

    final album = await repo.songs(album: 'Alpha');
    expect(album.items.map((s) => s.title), ['First', 'Second', 'Third']);
    final artist = await repo.songs(artist: 'Artist A');
    expect(artist.items.map((s) => s.title),
        ['First', 'Second', 'Third', 'Beta Song']);
  });

  test('artists and albums are grouped with counts', () async {
    await add('a1', artist: 'Zed', album: 'Z1');
    await add('a2', artist: 'Zed', album: 'Z1');
    await add('a3', artist: 'Zed', album: 'Z2');
    await add('b1', artist: 'amy', album: 'A1');

    final artists = await repo.artists();
    expect(artists.items.map((a) => a.name), ['amy', 'Zed']);
    final zed = artists.items.last;
    expect(zed.songCount, 3);
    expect(zed.albumCount, 2);
    expect(artists.total, 2);

    expect((await repo.artists(query: 'ze')).items.single.name, 'Zed');

    final albums = await repo.albums();
    expect(albums.items.map((a) => a.name), ['A1', 'Z1', 'Z2']);
    expect(albums.items[1].songCount, 2);
    expect(albums.items[1].artist, 'Zed');
    expect((await repo.albums(artist: 'Zed')).total, 2);
    expect((await repo.albums(query: 'a1')).items.single.artist, 'amy');
  });

  test('songsByIds keeps the requested order and skips unknown ids', () async {
    final a = await add('A');
    final b = await add('B');
    final c = await add('C');
    final out = await repo.songsByIds([c, 9999, a, b]);
    expect(out.map((s) => s.title), ['C', 'A', 'B']);
    expect(await repo.songsByIds([]), isEmpty);
  });

  test('duplicate detection uses title, artist, album, duration and size', () async {
    await add('Same', duration: 100, size: 5);
    Future<bool> dup({int d = 100, int s = 5, String t = 'Same'}) =>
        repo.hasDuplicate(
          title: t,
          artist: 'Artist A',
          album: 'Album X',
          durationSeconds: d,
          fileSizeBytes: s,
        );
    expect(await dup(), isTrue);
    expect(await dup(d: 101), isFalse);
    expect(await dup(s: 6), isFalse);
    expect(await dup(t: 'Different'), isFalse);
  });

  test('albums share one art file', () async {
    await add('One', art: '/art/a.jpg');
    await add('Two');
    expect(await repo.albumArtFor('Artist A', 'Album X'), '/art/a.jpg');
    expect(await repo.albumArtFor('Artist A', 'Other'), isNull);
  });

  test('removeSong deletes the row and returns it', () async {
    final id = await add('Gone');
    final removed = await repo.removeSong(id);
    expect(removed!.title, 'Gone');
    expect(await repo.songById(id), isNull);
    expect(await repo.removeSong(id), isNull);
  });

  test('watchSongs emits updates', () async {
    final stream = repo.watchSongs();
    final first = await stream.first;
    expect(first, isEmpty);
    final expectation = expectLater(
      stream,
      emitsThrough(predicate<List<Song>>((l) => l.length == 1)),
    );
    await add('Live');
    await expectation;
  });

  test('mapping hides nothing the Player needs and nothing a Controller must not see',
      () async {
    final id = await add('Mapped', art: '/art/m.jpg');
    final song = (await repo.songById(id))!;
    final playable = song.toPlayable()!;
    expect(playable.filePath, '/music/Mapped.mp3');
    expect(playable.albumArtPath, '/art/m.jpg');

    final remote = song.toRemote(available: false);
    expect(remote.available, isFalse);
    final json = remote.toJson().toString();
    expect(json, isNot(contains('/music')));
    expect(json, isNot(contains('/art')));
  });
}
