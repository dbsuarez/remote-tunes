import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/features/cloud/cloud_models.dart';
import 'package:remote_tunes/features/cloud/cloud_service.dart';
import 'package:remote_tunes/features/cloud/r2_client.dart';
import 'package:remote_tunes/features/cloud/sigv4.dart';

const _account = 'abcdef0123456789abcdef0123456789';
const config = CloudConfig(
  accountId: _account,
  bucket: 'remotetunes',
  publicUrl: 'https://pub-123.r2.dev',
  accessKeyId: 'KEYID',
  secretKey: 'SECRET',
);

/// A pretend R2: stores files by key, checks each signed request is well formed, and serves the
/// public address too.
class FakeR2 {
  final files = <String, List<int>>{};
  final log = <String>[];
  int failPutsFrom = -1; // fail every PUT from this count on
  int failStatus = 500;
  bool refuse = false;
  int puts = 0;

  http.Response handle(http.Request r) {
    log.add('${r.method} ${r.url.path}');
    if (r.url.host == 'pub-123.r2.dev') {
      final key = r.url.path.substring(1);
      final f = files[key];
      return f == null ? http.Response('', 404) : http.Response.bytes(f, 200);
    }
    expect(r.url.host, '$_account.r2.cloudflarestorage.com');
    final auth = r.headers['authorization'] ?? '';
    expect(auth, startsWith('AWS4-HMAC-SHA256 Credential=KEYID/'));
    expect(auth, contains('/auto/s3/aws4_request'));
    expect(auth, contains('SignedHeaders=host;x-amz-content-sha256;x-amz-date'));
    expect(r.headers['x-amz-date'], matches(RegExp(r'^\d{8}T\d{6}Z$')));
    final hash = r.headers['x-amz-content-sha256']!;
    if (hash != SigV4.unsignedPayload) expect(hash, SigV4.sha256Hex(r.bodyBytes), reason: 'the body hash must be of the body');
    if (refuse) return http.Response('', 403);
    expect(r.url.path, startsWith('/remotetunes/'));
    final key = r.url.path.substring('/remotetunes/'.length);
    switch (r.method) {
      case 'GET':
        final f = files[key];
        return f == null ? http.Response('', 404) : http.Response.bytes(f, 200);
      case 'PUT':
        if (failPutsFrom >= 0 && puts++ >= failPutsFrom) return http.Response('', failStatus);
        files[key] = r.bodyBytes;
        return http.Response('', 200);
      case 'DELETE':
        files.remove(key);
        return http.Response('', 204);
    }
    return http.Response('', 405);
  }

  CloudLibraryService service({CloudConfig cfg = config, String Function()? ids}) {
    var n = 0;
    return CloudLibraryService(
      cfg,
      client: MockClient((r) async => handle(r)),
      newId: ids ?? () => 'id${++n}',
      now: () => DateTime.utc(2026, 11, 25, 12),
    );
  }

  CloudCatalog get catalog => CloudCatalog.fromJson(jsonDecode(utf8.decode(files['catalog.json']!)));
}

CloudUpload song(String title, {String artist = 'Ann', String album = 'Alpha', String genre = 'Rock', int size = 300, Uint8List? art, String ext = 'mp3', int dur = 200}) =>
    CloudUpload(
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      durationSeconds: dur,
      ext: ext,
      length: size,
      art: art,
      open: () => Stream.value(List.filled(size, 7)),
    );

