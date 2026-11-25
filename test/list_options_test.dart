import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/song_list_look.dart';
import 'package:remote_tunes/core/widgets/playback_widgets.dart' show formatTotalTime;
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/music/music_browser.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

void main() {
  group('the saved looks', () {
    test('a look is written and read back; the standard look is not stored', () {
      final looks = {
        'songs': const ListLook(view: SongListView.grid, titlesOnly: true),
        'album': const ListLook(view: SongListView.noImages),
        'playlist': ListLook.standard,
      };
      final text = encodeListLooks(looks);
      expect(text, isNot(contains('playlist')));
      final back = decodeListLooks(text);
      expect(back['songs'], const ListLook(view: SongListView.grid, titlesOnly: true));
      expect(back['album']!.view, SongListView.noImages);
      expect(back['album']!.titlesOnly, isFalse);
    });

    test('damaged or unknown entries are ignored', () {
      expect(decodeListLooks(null), isEmpty);
      expect(decodeListLooks('nonsense;=x;nokind=grid|1;songs=wat|1').keys, ['songs']);
      expect(decodeListLooks('songs=wat|1')['songs'], const ListLook(titlesOnly: true));
    });

    test('settings remember each kind of list on its own', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SettingsRepository(db);
      expect((await repo.load()).listLooks, isEmpty);
      await repo.setListLook('songs', const ListLook(view: SongListView.oneLine));
      await repo.setListLook('album', const ListLook(titlesOnly: true));
      var l = (await repo.load()).listLooks;
      expect(l['songs']!.view, SongListView.oneLine);
      expect(l['album']!.titlesOnly, isTrue);
      await repo.setListLook('songs', ListLook.standard);
      l = (await repo.load()).listLooks;
      expect(l.containsKey('songs'), isFalse);
      expect(l.containsKey('album'), isTrue);
    });
  });

  group('the song list', () {
    late FakeMusicSource source;
    late Map<String, ListLook> looks;
    final saved = <String, ListLook>{};

    setUp(() {
      saved.clear();
      looks = {};
      source = FakeMusicSource(songs: [
        song(1, 'Apple Song', artist: 'Ann', album: 'Alpha'),
        song(2, 'Banana Song', artist: 'Bob', album: 'Beta'),
      ]);
    });

    Future<void> open(WidgetTester tester, {bool withOptions = true}) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => MusicBrowser(
          source: source,
          looks: looks,
          onLook: withOptions
              ? (k, l) {
                  saved[k] = l;
                  setState(() => looks = {...looks, k: l});
                }
              : null,
        ),
      )));
      await settleUi(tester);
    }

    Future<void> pick(WidgetTester tester, Key key) async {
      await tester.tap(find.byKey(const Key('list-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }

    testWidgets('without List options (the web Controller) there is no button', (tester) async {
      await open(tester, withOptions: false);
      expect(find.byKey(const Key('list-options')), findsNothing);
      expect(find.text('Ann · Alpha'), findsOneWidget);
    });

    testWidgets('the standard look is the list as it always was', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('list-options')), findsOneWidget);
      expect(find.text('Ann · Alpha'), findsOneWidget);
    });

    testWidgets('the sheet is named for the kind of list and lists the six views', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('list-options')));
      await tester.pumpAndSettle();
      expect(find.text('List options: All songs'), findsOneWidget);
      for (final v in SongListView.values) {
        expect(find.byKey(ValueKey('view-${v.name}')), findsOneWidget, reason: v.name);
      }
      expect(find.text('Show titles only'), findsOneWidget);
    });

    testWidgets('Show titles only removes the artist line, and is remembered', (tester) async {
      await open(tester);
      await pick(tester, const Key('titles-only'));
      expect(find.text('Ann · Alpha'), findsNothing);
      expect(find.text('Apple Song'), findsOneWidget);
      expect(saved['songs']!.titlesOnly, isTrue);
    });

    testWidgets('No images drops the cover; 1 line puts the artist beside the title', (tester) async {
      await open(tester);
      await pick(tester, const ValueKey('view-noImages'));
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.text('Ann · Alpha'), findsOneWidget);
      await pick(tester, const ValueKey('view-oneLine'));
      expect(find.text('Apple Song · Ann'), findsOneWidget);
      expect(find.text('Ann · Alpha'), findsNothing);
    });

    testWidgets('Grid shows the songs side by side, and a tap plays one', (tester) async {
      looks = {'songs': const ListLook(view: SongListView.grid)};
      await open(tester);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('Apple Song'), findsOneWidget);
      expect(find.text('Ann'), findsOneWidget);
      await tester.tap(find.text('Banana Song'));
      await settleUi(tester);
      expect(source.calls.any((c) => c.contains('play')), isTrue);
    });

    testWidgets('Grid with titles only has no artist line', (tester) async {
      looks = {'songs': const ListLook(view: SongListView.grid, titlesOnly: true)};
      await open(tester);
      expect(find.text('Ann'), findsNothing);
      expect(find.text('Apple Song'), findsOneWidget);
    });

    testWidgets('a long-press in the grid picks a song', (tester) async {
      looks = {'songs': const ListLook(view: SongListView.grid)};
      await open(tester);
      await tester.longPress(find.text('Apple Song'));
      await settleUi(tester);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('the header says how many songs and how long they play', (tester) async {
      await open(tester);
      expect(tester.widget<Text>(find.byKey(const Key('list-count'))).data, '2 songs | 4:10');
    });

    testWidgets('the header follows the list, not the screen', (tester) async {
      source = FakeMusicSource(songs: [song(1, 'Only Song')]);
      await open(tester);
      expect(tester.widget<Text>(find.byKey(const Key('list-count'))).data, '1 song | 2:05');
    });

    Future<void> pinch(WidgetTester tester, {required bool apart}) async {
      final c = tester.getCenter(find.text('Apple Song'));
      final a = await tester.startGesture(c + const Offset(-40, 0));
      final b = await tester.startGesture(c + const Offset(40, 0));
      await a.moveBy(Offset(apart ? -60 : 30, 0));
      await b.moveBy(Offset(apart ? 60 : -30, 0));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
    }

    testWidgets('two fingers apart make the view bigger, together smaller, and it is remembered',
        (tester) async {
      await open(tester);
      await pinch(tester, apart: true);
      expect(saved['songs']!.view, SongListView.grid);
      expect(find.byType(GridView), findsOneWidget);
      await pinch(tester, apart: false);
      expect(saved['songs']!.view, SongListView.list);
      await pinch(tester, apart: false);
      expect(saved['songs']!.view, SongListView.listSmall);
    });

    testWidgets('one finger still scrolls and taps, and nothing changes', (tester) async {
      await open(tester);
      await tester.drag(find.text('Apple Song'), const Offset(0, -30));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    });

    testWidgets('the button shows it is not the standard look', (tester) async {
      looks = {'songs': const ListLook(view: SongListView.listCompact)};
      await open(tester);
      final icon = tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('list-options')), matching: find.byType(Icon)));
      expect(icon.color, isNotNull);
    });
  });

  test('a long time is written as hours, minutes and seconds', () {
    expect(formatTotalTime(0), '0:00');
    expect(formatTotalTime(59), '0:59');
    expect(formatTotalTime(3725), '1:02:05');
    expect(formatTotalTime(9 * 3600 + 7 * 60 + 26), '9:07:26');
    expect(formatTotalTime(-5), '0:00');
  });

  test('the library adds up how long a list plays', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = LibraryRepository(db);
    await repo.addSong(title: 'A', artist: 'X', album: 'Y', filePath: '/m/a.mp3', durationSeconds: 100);
    await repo.addSong(title: 'B', artist: 'X', album: 'Y', filePath: '/m/b.mp3', durationSeconds: 250);
    await repo.addSong(title: 'C', artist: 'Z', album: 'W', filePath: '/m/c.mp3');
    expect((await repo.songs()).totalSeconds, 350);
    expect((await repo.songs(artist: 'X')).totalSeconds, 350);
    expect((await repo.songs(artist: 'Z')).totalSeconds, 0);
    expect((await repo.songs(limit: 1)).totalSeconds, 350, reason: 'the whole list, not the page');
  });

  test('the zoom steps along the ladder and stops at the ends', () {
    expect(zoomView(SongListView.list, bigger: true), SongListView.grid);
    expect(zoomView(SongListView.grid, bigger: true), SongListView.grid);
    expect(zoomView(SongListView.list, bigger: false), SongListView.listSmall);
    expect(zoomView(SongListView.oneLine, bigger: false), SongListView.oneLine);
    expect(zoomView(SongListView.noImages, bigger: true), SongListView.listSmall);
    expect(zoomView(SongListView.noImages, bigger: false), SongListView.oneLine);
  });
}
