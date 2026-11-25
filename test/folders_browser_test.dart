import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/music_browser.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

void main() {
  late FakeMusicSource source;

  setUp(() {
    source = FakeMusicSource(songs: [
      for (var i = 1; i <= 9; i++) song(i, 'Song $i'),
    ]);
    // 40 folders, each with one song or so, so the list needs scrolling.
    for (var i = 1; i <= 40; i++) {
      source.folderList.add(RemoteFolder(
          id: i, name: 'Folder ${i.toString().padLeft(2, '0')}', parent: 'Music', songCount: 1));
    }
    source.folderSongs[1] = [1, 2];
    source.folderSongs[2] = [3];
    source.folderSongs[3] = [4, 5];
    source.folderSongs[30] = [9];
  });

  Future<void> openFolders(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(MusicBrowser(source: source, homeList: true)));
    await settleUi(tester);
    await tester.tap(find.text('Folders'));
    await settleUi(tester);
  }

  Color? tint(WidgetTester tester, String name) => tester
      .widget<ListTile>(find.ancestor(of: find.text(name), matching: find.byType(ListTile)))
      .tileColor;

  group('picking several folders', () {
    testWidgets('long-press picks a folder; taps pick more; the bar counts them', (tester) async {
      await openFolders(tester);
      await tester.longPress(find.text('Folder 01'));
      await tester.pump();
      expect(find.text('1 folder selected'), findsOneWidget);
      await tester.tap(find.text('Folder 02'));
      await tester.pump();
      expect(find.text('2 folders selected'), findsOneWidget);
      // Tapping one that is picked puts it back.
      await tester.tap(find.text('Folder 02'));
      await tester.pump();
      expect(find.text('1 folder selected'), findsOneWidget);
    });

    testWidgets('while picking, a tap does not open a folder', (tester) async {
      await openFolders(tester);
      await tester.longPress(find.text('Folder 01'));
      await tester.pump();
      await tester.tap(find.text('Folder 03'));
      await settleUi(tester);
      expect(find.text('Play all'), findsNothing);
      expect(find.text('2 folders selected'), findsOneWidget);
    });

    testWidgets('Cancel puts everything back', (tester) async {
      await openFolders(tester);
      await tester.longPress(find.text('Folder 01'));
      await tester.pump();
      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pump();
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('Add to playlist gives every song of the picked folders', (tester) async {
      await openFolders(tester);
      await tester.longPress(find.text('Folder 01'));
      await tester.pump();
      await tester.tap(find.text('Folder 03'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add selected folders to playlist'));
      await settleUi(tester);
      await tester.pumpAndSettle(); // the sheet slides up
      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Road trip');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settleUi(tester);
      final add = source.calls.firstWhere((c) => c.startsWith('addToPlaylist'));
      // Folder 1 has songs 1 and 2, folder 3 has songs 4 and 5.
      for (final id in [1, 2, 4, 5]) {
        expect(add, contains('$id'), reason: add);
      }
      expect(add.contains('3'), isFalse, reason: 'song 3 is in folder 2, which was not picked');
      expect(find.textContaining('selected'), findsNothing, reason: 'the selection is cleared');
    });

    testWidgets('Add to queue queues those songs', (tester) async {
      await openFolders(tester);
      await tester.longPress(find.text('Folder 02'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add selected folders to queue'));
      await settleUi(tester);
      expect(source.calls.any((c) => c.startsWith('queue') && c.contains('3')), isTrue,
          reason: source.calls.toString());
    });

    testWidgets('Select all picks every folder, not just the ones on screen', (tester) async {
      await openFolders(tester);
      await tester.longPress(find.text('Folder 01'));
      await tester.pump();
      await tester.tap(find.byTooltip('Select all folders'));
      await settleUi(tester);
      expect(find.text('40 folders selected'), findsOneWidget);
    });

    testWidgets('changing to another list drops the picks', (tester) async {
      await openFolders(tester);
      await tester.longPress(find.text('Folder 01'));
      await tester.pump();
      await tester.tap(find.byTooltip('Cancel selection'));
      await tester.pump();
      await tester.tap(find.byTooltip('Back to the Library'));
      await settleUi(tester);
      await tester.tap(find.text('Folders'));
      await settleUi(tester);
      expect(find.textContaining('selected'), findsNothing);
    });
  });

  group('coming back from an opened folder', () {
    testWidgets('the list is where it was and the folder opened last is marked', (tester) async {
      await openFolders(tester);
      // Scroll down to a folder far from the top and open it.
      await tester.dragUntilVisible(
          find.text('Folder 30'), find.byType(ListView).last, const Offset(0, -300));
      await tester.pump();
      expect(tint(tester, 'Folder 30'), isNull, reason: 'nothing is marked yet');
      await tester.tap(find.text('Folder 30'));
      await settleUi(tester);
      expect(find.text('Play all'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await settleUi(tester);
      // Not back at the top: the folder we opened is right there, tinted.
      expect(find.text('Folder 01'), findsNothing, reason: 'still scrolled down');
      expect(find.text('Folder 30'), findsOneWidget);
      expect(tint(tester, 'Folder 30'), isNotNull);
    });

    testWidgets('only the last one opened is marked', (tester) async {
      await openFolders(tester);
      await tester.tap(find.text('Folder 01'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Back'));
      await settleUi(tester);
      expect(tint(tester, 'Folder 01'), isNotNull);
      expect(tint(tester, 'Folder 02'), isNull);
      await tester.tap(find.text('Folder 02'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Back'));
      await settleUi(tester);
      expect(tint(tester, 'Folder 02'), isNotNull);
      expect(tint(tester, 'Folder 01'), isNull);
    });

    testWidgets('a search is still there when you come back', (tester) async {
      await openFolders(tester);
      await tester.enterText(find.byType(TextField).first, 'Folder 0');
      await tester.pump(const Duration(milliseconds: 500));
      await settleUi(tester);
      await tester.tap(find.text('Folder 03'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Back'));
      await settleUi(tester);
      expect(find.text('Folder 10'), findsNothing, reason: 'the filter is kept');
      expect(find.text('Folder 03'), findsOneWidget);
      expect(tint(tester, 'Folder 03'), isNotNull);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'Folder 0');
    });

    testWidgets('the same works for artists and albums', (tester) async {
      source.library
        ..clear()
        ..addAll([song(1, 'A', artist: 'Ann', album: 'One'), song(2, 'B', artist: 'Bob', album: 'Two')]);
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(source: source, homeList: true)));
      await settleUi(tester);
      await tester.tap(find.text('Albums'));
      await settleUi(tester);
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('leaving for another list forgets the mark', (tester) async {
      await openFolders(tester);
      await tester.tap(find.text('Folder 01'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Back'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Back to the Library'));
      await settleUi(tester);
      await tester.tap(find.text('Folders'));
      await settleUi(tester);
      expect(tint(tester, 'Folder 01'), isNull);
    });
  });
}
