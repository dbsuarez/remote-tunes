import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/features/online_library/jamendo_api.dart';
import 'package:remote_tunes/features/online_library/jamendo_home.dart';
import 'package:remote_tunes/features/online_library/jamendo_key_store.dart';
import 'package:remote_tunes/features/online_library/online_library_view.dart';

class _Keys implements JamendoKeyStore {
  _Keys([this.id]);
  String? id;
  @override
  Future<String?> load() async => id;
  @override
  Future<void> save(String clientId) async => id = clientId.trim();
  @override
  Future<void> clear() async => id = null;
}

Map<String, dynamic> _track(int i, String name) => {
      'id': '$i',
      'name': '$name $i',
      'artist_name': 'Band $i',
      'album_name': 'Album $i',
      'duration': 125,
      'audio': 'https://prod-1.storage.jamendo.com/?trackid=$i',
      'license_ccurl': 'https://creativecommons.org/licenses/by-sa/4.0/',
    };

String _ok(List<Map<String, dynamic>> r) =>
    jsonEncode({'headers': {'status': 'success', 'code': 0}, 'results': r});

/// Answers by the `order` that was asked for.
http.Response _byOrder(Uri u) {
  if (u.queryParameters['tags'] != null) {
    return http.Response(_ok([_track(90, 'Genre')]), 200);
  }
  return switch (u.queryParameters['order']) {
    'popularity_week' => http.Response(_ok([_track(1, 'Weekly'), _track(2, 'Weekly')]), 200),
    'popularity_month' => http.Response(_ok([_track(3, 'Monthly')]), 200),
    'releasedate_desc' => http.Response(_ok([_track(4, 'Fresh')]), 200),
    _ => http.Response(_ok([]), 200),
  };
}

JamendoApi _api(List<Uri> log, http.Response Function(Uri) respond, {Object? fail}) => JamendoApi(
      client: MockClient((r) async {
        log.add(r.url);
        if (fail != null) throw fail;
        return respond(r.url);
      }),
      minGap: Duration.zero,
      retryDelay: Duration.zero,
    );

