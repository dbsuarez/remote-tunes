import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:remote_tunes/features/cloud/cloud_config_store.dart';
import 'package:remote_tunes/features/cloud/cloud_history.dart';
import 'package:remote_tunes/features/cloud/cloud_library_view.dart';
import 'package:remote_tunes/features/cloud/cloud_models.dart';
import 'package:remote_tunes/features/cloud/cloud_pickers.dart';
import 'package:remote_tunes/features/cloud/cloud_service.dart';

import 'cloud_library_view_test.dart' show MemoryCloudStore, entry;
import 'cloud_test.dart' show FakeR2, config;

class MemoryHistory implements CloudHistoryStore {
  List<String> ids = [];
  CloudSort chosen = CloudSort.title;
  @override
  Future<List<String>> recent() async => [...ids];
  @override
  Future<CloudSort> sort() async => chosen;
  @override
  Future<void> saveRecent(List<String> v) async => ids = [...v];
  @override
  Future<void> saveSort(CloudSort v) async => chosen = v;
}

/// A real (1 by 1) PNG, so the preview can be drawn.
final onePixel = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));

void main() {
  late FakeR2 r2;
  late List<String> played;
  late MemoryHistory history;
  Uint8List? picture;
  var picked = 0;

  setUp(() {
    r2 = FakeR2();
    played = [];
    history = MemoryHistory();
    picture = onePixel;
    picked = 0;
  });

  void catalog([List<Map<String, Object?>> playlists = const []]) => r2.files['catalog.json'] = utf8.encode(jsonEncode({
        'version': 1,
        'songs': [
          {...entry('1', 'Cherry', artist: 'Ann', album: 'First', dur: 100), 'added': '2026-01-01T00:00:00Z'},
          {...entry('2', 'Apple', artist: 'Ann', album: 'First', dur: 300), 'added': '2026-03-01T00:00:00Z'},
          {...entry('3', 'Banana', artist: 'Bob', album: 'Other', dur: 200), 'added': '2026-02-01T00:00:00Z'},
        ],
        'playlists': playlists,
      }));

  CloudCatalog saved() => CloudCatalog.fromJson(jsonDecode(utf8.decode(r2.files['catalog.json']!)));

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

  Future<void> open(WidgetTester tester, {CloudConfig? cfg, Size size = const Size(500, 1800), bool covers = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var n = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        cloudConfigStoreProvider.overrideWithValue(MemoryCloudStore(cfg ?? config)),
        cloudHistoryStoreProvider.overrideWithValue(history),
        if (covers)
          cloudCoverPickerProvider.overrideWithValue(() async {
            picked++;
            return picture;
          }),
        cloudServiceFactoryProvider.overrideWithValue(
            (c) => CloudLibraryService(c, client: MockClient((r) async => r2.handle(r)), newId: () => 'n${++n}')),
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

  Future<void> key(WidgetTester tester, String k) => tap(tester, find.byKey(Key(k)));
  Future<void> row(WidgetTester tester, String id) => tap(tester, find.byKey(ValueKey('cloud-song-$id')));

  Future<void> sortBy(WidgetTester tester, String label) async {
    await key(tester, 'cloud-sort');
    await tap(tester, find.text(label).last);
  }

  List<String> titles(WidgetTester tester) => [
        for (final t in tester.widgetList<ListTile>(find.byType(ListTile))) (t.title! as Text).data!,
      ];

  group('sorting', () {
    screenTest('starts by title, can be changed, and is remembered', (tester) async {
      catalog();
      await open(tester);
      expect(titles(tester), ['Apple', 'Banana', 'Cherry']);
      await sortBy(tester, 'Longest');
      expect(titles(tester), ['Apple', 'Banana', 'Cherry'], reason: '300, 200 and 100 seconds');
      await sortBy(tester, 'Oldest added');
      expect(titles(tester), ['Cherry', 'Banana', 'Apple']);
      expect(history.chosen, CloudSort.oldest);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(titles(tester), ['Cherry', 'Banana', 'Apple']);
    });

    screenTest('Play all follows the order shown', (tester) async {
      catalog();
      await open(tester);
      await sortBy(tester, 'Newest added');
      await key(tester, 'cloud-play-all');
      expect(played, ['play Apple', 'queue Banana', 'queue Cherry']);
    });

    screenTest('Recently played lists what was started here, latest first', (tester) async {
      catalog();
      await open(tester);
      await sortBy(tester, 'Recently played');
      expect(find.textContaining('Songs you start from this screen'), findsOneWidget);
      await sortBy(tester, 'Title');
      await row(tester, '1');
      await row(tester, '3');
      await tester.longPress(find.byKey(const ValueKey('cloud-song-2')));
      await tester.pump();
      await sortBy(tester, 'Recently played');
      expect(titles(tester), ['Banana', 'Cherry'], reason: 'a song only queued is not listed');
      expect(history.ids, ['3', '1']);
    });

    screenTest('what was played before is read back', (tester) async {
      history
        ..ids = ['2', 'gone', '1']
        ..chosen = CloudSort.recent;
      catalog();
      await open(tester);
      expect(titles(tester), ['Apple', 'Cherry']);
    });
  });

  group('picking several', () {
    screenTest('queues or plays what was picked, in the order shown', (tester) async {
      catalog();
      await open(tester);
      await key(tester, 'cloud-select');
      await row(tester, '1');
      await row(tester, '2');
      expect(find.text('2 selected'), findsOneWidget);
      expect(played, isEmpty, reason: 'a tap picks, it does not play');
      await key(tester, 'cloud-sel-queue');
      expect(played, ['queue Apple', 'queue Cherry']);
      expect(find.byKey(const Key('cloud-select-count')), findsNothing);
      played.clear();
      await key(tester, 'cloud-select');
      await key(tester, 'cloud-select-all');
      await key(tester, 'cloud-sel-play');
      expect(played, ['play Apple', 'queue Banana', 'queue Cherry']);
    });

    screenTest('nothing picked offers nothing; Back stops selecting', (tester) async {
      catalog();
      await open(tester);
      await key(tester, 'cloud-select');
      expect(tester.widget<TextButton>(find.byKey(const Key('cloud-sel-queue'))).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloud-select-count')), findsNothing);
      expect(find.byKey(const Key('cloud-select')), findsOneWidget);
    });

    screenTest('goes into a playlist together; cancelling keeps the picks', (tester) async {
      catalog();
      await open(tester);
      await key(tester, 'cloud-select');
      await row(tester, '3');
      await row(tester, '1');
      await key(tester, 'cloud-sel-playlist');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await key(tester, 'cloud-sel-playlist');
      await key(tester, 'cloud-pl-new');
      await tester.enterText(find.byKey(const Key('cloud-name-field')), 'Mix');
      await key(tester, 'cloud-name-save');
      await settle(tester);
      expect(saved().playlists.single.songIds, ['3', '1']);
      expect(find.byKey(const Key('cloud-select-count')), findsNothing);
    });

    screenTest('edits them all at once, only what was typed', (tester) async {
      catalog();
      await open(tester);
      await key(tester, 'cloud-select');
      await row(tester, '1');
      await row(tester, '3');
      await key(tester, 'cloud-sel-edit');
      await key(tester, 'cloud-many-save');
      expect(find.text('Type something to change.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('cloud-many-year')), '12');
      await key(tester, 'cloud-many-save');
      expect(find.textContaining('four digits'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('cloud-many-year')), '2020');
      await tester.enterText(find.byKey(const Key('cloud-many-genre')), 'Pop');
      await key(tester, 'cloud-many-save');
      await settle(tester);
      final c = saved();
      expect([for (final s in c.songs) s.genre], ['Pop', 'Rock', 'Pop']);
      expect([for (final s in c.songs) s.year], [2020, null, 2020]);
      expect([for (final s in c.songs) s.artist], ['Ann', 'Ann', 'Bob']);
    });

    screenTest('takes them out of a playlist', (tester) async {
      catalog([
        {'id': 'p', 'name': 'Mix', 'songs': ['1', '2', '3']}
      ]);
      await open(tester);
      await key(tester, 'cloud-tab-playlists');
      await tap(tester, find.byKey(const ValueKey('cloud-playlist-p')));
      await key(tester, 'cloud-select');
      await row(tester, '1');
      await row(tester, '3');
      await key(tester, 'cloud-sel-unlist');
      await settle(tester);
      expect(saved().playlists.single.songIds, ['2']);
      expect(saved().songs, hasLength(3));
    });
  });

  group('reordering a playlist', () {
    Future<void> openList(WidgetTester tester) async {
      catalog([
        {'id': 'p', 'name': 'Mix', 'songs': ['1', '2', '3']}
      ]);
      await open(tester);
      await key(tester, 'cloud-tab-playlists');
      await tap(tester, find.byKey(const ValueKey('cloud-playlist-p')));
      await key(tester, 'cloud-reorder');
    }

    Future<void> dragFirstToEnd(WidgetTester tester) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('cloud-drag-1'))));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    screenTest('dragging and Save writes the new order', (tester) async {
      await openList(tester);
      await dragFirstToEnd(tester);
      expect(titles(tester), ['Apple', 'Banana', 'Cherry']);
      expect(saved().playlists.single.songIds, ['1', '2', '3'], reason: 'not saved yet');
      await key(tester, 'cloud-order-save');
      await settle(tester);
      expect(saved().playlists.single.songIds, ['2', '3', '1']);
      expect(find.byKey(const Key('cloud-reorder')), findsOneWidget);
      expect(titles(tester), ['Apple', 'Banana', 'Cherry']);
    });

    screenTest('Cancel and Back leave it as it was', (tester) async {
      await openList(tester);
      await dragFirstToEnd(tester);
      await key(tester, 'cloud-order-cancel');
      expect(titles(tester), ['Cherry', 'Apple', 'Banana']);
      await key(tester, 'cloud-reorder');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloud-order-save')), findsNothing);
      expect(find.byKey(const Key('cloud-back')), findsOneWidget, reason: 'still on the playlist');
      expect(saved().playlists.single.songIds, ['1', '2', '3']);
    });
  });

  group('changing a cover', () {
    Future<void> choose(WidgetTester tester, String song) async {
      await tap(tester, find.byTooltip('More for $song'));
      await tap(tester, find.text('Change cover'));
    }

    screenTest('goes to the whole album by default', (tester) async {
      catalog();
      await open(tester);
      await choose(tester, 'Cherry');
      expect(find.text('All 2 songs of "First"'), findsOneWidget);
      await key(tester, 'cloud-cover-save');
      await settle(tester);
      final c = saved();
      expect(c.songById('1')!.artKey, isNotNull);
      expect(c.songById('2')!.artKey, c.songById('1')!.artKey);
      expect(c.songById('3')!.artKey, isNull);
      expect(r2.files[c.songById('1')!.artKey], onePixel);
    });

    screenTest('or only to that song', (tester) async {
      catalog();
      await open(tester);
      await choose(tester, 'Cherry');
      await key(tester, 'cloud-cover-album');
      await key(tester, 'cloud-cover-save');
      await settle(tester);
      expect(saved().songById('1')!.artKey, isNotNull);
      expect(saved().songById('2')!.artKey, isNull);
    });

    screenTest('a file that is not a picture is refused; nothing picked does nothing', (tester) async {
      catalog();
      await open(tester);
      picture = Uint8List.fromList([1, 2, 3, 4, 5]);
      await choose(tester, 'Cherry');
      expect(find.text('Pick a JPG or PNG picture.'), findsOneWidget);
      picture = null;
      await choose(tester, 'Cherry');
      expect(find.byKey(const Key('cloud-cover-save')), findsNothing);
      expect(picked, 2);
      expect(r2.puts, 0);
    });

    screenTest('is not offered where pictures cannot be picked', (tester) async {
      catalog();
      await open(tester, covers: false);
      await tap(tester, find.byTooltip('More for Cherry'));
      expect(find.text('Edit info'), findsOneWidget);
      expect(find.text('Change cover'), findsNothing);
    });
  });

  group('without the keys', () {
    screenTest('sorting and picking to play work; nothing can be changed', (tester) async {
      catalog([
        {'id': 'p', 'name': 'Mix', 'songs': ['1', '2']}
      ]);
      await open(tester, cfg: const CloudConfig(publicUrl: 'https://pub-123.r2.dev'));
      await key(tester, 'cloud-select');
      expect(find.byKey(const Key('cloud-sel-queue')), findsOneWidget);
      expect(find.byKey(const Key('cloud-sel-edit')), findsNothing);
      expect(find.byKey(const Key('cloud-sel-playlist')), findsNothing);
      await key(tester, 'cloud-select-done');
      await key(tester, 'cloud-tab-playlists');
      await tap(tester, find.byKey(const ValueKey('cloud-playlist-p')));
      expect(find.byKey(const Key('cloud-reorder')), findsNothing);
    });
  });

  screenTest('fits a narrow phone', (tester) async {
    catalog([
      {'id': 'p', 'name': 'Mix', 'songs': ['1', '2', '3']}
    ]);
    await open(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await key(tester, 'cloud-select');
    await row(tester, '1');
    expect(tester.takeException(), isNull);
    await key(tester, 'cloud-sel-edit');
    expect(tester.takeException(), isNull);
  });
}
