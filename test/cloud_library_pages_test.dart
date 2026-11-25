import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/features/cloud/cloud_config_store.dart';
import 'package:remote_tunes/features/cloud/cloud_library_view.dart';
import 'package:remote_tunes/features/cloud/cloud_models.dart';
import 'package:remote_tunes/features/cloud/cloud_service.dart';

import 'cloud_library_view_test.dart' show MemoryCloudStore, entry;
import 'cloud_test.dart' show FakeR2, config;

void main() {
  late FakeR2 r2;
  late List<String> played;
  var refuseWrites = false;
  var ids = 0;

  setUp(() {
    r2 = FakeR2();
    played = [];
    refuseWrites = false;
    ids = 0;
  });

  void catalog(List<Map<String, Object?>> songs, [List<Map<String, Object?>> playlists = const []]) =>
      r2.files['catalog.json'] = utf8.encode(jsonEncode({'version': 1, 'songs': songs, 'playlists': playlists}));

  CloudCatalog saved() => CloudCatalog.fromJson(jsonDecode(utf8.decode(r2.files['catalog.json']!)));

  void usual([List<Map<String, Object?>> playlists = const []]) => catalog([
        {...entry('1', 'Zed Song', artist: 'Ann', album: 'First'), 'track': 2, 'year': 1999},
        {...entry('2', 'Alpha Song', artist: 'Ann', album: 'First'), 'track': 1},
        entry('3', 'Other', artist: 'Ann', album: 'Second'),
        entry('4', 'Solo', artist: 'Bob', album: 'Third'),
      ], playlists);

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
  }

  void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 5));
    });
  }

  Future<void> open(WidgetTester tester, {CloudConfig? cfg, Size size = const Size(500, 1800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        cloudConfigStoreProvider.overrideWithValue(MemoryCloudStore(cfg ?? config)),
        cloudServiceFactoryProvider.overrideWithValue((c) => CloudLibraryService(
              c,
              client: MockClient((r) async => refuseWrites && r.method == 'PUT' ? http.Response('', 403) : r2.handle(r)),
              newId: () => 'list${++ids}',
              now: () => DateTime.utc(2026),
            )),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CloudLibraryView(
            onTrack: (s, url, image, {required queue}) async => played.add('${queue ? 'queue' : 'play'} ${s.title}'),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String name) => tap(tester, find.byKey(ValueKey('cloud-tab-$name')));

  Future<void> menu(WidgetTester tester, String song, String item) async {
    await tap(tester, find.byTooltip('More for $song'));
    await tap(tester, find.text(item));
  }

  /// The song titles of the rows, top to bottom.
  List<String> rows(WidgetTester tester) => [
        for (final t in tester.widgetList<ListTile>(find.byType(ListTile))) (t.title! as Text).data!,
      ];

  group('artists', () {
    screenTest('are listed with how many songs and albums; one opens in album and track order', (tester) async {
      usual();
      await open(tester);
      await tab(tester, 'artists');
      expect(rows(tester), ['Ann', 'Bob']);
      expect(find.text('3 songs · 2 albums'), findsOneWidget);
      expect(find.text('1 song · 1 album'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('cloud-artist-Ann')));
      expect(rows(tester), ['Alpha Song', 'Zed Song', 'Other']);
      await tap(tester, find.byKey(const Key('cloud-play-all')));
      expect(played, ['play Alpha Song', 'queue Zed Song', 'queue Other']);
      await tap(tester, find.byKey(const Key('cloud-back')));
      expect(rows(tester), ['Ann', 'Bob'], reason: 'back to the artists');
    });

    screenTest("the phone's Back button closes the page first", (tester) async {
      usual();
      await open(tester);
      await tab(tester, 'artists');
      await tap(tester, find.byKey(const ValueKey('cloud-artist-Bob')));
      expect(find.byKey(const Key('cloud-back')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloud-back')), findsNothing);
      expect(rows(tester), ['Ann', 'Bob']);
    });
  });

  group('albums', () {
    screenTest('are listed with artist, year and count; one opens in track order', (tester) async {
      usual();
      await open(tester);
      await tab(tester, 'albums');
      expect(rows(tester), ['First', 'Second', 'Third']);
      expect(find.text('Ann · 1999 · 2 songs'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('cloud-album-ann|first')));
      expect(rows(tester), ['Alpha Song', 'Zed Song']);
      await tap(tester, find.byKey(const Key('cloud-queue-all')));
      expect(played, ['queue Alpha Song', 'queue Zed Song']);
    });
  });

  group('editing a song', () {
    screenTest('changes its details in the cloud and in the list', (tester) async {
      usual();
      await open(tester);
      await menu(tester, 'Solo', 'Edit info');
      await tester.enterText(find.byKey(const Key('cloud-edit-title')), 'Solo (Live)');
      await tester.enterText(find.byKey(const Key('cloud-edit-artist')), 'Bobby');
      await tester.enterText(find.byKey(const Key('cloud-edit-genre')), 'Blues');
      await tester.enterText(find.byKey(const Key('cloud-edit-year')), '2004');
      await tester.enterText(find.byKey(const Key('cloud-edit-track')), '7');
      await tap(tester, find.byKey(const Key('cloud-edit-save')));
      await settle(tester);
      expect(find.text('Solo (Live)'), findsOneWidget);
      expect(find.text('Bobby · Third'), findsOneWidget);
      expect(find.byKey(const ValueKey('cloud-genre-Blues')), findsOneWidget);
      final s = saved().songById('4')!;
      expect((s.title, s.artist, s.album, s.genre, s.year, s.track), ('Solo (Live)', 'Bobby', 'Third', 'Blues', 2004, 7));
      expect(s.audioKey, 'songs/4.mp3');
    });

    screenTest('an empty title or a bad number is refused in the dialog; Cancel saves nothing', (tester) async {
      usual();
      await open(tester);
      await menu(tester, 'Solo', 'Edit info');
      await tester.enterText(find.byKey(const Key('cloud-edit-title')), '  ');
      await tap(tester, find.byKey(const Key('cloud-edit-save')));
      expect(find.text('A song needs a title.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('cloud-edit-title')), 'New');
      await tester.enterText(find.byKey(const Key('cloud-edit-year')), '99');
      await tap(tester, find.byKey(const Key('cloud-edit-save')));
      expect(find.textContaining('four digits'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('cloud-edit-year')), '');
      await tester.enterText(find.byKey(const Key('cloud-edit-track')), '0');
      await tap(tester, find.byKey(const Key('cloud-edit-save')));
      expect(find.textContaining('from 1 to 999'), findsOneWidget);
      await tap(tester, find.text('Cancel'));
      expect(saved().songById('4')!.title, 'Solo');
    });

    screenTest('on an artist page, a song moved to another artist leaves the page', (tester) async {
      usual();
      await open(tester);
      await tab(tester, 'artists');
      await tap(tester, find.byKey(const ValueKey('cloud-artist-Bob')));
      await menu(tester, 'Solo', 'Edit info');
      await tester.enterText(find.byKey(const Key('cloud-edit-artist')), 'Ann');
      await tap(tester, find.byKey(const Key('cloud-edit-save')));
      await settle(tester);
      expect(find.text('No songs here any more.'), findsOneWidget);
    });

    screenTest('a refused key is explained and nothing changes', (tester) async {
      usual();
      await open(tester);
      refuseWrites = true;
      await menu(tester, 'Solo', 'Edit info');
      await tester.enterText(find.byKey(const Key('cloud-edit-title')), 'Changed');
      await tap(tester, find.byKey(const Key('cloud-edit-save')));
      await settle(tester);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Solo'), findsOneWidget);
      expect(find.text('Changed'), findsNothing);
    });
  });

  group('playlists', () {
    screenTest('a new empty playlist is made from the Playlists tab', (tester) async {
      usual();
      await open(tester);
      await tab(tester, 'playlists');
      expect(find.textContaining('No playlists yet'), findsOneWidget);
      await tap(tester, find.byKey(const Key('cloud-new-playlist')));
      await tap(tester, find.byKey(const Key('cloud-name-save')));
      expect(find.byKey(const Key('cloud-name-field')), findsOneWidget, reason: 'a name is needed');
      await tester.enterText(find.byKey(const Key('cloud-name-field')), 'Gym');
      await tap(tester, find.byKey(const Key('cloud-name-save')));
      await settle(tester);
      expect(rows(tester), ['Gym']);
      expect(find.text('0 songs'), findsOneWidget);
      expect(saved().playlists.single.name, 'Gym');
    });

    screenTest('a song goes into a new playlist, then into an existing one, and not twice', (tester) async {
      usual();
      await open(tester);
      await menu(tester, 'Solo', 'Add to playlist');
      await tap(tester, find.byKey(const Key('cloud-pl-new')));
      await tester.enterText(find.byKey(const Key('cloud-name-field')), 'Road');
      await tap(tester, find.byKey(const Key('cloud-name-save')));
      await settle(tester);
      expect(saved().playlists.single.songIds, ['4']);
      await menu(tester, 'Other', 'Add to playlist');
      await tap(tester, find.byKey(const ValueKey('cloud-pl-pick-list1')));
      await settle(tester);
      expect(saved().playlists.single.songIds, ['4', '3']);
      expect(find.text('Added to "Road"'), findsOneWidget);
      await menu(tester, 'Other', 'Add to playlist');
      await tap(tester, find.byKey(const ValueKey('cloud-pl-pick-list1')));
      await settle(tester);
      expect(saved().playlists.single.songIds, ['4', '3']);
      expect(find.text('Already in "Road"'), findsOneWidget);
    });

    screenTest('the shown songs go into a playlist together', (tester) async {
      usual([
        {'id': 'p', 'name': 'Mix', 'songs': <String>[]}
      ]);
      await open(tester);
      await tab(tester, 'albums');
      await tap(tester, find.byKey(const ValueKey('cloud-album-ann|first')));
      await tap(tester, find.byKey(const Key('cloud-all-to-playlist')));
      await tap(tester, find.byKey(const ValueKey('cloud-pl-pick-p')));
      await settle(tester);
      expect(saved().playlists.single.songIds, ['2', '1']);
    });

    screenTest('a playlist plays in its order; a song can be taken out', (tester) async {
      usual([
        {'id': 'p', 'name': 'Mix', 'songs': ['4', '1']}
      ]);
      await open(tester);
      await tab(tester, 'playlists');
      await tap(tester, find.byKey(const ValueKey('cloud-playlist-p')));
      expect(rows(tester), ['Solo', 'Zed Song']);
      await tap(tester, find.byKey(const Key('cloud-play-all')));
      expect(played, ['play Solo', 'queue Zed Song']);
      await menu(tester, 'Solo', 'Remove from this playlist');
      await settle(tester);
      expect(rows(tester), ['Zed Song']);
      expect(saved().playlists.single.songIds, ['1']);
      expect(saved().songs, hasLength(4), reason: 'the song stays in the cloud');
    });

    screenTest('a playlist is renamed and deleted', (tester) async {
      usual([
        {'id': 'p', 'name': 'Mix', 'songs': ['4']}
      ]);
      await open(tester);
      await tab(tester, 'playlists');
      await tap(tester, find.byKey(const ValueKey('cloud-playlist-p')));
      await tap(tester, find.byKey(const Key('cloud-playlist-menu')));
      await tap(tester, find.text('Rename'));
      await tester.enterText(find.byKey(const Key('cloud-name-field')), 'Evening');
      await tap(tester, find.byKey(const Key('cloud-name-save')));
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const Key('cloud-page-title'))).data, 'Evening');
      expect(saved().playlists.single.name, 'Evening');
      await tap(tester, find.byKey(const Key('cloud-playlist-menu')));
      await tap(tester, find.text('Delete playlist'));
      await tap(tester, find.byKey(const Key('cloud-pl-delete-confirm')));
      await settle(tester);
      expect(find.byKey(const Key('cloud-back')), findsNothing);
      expect(find.textContaining('No playlists yet'), findsOneWidget);
      expect(saved().playlists, isEmpty);
      expect(saved().songs, hasLength(4));
    });

    screenTest('a deletion that fails stays on the playlist', (tester) async {
      usual([
        {'id': 'p', 'name': 'Mix', 'songs': ['4']}
      ]);
      await open(tester);
      await tab(tester, 'playlists');
      await tap(tester, find.byKey(const ValueKey('cloud-playlist-p')));
      refuseWrites = true;
      await tap(tester, find.byKey(const Key('cloud-playlist-menu')));
      await tap(tester, find.text('Delete playlist'));
      await tap(tester, find.byKey(const Key('cloud-pl-delete-confirm')));
      await settle(tester);
      expect(find.byKey(const Key('cloud-back')), findsOneWidget);
      expect(rows(tester), ['Solo']);
    });
  });

  group('without the keys', () {
    const readOnly = CloudConfig(publicUrl: 'https://pub-123.r2.dev');

    screenTest('artists, albums and playlists can be looked at and played, not changed', (tester) async {
      usual([
        {'id': 'p', 'name': 'Mix', 'songs': ['4']}
      ]);
      await open(tester, cfg: readOnly);
      expect(find.byKey(const Key('cloud-all-to-playlist')), findsNothing);
      await tap(tester, find.byTooltip('More for Solo'));
      expect(find.text('Edit info'), findsNothing);
      expect(find.text('Add to playlist'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tab(tester, 'playlists');
      expect(find.byKey(const Key('cloud-new-playlist')), findsNothing);
      await tap(tester, find.byKey(const ValueKey('cloud-playlist-p')));
      expect(find.byKey(const Key('cloud-playlist-menu')), findsNothing);
      await tap(tester, find.byTooltip('More for Solo'));
      expect(find.text('Remove from this playlist'), findsNothing);
      await tap(tester, find.text('Play'));
      expect(played, ['play Solo']);
    });
  });

  screenTest('fits a narrow phone', (tester) async {
    usual([
      {'id': 'p', 'name': 'A playlist with a very long name that goes on and on', 'songs': ['4']}
    ]);
    await open(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    // The last tab may need a sideways scroll on a screen this narrow.
    await tester.ensureVisible(find.byKey(const ValueKey('cloud-tab-playlists')));
    await tester.pumpAndSettle();
    await tab(tester, 'playlists');
    await tap(tester, find.byKey(const ValueKey('cloud-playlist-p')));
    expect(tester.takeException(), isNull);
    await tap(tester, find.byTooltip('More for Solo'));
    await tap(tester, find.text('Edit info'));
    expect(tester.takeException(), isNull, reason: 'the edit box fits too');
  });
}
