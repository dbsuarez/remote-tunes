import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/album_art_fetcher.dart';

const _mbid = '11111111-2222-3333-4444-555555555555';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late LibraryRepository repo;
  late Directory dir;
  late List<Uri> asked;
  final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 40)));

  AlbumArtFetcher make(http.Response Function(Uri) answer) => AlbumArtFetcher(
        db: db,
        directory: () async => dir,
        gap: Duration.zero,
        client: MockClient((r) async {
          asked.add(r.url);
          return answer(r.url);
        }),
      );

  http.Response mb(List<String> ids) => http.Response(
      jsonEncode({'releases': [for (final i in ids) {'id': i}]}), 200);

  Future<int> add(String title, String artist, String album, {String? art}) =>
      repo.addSong(
          title: title,
          artist: artist,
          album: album,
          filePath: '/m/$title.mp3',
          albumArtPath: art);

  Future<String?> artOf(int id) async =>
      (await repo.songById(id))?.albumArtPath;

  setUp(() async {
    asked = [];
    dir = Directory.systemTemp.createTempSync('rt_art_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('only albums with no cover and a known artist are looked up', () async {
    await add('a', 'Ann', 'One');
    await add('b', 'Ann', 'One');
    await add('c', 'Ann', 'Two', art: '/art/two.jpg');
    await add('d', 'Unknown artist', 'Three');
    await add('e', 'Bob', 'Unknown album');
    final f = make((_) => http.Response('', 404));
    final m = await f.missing();
    expect(m.keys.map((k) => '${k.artist}/${k.album}'), ['Ann/One']);
    expect(m.values.single, hasLength(2));
    expect(await f.missingAlbums(), 1);
  });

  test('a cover is found, saved on the phone, and given to every song of the album', () async {
    final a = await add('a', 'Ann', 'One');
    final b = await add('b', 'Ann', 'One');
    final f = make((u) => u.host == 'musicbrainz.org'
        ? mb([_mbid])
        : http.Response.bytes(jpeg, 200));
    final r = await f.run();
    expect([r.albums, r.found, r.notFound, r.failed], [1, 1, 0, 0]);
    final pa = await artOf(a);
    expect(pa, isNotNull);
    expect(await artOf(b), pa);
    expect(File(pa!).readAsBytesSync(), jpeg);
    expect(pa, startsWith(dir.path));
    expect(asked.last.toString(), 'https://coverartarchive.org/release/$_mbid/front-500');
  });

  test('only the artist and album names are sent', () async {
    await add('secret title', 'Ann', 'One');
    await make((u) => http.Response('', 404)).run();
    final all = asked.join(' ');
    expect(all, isNot(contains('secret')));
    expect(all, isNot(contains('/m/')));
    final q = asked.first.queryParameters['query']!;
    expect(q, contains('One'));
    expect(q, contains('Ann'));
  });

  test('the next release is tried when the first has no picture', () async {
    final a = await add('a', 'Ann', 'One');
    const second = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    final f = make((u) {
      if (u.host == 'musicbrainz.org') return mb([_mbid, second]);
      return u.path.contains(second) ? http.Response.bytes(jpeg, 200) : http.Response('', 404);
    });
    final r = await f.run();
    expect(r.found, 1);
    expect(await artOf(a), isNotNull);
  });

  test('no match anywhere: nothing changes and it is counted', () async {
    final a = await add('a', 'Ann', 'One');
    final r = await make((u) => u.host == 'musicbrainz.org' ? mb([]) : http.Response('', 404)).run();
    expect([r.found, r.notFound], [0, 1]);
    expect(await artOf(a), isNull);
  });

  test('something that is not a picture is never saved', () async {
    final a = await add('a', 'Ann', 'One');
    final f = make((u) => u.host == 'musicbrainz.org'
        ? mb([_mbid])
        : http.Response.bytes(Uint8List.fromList(utf8.encode('<html>' * 50)), 200));
    final r = await f.run();
    expect(r.found, 0);
    expect(await artOf(a), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('a huge file is refused', () async {
    await add('a', 'Ann', 'One');
    final big = Uint8List(4 * 1024 * 1024)..[0] = 0xFF..[1] = 0xD8;
    final r = await make((u) => u.host == 'musicbrainz.org'
        ? mb([_mbid])
        : http.Response.bytes(big, 200)).run();
    expect(r.found, 0);
  });

  test('a link id that is not an id is never fetched', () async {
    await add('a', 'Ann', 'One');
    final f = make((u) => u.host == 'musicbrainz.org'
        ? mb(['../../evil'])
        : http.Response.bytes(jpeg, 200));
    await f.run();
    expect(asked.where((u) => u.host == 'coverartarchive.org'), isEmpty);
  });

  test('no internet: the album is skipped, not marked as having no cover', () async {
    final a = await add('a', 'Ann', 'One');
    final f = AlbumArtFetcher(
      db: db,
      directory: () async => dir,
      gap: Duration.zero,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    final r = await f.run();
    expect([r.failed, r.found, r.notFound], [1, 0, 0]);
    expect(await artOf(a), isNull);
    expect(await f.missingAlbums(), 1, reason: 'still missing, so it can be tried again');
  });

  test('progress is reported and a run can be stopped', () async {
    await add('a', 'Ann', 'One');
    await add('b', 'Bob', 'Two');
    await add('c', 'Cat', 'Three');
    final seen = <String>[];
    var stop = false;
    final r = await make((_) => http.Response('', 404)).run(
      onProgress: (d, t) {
        seen.add('$d/$t');
        if (d == 1) stop = true;
      },
      isCancelled: () => stop,
    );
    expect(seen, ['1/3']);
    expect(r.cancelled, isTrue);
  });

  test('a quote in a name does not break the search text', () async {
    await add('a', 'Ann "The Voice"', 'One "Live"');
    await make((_) => http.Response('', 404)).run();
    final q = asked.first.queryParameters['query']!;
    expect(RegExp('"').allMatches(q).length, 4, reason: 'only the two pairs we added');
  });
}
