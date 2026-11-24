import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/features/online_library/jamendo_api.dart';
import 'package:remote_tunes/features/online_library/jamendo_key_store.dart';
import 'package:remote_tunes/features/online_library/online_library_view.dart';

class _MemoryKeys implements JamendoKeyStore {
  _MemoryKeys([this.id]);
  String? id;

  @override
  Future<String?> load() async => id;
  @override
  Future<void> save(String clientId) async => id = clientId.trim();
  @override
  Future<void> clear() async => id = null;
}

Map<String, dynamic> _track(int i, {String name = 'Song'}) => {
      'id': '$i',
      'name': '$name $i',
      'artist_name': 'Band $i',
      'album_name': 'Album $i',
      'duration': 125,
      'audio': 'https://prod-1.storage.jamendo.com/?trackid=$i',
      'license_ccurl': 'https://creativecommons.org/licenses/by-sa/4.0/',
    };

String _ok(List<Map<String, dynamic>> r) => jsonEncode({
      'headers': {'status': 'success', 'code': 0},
      'results': r,
    });

void main() {
  late _MemoryKeys keys;
  late List<Uri> requests;
  late List<String> played;
  late http.Response Function(Uri) respond;
  Object? failWith;

  setUp(() {
    keys = _MemoryKeys('56d30c95');
    requests = [];
    played = [];
    failWith = null;
    respond = (u) => http.Response(_ok([_track(1), _track(2)]), 200);
  });

  Future<void> open(WidgetTester tester, {bool enabled = true}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = JamendoApi(
      client: MockClient((r) async {
        requests.add(r.url);
        if (failWith != null) throw failWith!;
        return respond(r.url);
      }),
      minGap: Duration.zero,
      retryDelay: Duration.zero,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        jamendoKeyStoreProvider.overrideWithValue(keys),
        jamendoApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: OnlineLibraryView(
            enabled: enabled,
            onTrack: (t, {required queue}) async {
              played.add('${queue ? 'queue' : 'play'} ${t.title} | ${t.artist} | ${t.audioUrl}');
            },
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('without a client id it explains how to get one and makes no request',
      (tester) async {
    keys.id = null;
    await open(tester);
    expect(find.textContaining('developer.jamendo.com'), findsOneWidget);
    expect(find.text('Save client ID'), findsOneWidget);
    expect(find.textContaining('kept on this device only'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('a bad client id is refused before saving', (tester) async {
    keys.id = null;
    await open(tester);
    await tester.enterText(find.byType(TextField), 'not valid!');
    await tester.tap(find.text('Save client ID'));
    await tester.pump();
    expect(find.textContaining('only letters and numbers'), findsOneWidget);
    expect(keys.id, isNull);
  });

  testWidgets('saving the id stores it locally and opens the search', (tester) async {
    keys.id = null;
    await open(tester);
    await tester.enterText(find.byType(TextField), '56d30c95');
    await tester.tap(find.text('Save client ID'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(keys.id, '56d30c95');
    expect(find.text('Keyword'), findsOneWidget);
    expect(find.textContaining('Search free Creative Commons music'), findsOneWidget);
    expect(requests, isEmpty, reason: 'nothing is searched until the user does');
  });

  testWidgets('search results show title, artist, album, length and licence',
      (tester) async {
    await open(tester);
    await search(tester, 'piano');
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Band 1 · Album 1'), findsOneWidget);
    expect(find.textContaining('2:05'), findsWidgets);
    expect(find.text('CC BY-SA 4.0'), findsWidgets);
    expect(requests.single.queryParameters['search'], 'piano');
    expect(requests.single.queryParameters['client_id'], '56d30c95');
  });

  testWidgets('the four search kinds are offered and used', (tester) async {
    await open(tester);
    for (final label in ['Keyword', 'Genre', 'Artist', 'Album']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Artist'));
    await tester.pump();
    await search(tester, 'Band 1');
    expect(requests.last.queryParameters['artist_name'], 'Band 1');

    await tester.tap(find.text('Album'));
    await tester.pump();
    await search(tester, 'Album 1');
    expect(requests.last.queryParameters['album_name'], 'Album 1');
  });

  testWidgets('a genre can be picked from quick chips', (tester) async {
    await open(tester);
    await tester.tap(find.text('Genre'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'jazz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests.single.queryParameters['tags'], 'jazz');
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('Play on Player sends the stream link and the details', (tester) async {
    await open(tester);
    await search(tester, 'x');
    await tester.tap(find.byTooltip('Play on Player').first);
    await tester.pump();
    expect(played,
        ['play Song 1 | Band 1 | https://prod-1.storage.jamendo.com/?trackid=1']);
    expect(find.text('Playing on the Player'), findsOneWidget);
  });

  testWidgets('tapping a row plays it too', (tester) async {
    await open(tester);
    await search(tester, 'x');
    await tester.tap(find.text('Song 2'));
    await tester.pump();
    expect(played.single, startsWith('play Song 2'));
  });

  testWidgets('Add to queue sends it as a queue request', (tester) async {
    await open(tester);
    await search(tester, 'x');
    await tester.tap(find.byTooltip('Add to queue').last);
    await tester.pump();
    expect(played.single, startsWith('queue Song 2'));
    expect(find.text("Added to the Player's queue"), findsOneWidget);
  });

  testWidgets('a Player that refuses is explained, not silent', (tester) async {
    await open(tester);
    await search(tester, 'x');
    await tester.pumpWidget(const SizedBox()); // fresh tree below
    // Re-open with a failing action.
    tester.view.physicalSize = const Size(800, 2400);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        jamendoKeyStoreProvider.overrideWithValue(keys),
        jamendoApiProvider.overrideWithValue(
            JamendoApi(
                client: MockClient((r) async => respond(r.url)),
                minGap: Duration.zero,
                retryDelay: Duration.zero)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: OnlineLibraryView(
            onTrack: (t, {required queue}) async =>
                throw StateError('Player offline'),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await search(tester, 'x');
    await tester.tap(find.byTooltip('Play on Player').first);
    await tester.pump();
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
  });

  testWidgets('no internet: a clear message and a way to retry', (tester) async {
    await open(tester);
    failWith = http.ClientException('no route');
    await search(tester, 'piano');
    expect(find.textContaining('No internet connection'), findsOneWidget);
    expect(find.textContaining('Your own music still works'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

    failWith = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Song 1'), findsOneWidget);
  });

  testWidgets('Jamendo refusing the id offers to change it', (tester) async {
    respond = (u) => http.Response(
        jsonEncode({
          'headers': {'status': 'failed', 'code': 5},
          'results': []
        }),
        200);
    await open(tester);
    await search(tester, 'x');
    expect(find.textContaining('did not accept this client ID'), findsOneWidget);
    await tester.tap(find.text('Change client ID'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(keys.id, isNull);
    expect(find.text('Save client ID'), findsOneWidget);
  });

  testWidgets('no results is said plainly', (tester) async {
    respond = (u) => http.Response(_ok([]), 200);
    await open(tester);
    await search(tester, 'zzzz');
    expect(find.text('No tracks found. Try another search.'), findsOneWidget);
  });

  testWidgets('the licence can be read', (tester) async {
    await open(tester);
    await search(tester, 'x');
    await tester.tap(find.text('CC BY-SA 4.0').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('creativecommons.org/licenses/by-sa/4.0'), findsOneWidget);
    expect(find.textContaining('does not download or keep it'), findsOneWidget);
  });

  testWidgets('while reconnecting the controls are disabled', (tester) async {
    await open(tester, enabled: false);
    await tester.tap(find.byType(TextField).first, warnIfMissed: false);
    expect(requests, isEmpty);
  });
}