void main() {
  group('the signature', () {
    test('matches the example in the AWS documentation', () {
      // "GET Object" with a Range header, from the S3 signature version 4 documentation.
      final h = SigV4(accessKeyId: 'AKIAIOSFODNN7EXAMPLE', secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', region: 'us-east-1')
          .sign(
        method: 'GET',
        host: 'examplebucket.s3.amazonaws.com',
        path: '/test.txt',
        extraSigned: {'Range': 'bytes=0-9'},
        payloadHash: SigV4.sha256Hex(const []),
        now: DateTime.utc(2013, 5, 24),
      );
      expect(
        h['authorization'],
        'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, '
        'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, '
        'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
      );
      expect(h['x-amz-date'], '20130524T000000Z');
      expect(h.containsKey('host'), isFalse, reason: 'the http client sets the host itself');
    });

    test('a different body, key or time gives a different signature', () {
      String sig(String secret, String hash, DateTime t) => SigV4(accessKeyId: 'K', secretKey: secret)
          .sign(method: 'PUT', host: 'h', path: '/b/k', payloadHash: hash, now: t)['authorization']!;
      final base = sig('s', 'a', DateTime.utc(2026));
      expect(sig('s2', 'a', DateTime.utc(2026)), isNot(base));
      expect(sig('s', 'b', DateTime.utc(2026)), isNot(base));
      expect(sig('s', 'a', DateTime.utc(2027)), isNot(base));
      expect(sig('s', 'a', DateTime.utc(2026)), base, reason: 'the same input, the same signature');
    });

    test('the time is written the way S3 wants', () {
      expect(SigV4.stamp(DateTime.utc(2026, 1, 2, 3, 4, 5)), '20260102T030405Z');
    });
  });

  group('the settings', () {
    test('reading needs only the public address; writing needs the keys too', () {
      expect(const CloudConfig().canRead, isFalse);
      const read = CloudConfig(publicUrl: 'https://pub-1.r2.dev');
      expect(read.canRead, isTrue);
      expect(read.canWrite, isFalse);
      expect(config.canWrite, isTrue);
      expect(config.host, '$_account.r2.cloudflarestorage.com');
      expect(config.urlFor('songs/a.mp3'), 'https://pub-123.r2.dev/songs/a.mp3');
    });

    test('mistakes are explained', () {
      expect(const CloudConfig().problem(), contains('public address'));
      expect(const CloudConfig(publicUrl: 'http://x.dev').problem(), contains('https://'));
      expect(const CloudConfig(publicUrl: 'https://x.dev/').problem(), contains('slash'));
      expect(const CloudConfig(publicUrl: 'https://x.dev').problem(), isNull);
      const ok = CloudConfig(publicUrl: 'https://x.dev', accountId: _account, bucket: 'remotetunes', accessKeyId: 'a', secretKey: 'b');
      expect(ok.problem(forWriting: true), isNull);
      expect(ok.copyWith(accountId: 'short').problem(forWriting: true), contains('account id'));
      expect(ok.copyWith(bucket: 'Bad Bucket').problem(forWriting: true), contains('bucket'));
      expect(ok.copyWith(accessKeyId: ' ').problem(forWriting: true), contains('access key'));
      expect(ok.copyWith(secretKey: '').problem(forWriting: true), contains('secret'));
    });
  });

  group('the catalog', () {
    CloudSong s(String id, String title, {String artist = 'Ann', String album = 'Alpha', String genre = 'Rock', int dur = 200, int size = 1000}) =>
        CloudSong(id: id, title: title, artist: artist, album: album, genre: genre, durationSeconds: dur, audioKey: 'songs/$id.mp3', sizeBytes: size);

    test('is written and read back', () {
      final c = CloudCatalog([
        CloudSong(
            id: 'a',
            title: 'Hello',
            artist: 'Ann',
            album: 'First',
            genre: 'Rock',
            year: 1999,
            track: 3,
            durationSeconds: 201,
            audioKey: 'songs/a.mp3',
            artKey: 'artwork/1.jpg',
            sizeBytes: 4000000,
            added: DateTime.utc(2026, 1, 2)),
      ]);
      final back = CloudCatalog.fromJson(jsonDecode(jsonEncode(c.toJson()))).songs.single;
      expect((back.title, back.artist, back.album, back.genre, back.year, back.track), ('Hello', 'Ann', 'First', 'Rock', 1999, 3));
      expect((back.durationSeconds, back.audioKey, back.artKey, back.sizeBytes), (201, 'songs/a.mp3', 'artwork/1.jpg', 4000000));
      expect(back.added!.toUtc(), DateTime.utc(2026, 1, 2));
    });

    test('damaged entries are skipped, and keys that point elsewhere are never trusted', () {
      final c = CloudCatalog.fromJson({
        'songs': [
          {'id': 'ok', 'title': 'Fine', 'audio': 'songs/ok.mp3'},
          {'id': '', 'title': 'No id', 'audio': 'songs/x.mp3'},
          {'id': 'x', 'title': '  ', 'audio': 'songs/x.mp3'},
          {'id': 'y', 'title': 'No audio'},
          {'id': 'z', 'title': 'Away', 'audio': 'https://evil.example/a.mp3'},
          {'id': 'w', 'title': 'Up', 'audio': '../../etc/passwd'},
          {'id': 'v', 'title': 'Root', 'audio': '/songs/a.mp3'},
          {'id': 'u', 'title': 'Bad art', 'audio': 'songs/u.mp3', 'art': 'https://evil.example/a.jpg'},
          'junk',
          5,
        ],
      });
      expect(c.songs.map((x) => x.id), ['ok', 'u']);
      expect(c.songs.last.artKey, isNull);
      expect(CloudCatalog.fromJson('nonsense').songs, isEmpty);
      expect(CloudCatalog.fromJson({'songs': 'no'}).songs, isEmpty);
    });

    test('adding keeps what was there, a song already there is not added twice, removing takes out', () {
      final c = CloudCatalog([s('a', 'A'), s('b', 'B')]);
      final next = c.changed(add: [s('b', 'Other B'), s('c', 'C')], remove: ['a']);
      expect(next.songs.map((x) => x.id), ['b', 'c']);
      expect(next.songs.first.title, 'B', reason: 'the one that was there stays as it was');
    });

    test('search finds words anywhere in the details, in any order, and filters by genre', () {
      final c = CloudCatalog([
        s('1', 'Hello World', artist: 'Ann', album: 'First', genre: 'Rock'),
        s('2', 'Sunrise', artist: 'Bob', album: 'Morning', genre: 'Jazz'),
        s('3', 'World Tour', artist: 'Bob Marley', genre: 'Reggae'),
      ]);
      expect(c.search('').length, 3);
      expect(c.search('world').map((x) => x.id), ['1', '3']);
      expect(c.search('bob world').map((x) => x.id), ['3']);
      expect(c.search('morning jazz').map((x) => x.id), ['2']);
      expect(c.search('', genre: 'jazz').map((x) => x.id), ['2']);
      expect(c.search('zzz'), isEmpty);
      expect(c.search('').map((x) => x.title), ['Hello World', 'Sunrise', 'World Tour'], reason: 'by title');
    });

    test('genres by how many songs they have', () {
      final c = CloudCatalog([s('1', 'a', genre: 'Rock'), s('2', 'b', genre: 'Jazz'), s('3', 'c', genre: 'Jazz'), s('4', 'd', genre: '')]);
      expect(c.genres.map((g) => '${g.name} ${g.count}'), ['Jazz 2', 'Rock 1']);
    });

    test('the same recording is spotted; another length or title is not', () {
      final c = CloudCatalog([s('1', 'Hello, World!', artist: 'Ann', dur: 200)]);
      expect(c.duplicateOf(title: 'hello world', artist: 'ANN', durationSeconds: 202)?.id, '1');
      expect(c.duplicateOf(title: 'hello world', artist: 'Ann', durationSeconds: 260), isNull);
      expect(c.duplicateOf(title: 'Other', artist: 'Ann', durationSeconds: 200), isNull);
      expect(c.duplicateOf(title: 'hello world', artist: 'Ann', durationSeconds: 0)?.id, '1', reason: 'no length: title and artist decide');
    });

    test('the total size', () {
      expect(CloudCatalog([s('1', 'a', size: 5), s('2', 'b', size: 7)]).totalBytes, 12);
    });
  });

  group('the client', () {
    test('keys are plain paths only', () {
      expect(R2Client.validKey('songs/a-b_1.mp3'), isTrue);
      expect(R2Client.validKey('catalog.json'), isTrue);
      expect(R2Client.validKey('../x'), isFalse);
      expect(R2Client.validKey('songs//a'), isFalse);
      expect(R2Client.validKey('/songs/a'), isFalse);
      expect(R2Client.validKey('songs/a b.mp3'), isFalse);
      expect(R2Client.validKey(''), isFalse);
    });

    test('puts, gets and deletes a file with signed requests', () async {
      final r2 = FakeR2();
      final c = R2Client(config, client: MockClient((r) async => r2.handle(r)), now: () => DateTime.utc(2026));
      await c.putBytes('a/b.txt', utf8.encode('hello'), contentType: 'text/plain');
      expect(utf8.decode((await c.get('a/b.txt'))!), 'hello');
      expect(await c.get('nothing.txt'), isNull);
      await c.putStream('s/big.bin', Stream.fromIterable([List.filled(5, 1), List.filled(5, 2)]), 10, contentType: 'x/y');
      expect(r2.files['s/big.bin'], [1, 1, 1, 1, 1, 2, 2, 2, 2, 2]);
      await c.delete('a/b.txt');
      expect(await c.get('a/b.txt'), isNull);
    });

    test('refused keys, a busy service and no connection each have a plain sentence', () async {
      final r2 = FakeR2()..refuse = true;
      final c = R2Client(config, client: MockClient((r) async => r2.handle(r)));
      await expectLater(c.get('x'), throwsA(predicate((e) => e is R2Exception && e.refused && e.message.contains('keys'))));
      final busy = R2Client(config, client: MockClient((r) async => http.Response('', 503)));
      await expectLater(busy.get('x'), throwsA(predicate((e) => e is R2Exception && e.message.contains('busy'))));
      final off = R2Client(config, client: MockClient((r) async => throw Exception('offline')));
      await expectLater(off.get('x'), throwsA(predicate((e) => e is R2Exception && e.message.contains('internet') && e.status == 0)));
      await expectLater(c.get('../x'), throwsA(isA<R2Exception>()));
    });
  });

  group('the service', () {
    late FakeR2 r2;
    setUp(() => r2 = FakeR2());

    test('reads the catalog from the public address, with no keys; none yet is empty', () async {
      const readOnly = CloudConfig(publicUrl: 'https://pub-123.r2.dev');
      final svc = r2.service(cfg: readOnly);
      expect((await svc.fetchCatalog()).isEmpty, isTrue);
      r2.files['catalog.json'] = utf8.encode(jsonEncode({'songs': [{'id': 'a', 'title': 'T', 'audio': 'songs/a.mp3'}]}));
      expect((await svc.fetchCatalog()).songs.single.title, 'T');
      expect(r2.log.every((l) => !l.contains('remotetunes')), isTrue, reason: 'the signed address was never used');
    });

    test('a wrong public address or no internet is explained', () async {
      const readOnly = CloudConfig(publicUrl: 'https://pub-123.r2.dev');
      final bad = CloudLibraryService(readOnly, client: MockClient((r) async => http.Response('', 500)));
      await expectLater(bad.fetchCatalog(), throwsA(predicate((e) => e is R2Exception && e.message.contains('public address'))));
      final off = CloudLibraryService(readOnly, client: MockClient((r) async => throw Exception('x')));
      await expectLater(off.fetchCatalog(), throwsA(predicate((e) => e is R2Exception && e.message.contains('internet'))));
      await expectLater(CloudLibraryService(const CloudConfig()).fetchCatalog(), throwsA(isA<R2Exception>()));
    });

    test('uploads songs and covers, and lists them in the catalog', () async {
      final art = Uint8List.fromList(List.filled(300, 9));
      final res = await r2.service().upload([
        song('One', art: art),
        song('Two', art: art),
        song('Other', album: 'Beta', genre: 'Jazz', ext: 'flac'),
      ]);
      expect(res.uploaded, hasLength(3));
      expect(res.failed, isEmpty);
      expect(res.stoppedBecause, isNull);
      expect(res.bytes, 900);
      expect(r2.files.keys, containsAll(['songs/id1.mp3', 'songs/id2.mp3', 'songs/id3.flac', 'catalog.json']));
      final covers = r2.files.keys.where((k) => k.startsWith('artwork/')).toList();
      expect(covers, hasLength(1), reason: 'one cover for the whole album');
      final cat = r2.catalog;
      expect(cat.songs.map((x) => x.title), ['One', 'Two', 'Other']);
      expect(cat.songs.first.artKey, covers.single);
      expect(cat.songs.last.artKey, isNull);
      expect(cat.songs.first.sizeBytes, 300);
      expect(cat.songs.first.added, isNotNull);
    });

    test('songs already in the catalog are kept, and the new ones join them', () async {
      await r2.service().upload([song('First')]);
      final svc = r2.service(ids: () => 'later');
      await svc.upload([song('Second')]);
      expect(r2.catalog.songs.map((x) => x.title), ['First', 'Second']);
    });

    test('a cover the catalog already has is not sent again', () async {
      final art = Uint8List.fromList(List.filled(300, 9));
      await r2.service().upload([song('One', art: art)]);
      final key = r2.files.keys.firstWhere((k) => k.startsWith('artwork/'));
      r2.log.clear();
      await r2.service(ids: () => 'second').upload([song('Two', art: art)]);
      expect(r2.log.where((l) => l == 'PUT /remotetunes/$key'), isEmpty);
    });

    test('a song that fails is listed and the rest go on; the catalog holds those that went up', () async {
      // The second song's file fails (the 1st PUT is the song, the 2nd its cover-less next song).
      r2.failPutsFrom = 1;
      r2.failStatus = 500;
      final res = await r2.service().upload([song('Good'), song('Bad'), song('Bad2')]);
      expect(res.uploaded.map((x) => x.title), ['Good']);
      expect(res.failed, hasLength(2));
      expect(res.failed.first, contains('Bad'));
      // The catalog could not be saved either (failing PUTs): that is reported, not hidden.
      expect(res.stoppedBecause, isNotNull);
    });

    test('refused keys stop everything, with what went up before kept', () async {
      final svc = r2.service();
      r2.refuse = true;
      final res = await svc.upload([song('A'), song('B')]);
      expect(res.uploaded, isEmpty);
      expect(res.stoppedBecause, contains('keys'));
    });

    test('with no keys nothing is tried', () async {
      final res = await r2.service(cfg: const CloudConfig(publicUrl: 'https://pub-123.r2.dev')).upload([song('A')]);
      expect(res.stoppedBecause, contains('keys'));
      expect(r2.log, isEmpty);
    });

    test('can be stopped; what went up is listed', () async {
      var asks = 0;
      final res = await r2.service().upload([song('A'), song('B'), song('C')], cancelled: () => asks++ >= 1);
      expect(res.uploaded.map((x) => x.title), ['A']);
      expect(r2.catalog.songs.map((x) => x.title), ['A']);
    });

    test('progress is reported', () async {
      final seen = <String>[];
      await r2.service().upload([song('A'), song('B')], onProgress: (d, t, c) => seen.add('$d/$t ${c ?? ''}'));
      expect(seen, ['0/2 A', '1/2 B', '2/2 ']);
    });

    test('the catalog is saved every ten songs, not only at the end', () async {
      final svc = r2.service();
      final res = await svc.upload([for (var i = 0; i < 12; i++) song('S$i')]);
      expect(res.uploaded, hasLength(12));
      final catalogPuts = r2.log.where((l) => l == 'PUT /remotetunes/catalog.json').length;
      expect(catalogPuts, 2);
      expect(r2.catalog.songs, hasLength(12));
    });

    test('removing takes the songs out of the catalog and deletes their files, and a cover only when unused', () async {
      final art = Uint8List.fromList(List.filled(300, 9));
      final svc = r2.service();
      final res = await svc.upload([song('One', art: art), song('Two', art: art), song('Solo', album: 'Beta', art: Uint8List.fromList(List.filled(300, 5)))]);
      expect(r2.files.keys.where((k) => k.startsWith('artwork/')), hasLength(2));
      await svc.remove([res.uploaded[0]]);
      expect(r2.catalog.songs.map((x) => x.title), ['Two', 'Solo']);
      expect(r2.files.containsKey('songs/id1.mp3'), isFalse);
      expect(r2.files.keys.where((k) => k.startsWith('artwork/')), hasLength(2), reason: 'Two still uses the cover');
      await svc.remove([res.uploaded[1], res.uploaded[2]]);
      expect(r2.catalog.songs, isEmpty);
      expect(r2.files.keys.where((k) => k.startsWith('artwork/')), isEmpty);
      expect(await svc.remove(const []), 0);
    });

    test('testing the keys reads the catalog with them', () async {
      final svc = r2.service();
      expect(await svc.testKeys(), 0);
      await svc.upload([song('A')]);
      expect(await svc.testKeys(), 1);
      r2.refuse = true;
      await expectLater(svc.testKeys(), throwsA(predicate((e) => e is R2Exception && e.refused)));
    });

    test('names of covers are the same for the same album, whatever the capitals', () {
      expect(CloudLibraryService.artKeyFor('Ann', 'First', 'jpg'), CloudLibraryService.artKeyFor(' ann ', 'FIRST', 'jpg'));
      expect(CloudLibraryService.artKeyFor('Ann', 'First', 'jpg'), isNot(CloudLibraryService.artKeyFor('Ann', 'Second', 'jpg')));
      expect(CloudLibraryService.artKeyFor('A', 'B', 'png'), endsWith('.png'));
      expect(CloudLibraryService.artKeyFor('A', 'B', 'webp'), endsWith('.jpg'));
      expect(R2Client.validKey(CloudLibraryService.artKeyFor('A', 'B', 'jpg')), isTrue);
    });
  });
}
