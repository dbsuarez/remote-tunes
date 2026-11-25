import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/song_list_look.dart';
import 'package:remote_tunes/features/music/list_options_sheet.dart';
import 'package:remote_tunes/features/music/music_browser.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

void main() {
  group('the compact header setting', () {
    test('is saved with the look, and older saved looks still read', () {
      const look = ListLook(view: SongListView.grid, titlesOnly: true, compactHeader: true);
      expect(ListLook.parse(look.encode()), look);
      expect(ListLook.parse('grid|1'), const ListLook(view: SongListView.grid, titlesOnly: true));
      expect(ListLook.parse('list|0|0').isStandard, isTrue);
      expect(const ListLook(compactHeader: true).isStandard, isFalse);
      expect(decodeListLooks(encodeListLooks({'album': look}))['album'], look);
    });

    Future<void> sheet(WidgetTester tester, String kind) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(ListOptionsSheet(kind: kind, look: ListLook.standard, onChanged: (_) {})));
    }

    testWidgets('the sheet offers it for lists that have a header, not for the others', (tester) async {
      await sheet(tester, 'playlist');
      expect(find.byKey(const Key('compact-header')), findsOneWidget);
      await sheet(tester, 'songs');
      expect(find.byKey(const Key('compact-header')), findsNothing);
    });

    testWidgets('ticking it changes the look', (tester) async {
      ListLook? seen;
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(ListOptionsSheet(kind: 'album', look: ListLook.standard, onChanged: (l) => seen = l)));
      await tester.tap(find.byKey(const Key('compact-header')));
      await tester.pump();
      expect(seen!.compactHeader, isTrue);
    });

    testWidgets('the header of an album page is slimmer: Play all is an icon', (tester) async {
      final source = FakeMusicSource(songs: [song(1, 'A1', album: 'Alpha'), song(2, 'A2', album: 'Alpha')]);
      Future<void> open(ListLook look) async {
        tester.view.physicalSize = const Size(500, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(host(MusicBrowser(
          source: source,
          looks: {'album': look},
          initialTarget: const LibraryTarget(title: 'Alpha', artist: 'Ann', album: 'Alpha'),
        )));
        await settleUi(tester);
      }

      await open(ListLook.standard);
      expect(find.text('Play all'), findsOneWidget);
      await open(const ListLook(compactHeader: true));
      expect(find.text('Play all'), findsNothing);
      expect(find.byTooltip('Play all'), findsOneWidget);
      await tester.tap(find.byTooltip('Play all'));
      await settleUi(tester);
      expect(source.calls.last, startsWith('play [1, 2]'));
    });
  });

  group('the menu inside the Grid view', () {
    late FakeMusicSource source;
    setUp(() => source = FakeMusicSource(songs: [song(1, 'Apple Song'), song(2, 'Banana Song')]));

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        looks: {'songs': const ListLook(view: SongListView.grid)},
        onLook: (_, __) {},
      )));
      await settleUi(tester);
    }

    testWidgets('each cell has a small menu with the same actions as a row', (tester) async {
      await open(tester);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byTooltip('More'), findsNWidgets(2));
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Add to queue'), findsOneWidget);
      expect(find.text('Add to playlist'), findsOneWidget);
      await tester.tap(find.text('Add to queue'));
      await settleUi(tester);
      expect(source.calls.last, 'queue [1] next=false');
    });

    testWidgets('a tap on the cover still plays, and the menu hides while picking', (tester) async {
      await open(tester);
      await tester.tap(find.text('Banana Song'));
      await settleUi(tester);
      expect(source.calls.last, startsWith('play [2]'));
      await tester.longPress(find.text('Apple Song'));
      await settleUi(tester);
      expect(find.byTooltip('More'), findsNothing);
    });
  });

  group('the menu on folders', () {
    late FakeMusicSource source;
    setUp(() {
      source = FakeMusicSource(songs: [for (var i = 1; i <= 5; i++) song(i, 'Song $i')]);
      source.folderList.addAll(const [
        RemoteFolder(id: 1, name: 'Rock', parent: 'Music', songCount: 2),
        RemoteFolder(id: 2, name: 'Jazz', parent: 'Music', songCount: 1),
      ]);
      source.folderSongs[1] = [1, 2];
      source.folderSongs[2] = [3];
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(source: source, homeList: true)));
      await settleUi(tester);
      await tester.tap(find.text('Folders'));
      await settleUi(tester);
    }

    testWidgets('Play, Add to queue and Add to playlist work on the whole folder', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('More for Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await settleUi(tester);
      expect(source.calls.last, startsWith('play [1, 2]'));

      await tester.tap(find.byTooltip('More for Jazz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await settleUi(tester);
      expect(source.calls.last, 'queue [3] next=false');
    });

    testWidgets('the menu goes while folders are being picked, and tapping the row still opens it', (tester) async {
      await open(tester);
      await tester.longPress(find.text('Rock'));
      await tester.pump();
      expect(find.byTooltip('More for Jazz'), findsNothing);
      await tester.tap(find.text('Rock'));
      await tester.pump();
      await tester.tap(find.text('Jazz'));
      await settleUi(tester);
      expect(find.text('Play all'), findsOneWidget);
    });
  });
}
