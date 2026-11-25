import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/folder_tree.dart';
import 'package:remote_tunes/features/music/library_search.dart';
import 'package:remote_tunes/features/music/music_browser.dart';
import 'package:remote_tunes/features/music/queue_view.dart';

import 'music_widgets_test.dart' show FakeMusicSource, settleUi, song;

RemoteQueueItem _item(int id, String title) => RemoteQueueItem(
      queueItemId: id,
      isCurrent: false,
      song: RemoteSong(id: id, title: title, artist: 'Ann', album: 'Alpha'),
    );

void main() {
  late FakeMusicSource source;

  setUp(() {
    source = FakeMusicSource(songs: [
      song(1, 'Apple Song', artist: 'Ann', album: 'Alpha'),
      song(2, 'Banana Song', artist: 'Ann', album: 'Alpha'),
      song(3, 'Cherry Song', artist: 'Bob', album: 'Beta'),
    ], queue: [
      _item(10, 'Queued One'),
      _item(11, 'Queued Two'),
    ]);
    source.playlistList.add(const RemotePlaylist(id: 4, name: 'Gym', songCount: 0));
  });

  Future<void> bigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Picks the playlist "Gym" in the sheet that opened.
  Future<void> pickGym(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
  }

  group('the Library lists', () {
    Future<void> openArtists(WidgetTester tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MusicBrowser(source: source)),
      ));
      await settleUi(tester);
      await tester.tap(find.text('Artists'));
      await settleUi(tester);
    }

    testWidgets('an artist row has a menu: add all its songs to a playlist', (tester) async {
      await openArtists(tester);
      await tester.tap(find.byTooltip('More for Ann'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await pickGym(tester);
      expect(source.calls.last, 'addToPlaylist 4 [1, 2]');
      expect(find.text('Added 2 songs to "Gym"'), findsOneWidget);
    });

    testWidgets('the same menu can play them or queue them', (tester) async {
      await openArtists(tester);
      await tester.tap(find.byTooltip('More for Bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(source.calls.last, startsWith('queue [3]'));
    });

    testWidgets('inside an artist, a header button adds all of its songs to a playlist',
        (tester) async {
      await openArtists(tester);
      await tester.tap(find.text('Ann'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Add all to a playlist'));
      await pickGym(tester);
      expect(source.calls.last, 'addToPlaylist 4 [1, 2]');
    });

    testWidgets('an album row has the menu too', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MusicBrowser(source: source))));
      await settleUi(tester);
      await tester.tap(find.text('Albums'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('More for Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await pickGym(tester);
      expect(source.calls.last, 'addToPlaylist 4 [3]');
    });
  });

  group('the queue', () {
    testWidgets('swiping a row to the right adds that song to a playlist', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QueueView(
            source: source,
            revision: 1,
            currentIndex: 0,
            shuffle: false,
            repeat: RepeatMode.off,
            enabled: true,
          ),
        ),
      ));
      await settleUi(tester);
      await tester.drag(find.text('Queued Two'), const Offset(600, 0));
      await pickGym(tester);
      expect(source.calls.last, 'addToPlaylist 4 [11]');
      expect(find.text('Queued Two'), findsOneWidget, reason: 'the row stays in the queue');
      expect(find.byTooltip('Add Queued Two to a playlist'), findsNothing, reason: 'no button any more');
    });
  });

  group('the search', () {
    testWidgets('a song result has a menu with Add to playlist', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: LibrarySearchScreen(source: source))));
      await settleUi(tester);
      await tester.enterText(find.byType(TextField).first, 'Cherry');
      await tester.pump(const Duration(milliseconds: 600));
      await settleUi(tester);
      await tester.tap(find.byTooltip('More for Cherry Song'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await pickGym(tester);
      expect(source.calls.last, 'addToPlaylist 4 [3]');
    });

    testWidgets('an artist result can be added as a whole', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: LibrarySearchScreen(source: source))));
      await settleUi(tester);
      await tester.enterText(find.byType(TextField).first, 'Ann');
      await tester.pump(const Duration(milliseconds: 600));
      await settleUi(tester);
      await tester.tap(find.byTooltip('More for Ann').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await pickGym(tester);
      expect(source.calls.last, 'addToPlaylist 4 [1, 2]');
    });
  });

  group('the folder tree', () {
    testWidgets('a song in a folder has the menu', (tester) async {
      await bigScreen(tester);
      source.treeRoot = const RemoteFolder(id: 1, name: 'Music', songCount: 2);
      source.folderSongs[1] = [1, 2];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FolderTreeView(source: source))));
      await settleUi(tester);
      await tester.tap(find.byTooltip('More for Banana Song'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await pickGym(tester);
      expect(source.calls.last, 'addToPlaylist 4 [2]');
    });
  });
}
