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

import 'cloud_test.dart' show FakeR2, config;

class MemoryCloudStore implements CloudConfigStore {
  MemoryCloudStore(this.value);
  CloudConfig value;
  @override
  Future<CloudConfig> load() async => value;
  @override
  Future<void> save(CloudConfig c) async => value = c;
  @override
  Future<void> clearKeys() async => value = value.copyWith(accessKeyId: '', secretKey: '');
  @override
  Future<void> clear() async => value = const CloudConfig();
}

Map<String, Object?> entry(String id, String title,
        {String artist = 'Ann', String album = 'Alpha', String genre = 'Rock', int dur = 200, int size = 1048576, String? art}) =>
    {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'duration': dur,
      'audio': 'songs/$id.mp3',
      if (art != null) 'art': art,
      'size': size,
    };

void main() {
  late FakeR2 r2;
  late List<String> played;
  var opened = 0;

  setUp(() {
    r2 = FakeR2();
    played = [];
    opened = 0;
  });

  void catalog(List<Map<String, Object?>> songs) =>
      r2.files['catalog.json'] = utf8.encode(jsonEncode({'version': 1, 'songs': songs}));

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
      await tester.pump(const Duration(seconds: 1));
    });
  }

  Future<void> open(WidgetTester tester, {CloudConfig? cfg, bool enabled = true, http.Response Function(http.Request)? answer}) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        cloudConfigStoreProvider.overrideWithValue(MemoryCloudStore(cfg ?? config)),
        cloudServiceFactoryProvider.overrideWithValue((c) => CloudLibraryService(
              c,
              client: MockClient((r) async => answer != null ? answer(r) : r2.handle(r)),
              newId: () => 'new',
              now: () => DateTime.utc(2026),
            )),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CloudLibraryView(
            enabled: enabled,
            onOpenSettings: () => opened++,
            onTrack: (s, url, image, {required queue}) async => played.add('${queue ? 'queue' : 'play'} ${s.title} $url ${image ?? '-'}'),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  group('before it is set up', () {
    screenTest('says what to do, and the button opens the settings', (tester) async {
      await open(tester, cfg: const CloudConfig());
      expect(find.text('Your own songs in the cloud'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud-open-settings')));
      expect(opened, 1);
      expect(r2.log, isEmpty, reason: 'nothing is asked for');
    });
  });

  group('the songs', () {
    screenTest('are listed with artist, album, length and how much room is used', (tester) async {
      catalog([entry('a', 'Alpha Song', dur: 125), entry('b', 'Beta Song', artist: 'Bob', album: 'Second', genre: 'Jazz')]);
      await open(tester);
      expect(find.text('2 songs · 2 MB of 10.0 GB free'), findsOneWidget);
      expect(find.text('Alpha Song'), findsOneWidget);
      expect(find.text('Ann · Alpha'), findsOneWidget);
      expect(find.text('Bob · Second'), findsOneWidget);
      expect(find.text('2:05'), findsOneWidget);
    });

    screenTest('an empty cloud says how to put songs in', (tester) async {
      await open(tester);
      expect(find.textContaining('Nothing is in the cloud yet'), findsOneWidget);
      expect(find.textContaining('Upload to cloud'), findsOneWidget);
    });

    screenTest('a wrong address is explained, with Try again', (tester) async {
      var fail = true;
      await open(tester, answer: (r) => fail ? http.Response('', 500) : r2.handle(r));
      expect(find.byKey(const Key('cloud-error')), findsOneWidget);
      expect(find.textContaining('public address'), findsOneWidget);
      fail = false;
      catalog([entry('a', 'Alpha Song')]);
      await tester.tap(find.byKey(const Key('cloud-retry')));
      await settle(tester);
      expect(find.text('Alpha Song'), findsOneWidget);
    });

    screenTest('Refresh reads the catalog again', (tester) async {
      catalog([entry('a', 'Alpha Song')]);
      await open(tester);
      expect(find.text('Beta Song'), findsNothing);
      catalog([entry('a', 'Alpha Song'), entry('b', 'Beta Song')]);
      await tester.tap(find.byKey(const Key('cloud-refresh')));
      await settle(tester);
      expect(find.text('Beta Song'), findsOneWidget);
    });
  });

  group('finding songs', () {
    setUp(() => catalog([
          entry('1', 'Hello World', artist: 'Ann', album: 'First', genre: 'Rock'),
          entry('2', 'Sunrise', artist: 'Bob', album: 'Morning', genre: 'Jazz'),
          entry('3', 'World Tour', artist: 'Bob Marley', album: 'Live', genre: 'Reggae'),
        ]));

    screenTest('search takes words in any order from any detail', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('cloud-search')), 'bob world');
      await tester.pump();
      expect(find.text('World Tour'), findsOneWidget);
      expect(find.text('Hello World'), findsNothing);
      await tester.enterText(find.byKey(const Key('cloud-search')), 'zzz');
      await tester.pump();
      expect(find.text('No songs match.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('Sunrise'), findsOneWidget);
    });

    screenTest('genre chips narrow the list, and tapping the chosen one again lets go', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('cloud-genre-Jazz')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cloud-genre-Jazz')));
      await tester.pump();
      expect(find.text('Sunrise'), findsOneWidget);
      expect(find.text('Hello World'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('cloud-genre-Jazz')));
      await tester.pump();
      expect(find.text('Hello World'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cloud-genre-Rock')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cloud-genre-all')));
      await tester.pump();
      expect(find.text('Sunrise'), findsOneWidget);
    });

    screenTest('a search and a genre together', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('cloud-genre-Reggae')));
      await tester.enterText(find.byKey(const Key('cloud-search')), 'sunrise');
      await tester.pump();
      expect(find.text('No songs match.'), findsOneWidget);
    });
  });

  group('playing', () {
    setUp(() => catalog([
          entry('1', 'Hello', art: 'artwork/abc.jpg'),
          entry('2', 'World'),
        ]));

    screenTest('a tap plays with its public link and its cover; a long press queues it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Hello'));
      await tester.pump();
      await tester.longPress(find.text('World'));
      await tester.pump();
      expect(played, [
        'play Hello https://pub-123.r2.dev/songs/1.mp3 https://pub-123.r2.dev/artwork/abc.jpg',
        'queue World https://pub-123.r2.dev/songs/2.mp3 -',
      ]);
    });

    screenTest('the menu plays or queues', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('More for World'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pump();
      await tester.tap(find.byTooltip('More for World'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(played.map((p) => p.split(' ').take(2).join(' ')), ['queue World', 'play World']);
    });

    screenTest('Play all plays the first and queues the rest; Add all queues everything', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('cloud-play-all')));
      await tester.pump();
      expect(played.map((p) => p.split(' ').take(2).join(' ')), ['play Hello', 'queue World']);
      played.clear();
      await tester.tap(find.byKey(const Key('cloud-queue-all')));
      await tester.pump();
      expect(played.map((p) => p.split(' ').take(2).join(' ')), ['queue Hello', 'queue World']);
    });

    screenTest('a failure is shown as a message', (tester) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          cloudConfigStoreProvider.overrideWithValue(MemoryCloudStore(config)),
          cloudServiceFactoryProvider.overrideWithValue((c) => CloudLibraryService(c, client: MockClient((r) async => r2.handle(r)))),
        ],
        child: MaterialApp(
          home: Scaffold(body: CloudLibraryView(onTrack: (s, u, i, {required queue}) async => throw Exception('no player'))),
        ),
      ));
      await settle(tester);
      await tester.tap(find.text('Hello'));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
    });

    screenTest('while reconnecting nothing can be played', (tester) async {
      await open(tester, enabled: false);
      await tester.tap(find.text('Hello'));
      await tester.pump();
      expect(played, isEmpty);
      expect(tester.widget<TextButton>(find.byKey(const Key('cloud-play-all'))).onPressed, isNull);
    });
  });

  group('deleting', () {
    setUp(() => catalog([entry('1', 'Hello'), entry('2', 'World')]));

    screenTest('is offered only where the keys are', (tester) async {
      await open(tester, cfg: const CloudConfig(publicUrl: 'https://pub-123.r2.dev'));
      await tester.tap(find.byTooltip('More for Hello'));
      await tester.pumpAndSettle();
      expect(find.text('Delete from the cloud'), findsNothing);
    });

    screenTest('asks first, then takes the song out of the cloud and the list', (tester) async {
      r2.files['songs/1.mp3'] = [1, 2, 3];
      await open(tester);
      await tester.tap(find.byTooltip('More for Hello'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from the cloud'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Delete "Hello" from the cloud?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud-delete-confirm')));
      await settle(tester);
      await settle(tester);
      expect(find.text('Hello'), findsNothing);
      expect(find.text('World'), findsOneWidget);
      expect(r2.files.containsKey('songs/1.mp3'), isFalse);
      expect(r2.catalogSongTitles, ['World']);
    });

    screenTest('cancelling deletes nothing', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('More for Hello'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete from the cloud'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
    });
  });

  group('a big library', () {
    screenTest('draws the first 300 rows and says to search for the rest', (tester) async {
      catalog([for (var i = 0; i < 320; i++) entry('s$i', 'Song ${i.toString().padLeft(3, '0')}')]);
      await open(tester);
      expect(find.text('320 songs · 320 MB of 10.0 GB free'), findsOneWidget);
      await tester.dragUntilVisible(find.textContaining('Showing the first 300 of 320'), find.byType(ListView).last, const Offset(0, -2000));
      expect(find.textContaining('Showing the first 300 of 320'), findsOneWidget);
    });
  });
}

extension on FakeR2 {
  List<String> get catalogSongTitles =>
      CloudCatalog.fromJson(jsonDecode(utf8.decode(files['catalog.json']!))).songs.map((s) => s.title).toList();
}
