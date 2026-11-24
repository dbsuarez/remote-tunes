import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/features/online_library/jamendo_api.dart';
import 'package:remote_tunes/features/online_library/jamendo_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> track(int id,
        {String audio = 'https://prod-1.storage.jamendo.com/?trackid=1&format=mp32',
        String name = 'Song',
        String artist = 'Band',
        String album = 'Record',
        Object duration = 185,
        String image = 'https://usercontent.jamendo.com?type=album&id=1&width=200',
        String license = 'https://creativecommons.org/licenses/by-nc-sa/3.0/'}) =>
    {
      'id': '$id',
      'name': name,
      'artist_name': artist,
      'album_name': album,
      'duration': duration,
      'audio': audio,
      'image': image,
      'license_ccurl': license,
    };

String ok(List<Map<String, dynamic>> results) => jsonEncode({
      'headers': {'status': 'success', 'code': 0, 'results_count': results.length},
      'results': results,
    });

JamendoApi apiWith(MockClientHandler h) => JamendoApi(
    client: MockClient(h), minGap: Duration.zero, retryDelay: Duration.zero);

void main() {
  test('a search sends the client id and the right filter, nothing else personal', () async {
    final seen = <Uri>[];
    final api = apiWith((r) async {
      seen.add(r.url);
      return http.Response(ok([track(1)]), 200);
    });
    final page = await api.search(
        clientId: 'abc12345', mode: JamendoSearchMode.keyword, text: ' piano ');
    final q = seen.single.queryParameters;
    expect(seen.single.host, 'api.jamendo.com');
    expect(q['client_id'], 'abc12345');
    expect(q['search'], 'piano');
    expect(q['format'], 'json');
    expect(q.keys.toSet(),
        {'client_id', 'format', 'limit', 'offset', 'imagesize', 'audioformat', 'order', 'search'});
    expect(page.tracks.single.title, 'Song');
  });

  test('genre, artist and album searches use their own filters', () async {
    final seen = <Map<String, String>>[];
    final api = apiWith((r) async {
      seen.add(r.url.queryParameters);
      return http.Response(ok([track(1)]), 200);
    });
    await api.search(clientId: 'k', mode: JamendoSearchMode.genre, text: 'Hip Hop');
    await api.search(clientId: 'k', mode: JamendoSearchMode.artist, text: 'Band');
    await api.search(clientId: 'k', mode: JamendoSearchMode.album, text: 'Record');
    expect(seen[0]['tags'], 'hiphop', reason: 'Jamendo genres are one word');
    expect(seen[1]['artist_name'], 'Band');
    expect(seen[2]['album_name'], 'Record');
  });

  test('a track carries title, artist, album, length, art, stream and licence', () async {
    final api = apiWith((r) async => http.Response(ok([track(7, duration: '200')]), 200));
    final t = (await api.search(
            clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x'))
        .tracks
        .single;
    expect(t.id, '7');
    expect(t.artist, 'Band');
    expect(t.album, 'Record');
    expect(t.durationSeconds, 200);
    expect(t.imageUrl, startsWith('https://usercontent.jamendo.com'));
    expect(t.audioUrl, startsWith('https://prod-1.storage.jamendo.com/'));
    expect(t.licenseLabel, 'CC BY-NC-SA 3.0');
  });

  test('licence names', () {
    expect(licenseLabelFor('https://creativecommons.org/licenses/by/4.0/'), 'CC BY 4.0');
    expect(licenseLabelFor('https://creativecommons.org/licenses/by-nd/3.0/'), 'CC BY-ND 3.0');
    expect(licenseLabelFor('https://creativecommons.org/publicdomain/zero/1.0/'), 'CC0');
    // Jamendo really sends http:// links.
    expect(licenseLabelFor('http://creativecommons.org/licenses/by-nc-nd/3.0/'), 'CC BY-NC-ND 3.0');
    expect(licenseLabelFor(null), 'See Jamendo');
    expect(licenseLabelFor('https://example.com/x'), 'See Jamendo');
  });

  test('tracks that are unusable or point away from Jamendo are dropped', () async {
    final api = apiWith((r) async => http.Response(
        ok([
          track(1),
          track(2, audio: ''), // no stream
          track(3, audio: 'https://evil.example/a.mp3'),
          track(4, audio: 'http://prod-1.storage.jamendo.com/a'), // not https
          track(5, name: ''),
          track(6, audio: 'https://jamendo.com.evil.example/a'),
          track(8, image: 'https://evil.example/i.jpg'), // art dropped, track kept
        ]),
        200));
    final tracks = (await api.search(
            clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x'))
        .tracks;
    expect(tracks.map((t) => t.id), ['1', '8']);
    expect(tracks.last.imageUrl, isNull);
  });

  test('an unknown artist or album gets a plain placeholder', () async {
    final api = apiWith(
        (r) async => http.Response(ok([track(1, artist: '', album: '')]), 200));
    final t = (await api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x'))
        .tracks
        .single;
    expect(t.artist, 'Unknown artist');
    expect(t.album, 'Unknown album');
  });

  test('a full page says there may be more', () async {
    final api = apiWith((r) async =>
        http.Response(ok([for (var i = 1; i <= JamendoApi.pageSize; i++) track(i)]), 200));
    final page =
        await api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x');
    expect(page.hasMore, isTrue);
  });

  test('paging asks for the next offset', () async {
    Uri? seen;
    final api = apiWith((r) async {
      seen = r.url;
      return http.Response(ok([]), 200);
    });
    await api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x', offset: 40);
    expect(seen!.queryParameters['offset'], '40');
  });

  test('no internet gives a clear, plain message', () async {
    final api = apiWith((r) async => throw http.ClientException('Failed host lookup'));
    await expectLater(
      api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x'),
      throwsA(isA<JamendoException>()
          .having((e) => e.offline, 'offline', isTrue)
          .having((e) => e.message, 'message', contains('No internet connection'))
          .having((e) => e.message, 'message', contains('Your own music still works'))),
    );
  });

  test('a slow Jamendo is reported as a connection problem', () async {
    final api = JamendoApi(
      client: MockClient((r) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 50),
      minGap: Duration.zero,
      retryDelay: Duration.zero,
    );
    await expectLater(
      api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x'),
      throwsA(isA<JamendoException>().having((e) => e.offline, 'offline', isTrue)),
    );
  });

  test('a refused client id is explained', () async {
    final api = apiWith((r) async => http.Response(
        jsonEncode({
          'headers': {'status': 'failed', 'code': 5, 'error_message': 'Invalid Client Id'},
          'results': [],
        }),
        200));
    await expectLater(
      api.search(clientId: 'bad', mode: JamendoSearchMode.keyword, text: 'x'),
      throwsA(isA<JamendoException>()
          .having((e) => e.badKey, 'badKey', isTrue)
          .having((e) => e.offline, 'offline', isFalse)),
    );
  });

  test('server errors and junk answers do not crash', () async {
    for (final response in [
      http.Response('oops', 503),
      http.Response('not json', 200),
      http.Response('[1,2]', 200),
    ]) {
      final api = apiWith((r) async => response);
      await expectLater(
        api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x'),
        throwsA(isA<JamendoException>()),
      );
    }
  });

  test('an empty search asks for text and makes no request', () async {
    var calls = 0;
    final api = apiWith((r) async {
      calls++;
      return http.Response(ok([]), 200);
    });
    await expectLater(
      api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: '   '),
      throwsA(isA<JamendoException>()),
    );
    expect(calls, 0);
  });

  test('an artist that has no exact match falls back to a wider search', () async {
    final seen = <Map<String, String>>[];
    final api = apiWith((r) async {
      seen.add(r.url.queryParameters);
      if (r.url.queryParameters.containsKey('artist_name')) {
        return http.Response(ok([]), 200);
      }
      return http.Response(
          ok([track(1, artist: 'The Band'), track(2, artist: 'Someone Else')]), 200);
    });
    final page = await api.search(
        clientId: 'k', mode: JamendoSearchMode.artist, text: 'band');
    // The exact search (asked twice, in case Jamendo was throttling), then the
    // wider one.
    expect(seen.length, 3);
    expect(seen.last.containsKey('artist_name'), isFalse);
    expect(page.tracks.map((t) => t.artist), ['The Band']);
  });

  group('Jamendo quietly drops searches that come too fast', () {
    test('an empty first page is asked for once more before giving up', () async {
      var calls = 0;
      final api = apiWith((r) async {
        calls++;
        return http.Response(ok(calls == 1 ? [] : [track(1)]), 200);
      });
      final page =
          await api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'piano');
      expect(calls, 2);
      expect(page.tracks, hasLength(1));
    });

    test('a search that is really empty is asked twice, then reported empty', () async {
      var calls = 0;
      final api = apiWith((r) async {
        calls++;
        return http.Response(ok([]), 200);
      });
      final page =
          await api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'zzzz');
      expect(page.tracks, isEmpty);
      expect(calls, 2);
    });

    test('a later page that is empty is not retried (it is just the end)', () async {
      var calls = 0;
      final api = apiWith((r) async {
        calls++;
        return http.Response(ok([]), 200);
      });
      await api.search(
          clientId: 'k', mode: JamendoSearchMode.keyword, text: 'x', offset: 20);
      expect(calls, 1);
    });

    test('requests are spaced apart', () async {
      final times = <DateTime>[];
      final api = JamendoApi(
        client: MockClient((r) async {
          times.add(DateTime.now());
          return http.Response(ok([track(1)]), 200);
        }),
        minGap: const Duration(milliseconds: 200),
        retryDelay: Duration.zero,
      );
      await api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'a');
      await api.search(clientId: 'k', mode: JamendoSearchMode.keyword, text: 'b');
      expect(times[1].difference(times[0]).inMilliseconds, greaterThanOrEqualTo(190));
    });
  });

  group('client id storage', () {
    test('checks the shape of the id', () {
      expect(JamendoKeyStore.problem(''), isNotNull);
      expect(JamendoKeyStore.problem('has space'), isNotNull);
      expect(JamendoKeyStore.problem('abc'), isNotNull);
      expect(JamendoKeyStore.problem('https://x'), isNotNull);
      expect(JamendoKeyStore.problem('56d30c95'), isNull);
    });

    test('a build-time ID is used until the user saves their own', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsJamendoKeyStore(null, 'built1234');
      expect(await store.load(), 'built1234');
      await store.save('mine5678');
      expect(await store.load(), 'mine5678', reason: 'the user\'s own ID wins');
      await store.clear();
      expect(await store.load(), 'built1234', reason: 'back to the built-in one');
    });

    test('a damaged build-time ID is ignored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PrefsJamendoKeyStore(null, 'not valid!').load(), isNull);
      expect(await PrefsJamendoKeyStore(null, '').load(), isNull);
    });

    test('is saved on this device, read back and removed', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsJamendoKeyStore();
      expect(await store.load(), isNull);
      await store.save(' 56d30c95 ');
      expect(await store.load(), '56d30c95');
      await store.clear();
      expect(await store.load(), isNull);
    });
  });
}