void main() {
  group('the API', () {
    test('each shelf asks Jamendo for its own order, with no search text', () async {
      final log = <Uri>[];
      final api = _api(log, _byOrder);
      for (final s in JamendoShelf.values) {
        final page = await api.browse(clientId: 'abc', shelf: s);
        expect(page.tracks, isNotEmpty, reason: s.title);
      }
      expect([for (final u in log) u.queryParameters['order']],
          ['popularity_week', 'popularity_month', 'releasedate_desc']);
      expect(log.every((u) => !u.queryParameters.containsKey('search')), isTrue);
      expect(log.first.queryParameters['client_id'], 'abc');
    });
  });

  group('a genre shelf', () {
    test('asks for the genre as Jamendo spells it, sorted by the week', () async {
      final log = <Uri>[];
      final api = _api(log, _byOrder);
      await api.browse(clientId: 'abc', shelf: JamendoShelf.week, genre: 'Hip Hop');
      expect(log.single.queryParameters['tags'], 'hiphop');
      expect(log.single.queryParameters['order'], 'popularity_week');
    });

    test('is fetched when first asked for, kept, and fetched again when old or refreshed', () async {
      final log = <Uri>[];
      final api = _api(log, _byOrder);
      var now = DateTime(2026, 1, 1);
      final home = JamendoHome(now: () => now);
      expect(home.genreShelf('rock').loaded, isFalse);
      await home.loadGenre(api, 'abc', 'rock');
      expect(home.genreShelf('rock').tracks.single.title, 'Genre 90');
      await home.loadGenre(api, 'abc', 'rock');
      expect(log, hasLength(1), reason: 'fresh');
      await home.loadGenre(api, 'abc', 'jazz');
      expect(log, hasLength(2), reason: 'each genre on its own');
      now = now.add(const Duration(minutes: 20));
      await home.loadGenre(api, 'abc', 'rock');
      expect(log, hasLength(3), reason: 'old');
      await home.loadGenre(api, 'abc', 'rock', refresh: true);
      expect(log, hasLength(4));
    });

    test('a failure keeps what was there; a new client ID or clear forgets it', () async {
      final log = <Uri>[];
      var fail = false;
      final api = _api(log, (u) => fail ? http.Response('x', 500) : _byOrder(u));
      final home = JamendoHome();
      await home.loadGenre(api, 'abc', 'rock');
      fail = true;
      await home.loadGenre(api, 'abc', 'rock', refresh: true);
      expect(home.genreShelf('rock').tracks, hasLength(1));
      expect(home.genreShelf('rock').error, isNotNull);
      home.clear();
      expect(home.genreShelf('rock').loaded, isFalse);
      fail = false;
      await home.loadGenre(api, 'abc', 'rock');
      await home.loadGenre(api, 'other', 'rock');
      expect(log.length, greaterThanOrEqualTo(4), reason: 'another client ID asks again');
    });
  });

  group('the shelves', () {
    test('load one after another and are kept', () async {
      final log = <Uri>[];
      final api = _api(log, _byOrder);
      final home = JamendoHome();
      await home.load(api, 'abc');
      expect([for (final s in JamendoShelf.values) home.shelf(s).tracks.length], [2, 1, 1]);
      expect(log, hasLength(3));
      await home.load(api, 'abc'); // still fresh: no new requests
      expect(log, hasLength(3));
      await home.load(api, 'abc', refresh: true);
      expect(log, hasLength(6));
    });

    test('they are fetched again when they are old, or the client ID changed', () async {
      final log = <Uri>[];
      final api = _api(log, _byOrder);
      var now = DateTime(2026, 1, 1);
      final home = JamendoHome(now: () => now);
      await home.load(api, 'abc');
      now = now.add(const Duration(minutes: 20));
      await home.load(api, 'abc');
      expect(log, hasLength(6));
      await home.load(api, 'other');
      expect(log, hasLength(9));
    });

    test('with no internet it stops after the first try and says so', () async {
      final log = <Uri>[];
      final api = _api(log, _byOrder, fail: Exception('offline'));
      final home = JamendoHome();
      await home.load(api, 'abc');
      expect(log, hasLength(1), reason: 'the others would fail the same way');
      expect(home.shelf(JamendoShelf.week).error!.offline, isTrue);
      expect(home.anyLoaded, isFalse);
    });

    test('a shelf that fails keeps what it had', () async {
      final log = <Uri>[];
      var fail = false;
      final api = _api(log, (u) => fail ? http.Response('x', 500) : _byOrder(u));
      final home = JamendoHome();
      await home.load(api, 'abc');
      fail = true;
      await home.load(api, 'abc', refresh: true);
      expect(home.shelf(JamendoShelf.week).tracks, hasLength(2));
      expect(home.shelf(JamendoShelf.week).error, isNotNull);
    });
  });

  group('the home screen', () {
    late List<Uri> log;
    late List<String> played;
    late http.Response Function(Uri) respond;

    setUp(() {
      log = [];
      played = [];
      respond = _byOrder;
    });

    Future<void> open(WidgetTester tester, {bool suggestions = true}) async {
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          jamendoKeyStoreProvider.overrideWithValue(_Keys('abc')),
          jamendoApiProvider.overrideWithValue(_api(log, (u) => respond(u))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OnlineLibraryView(
              suggestions: suggestions,
              onTrack: (t, {required queue}) async {
                played.add('${queue ? "queue" : "play"} ${t.title}');
              },
            ),
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('shows the shelves before any search', (tester) async {
      await open(tester);
      for (final t in ['Popular this week', 'Popular this month', 'Newest releases']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Weekly 1'), findsOneWidget);
      expect(find.text('Fresh 4'), findsOneWidget);
      expect(find.text('Top tracks by genre'), findsOneWidget);
    });

    testWidgets('tap plays a cover, press and hold queues it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Weekly 1'));
      await tester.pump();
      await tester.longPress(find.text('Monthly 3'));
      await tester.pump();
      expect(played, ['play Weekly 1', 'queue Monthly 3']);
    });

    testWidgets('Play all plays the first and queues the rest', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Play all of "Popular this week"'));
      await tester.pump();
      expect(played, ['play Weekly 1', 'queue Weekly 2']);
    });

    testWidgets('Add all queues every track of a shelf', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Add all of "Popular this week" to the queue'));
      await tester.pump();
      expect(played, ['queue Weekly 1', 'queue Weekly 2']);
    });

    testWidgets('a genre chip lists the top tracks of that genre', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(ActionChip, 'jazz'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Genre 90'), findsOneWidget);
      final last = log.last.queryParameters;
      expect(last['tags'], 'jazz');
      expect(last['order'], 'popularity_total');
    });

    testWidgets('a Top this week shelf for one genre, with chips to pick the genre', (tester) async {
      await open(tester);
      expect(find.text('Top this week by genre'), findsOneWidget);
      expect(find.text('Popular this week · pop'), findsOneWidget);
      expect(find.text('Genre 90'), findsOneWidget);
      final first = log.last.queryParameters;
      expect((first['tags'], first['order']), ('pop', 'popularity_week'));
      await tester.ensureVisible(find.byKey(const ValueKey('week-jazz')));
      await tester.tap(find.byKey(const ValueKey('week-jazz')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Popular this week · jazz'), findsOneWidget);
      final jazz = log.last.queryParameters;
      expect((jazz['tags'], jazz['order']), ('jazz', 'popularity_week'));
    });

    testWidgets('the shelves refresh by themselves when they are old', (tester) async {
      var now = DateTime(2026, 1, 1);
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          jamendoKeyStoreProvider.overrideWithValue(_Keys('abc')),
          jamendoApiProvider.overrideWithValue(_api(log, (u) => respond(u))),
          jamendoHomeProvider.overrideWithValue(JamendoHome(now: () => now)),
        ],
        child: MaterialApp(
          home: Scaffold(body: OnlineLibraryView(suggestions: true, onTrack: (t, {required queue}) async {})),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      final first = log.length;
      expect(first, 4, reason: 'three shelves and the genre shelf');
      // Five minutes pass: still fresh, nothing new.
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(log, hasLength(first));
      // Twenty minutes: old, so the next check fetches again, with no pull down.
      now = now.add(const Duration(minutes: 15));
      await tester.pump(const Duration(minutes: 5));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(log.length, 2 * first);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('switched off, it stays blank until a search', (tester) async {
      await open(tester, suggestions: false);
      expect(find.text('Popular this week'), findsNothing);
      expect(log, isEmpty, reason: 'nothing is fetched');
      expect(find.textContaining('Search free Creative Commons music'), findsOneWidget);
    });

    testWidgets('with no internet it says so and offers Try again', (tester) async {
      respond = (u) => throw Exception('offline');
      await open(tester);
      expect(find.textContaining('No internet connection'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
