import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/queue_view.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

RemoteQueueItem _item(int queueId, RemoteSong s) =>
    RemoteQueueItem(queueItemId: queueId, isCurrent: false, song: s);

void main() {
  late FakeMusicSource source;

  setUp(() {
    final a = song(1, 'Apple');
    final b = song(2, 'Banana');
    final c = song(3, 'Cherry');
    source = FakeMusicSource(songs: [a, b, c], queue: [_item(10, a), _item(11, b), _item(12, c)]);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(QueueView(
      source: source,
      revision: 1,
      currentIndex: 0,
      shuffle: false,
      repeat: RepeatMode.off,
      enabled: true,
    )));
    await settleUi(tester);
  }

  Future<void> swipeLeft(WidgetTester tester, String title) async {
    await tester.drag(find.text(title), const Offset(-600, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3));
    await settleUi(tester);
  }

  testWidgets('there is no cross button on the rows any more', (tester) async {
    await open(tester);
    expect(find.byTooltip('Remove from queue'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('swiping a song to the left removes it and says so', (tester) async {
    await open(tester);
    await swipeLeft(tester, 'Banana');
    expect(source.calls, ['remove 11']);
    expect(find.text('Banana'), findsNothing);
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Cherry'), findsOneWidget);
    expect(find.text('Removed "Banana Song"'.replaceAll(' Song', '')), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('Undo puts it back where it was', (tester) async {
    await open(tester);
    await swipeLeft(tester, 'Banana');
    await tester.tap(find.text('Undo'));
    await settleUi(tester);
    // Added to the end, then moved back to the middle.
    expect(source.calls, ['remove 11', 'queue [2] next=false', 'move 13->1']);
    expect([for (final i in source.queue) i.song.title], ['Apple', 'Banana', 'Cherry']);
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets('Undo for the last song needs no move', (tester) async {
    await open(tester);
    await swipeLeft(tester, 'Cherry');
    await tester.tap(find.text('Undo'));
    await settleUi(tester);
    expect(source.calls, ['remove 12', 'queue [3] next=false']);
    expect([for (final i in source.queue) i.song.title], ['Apple', 'Banana', 'Cherry']);
  });

  testWidgets('a swipe to the right opens the playlists, and the song stays in the queue',
      (tester) async {
    source.playlistList.add(const RemotePlaylist(id: 4, name: 'Gym', songCount: 0));
    await open(tester);
    await tester.drag(find.text('Banana'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Gym'), findsOneWidget, reason: 'the choice of playlist');
    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
    expect(source.calls.last, 'addToPlaylist 4 [2]');
    expect(find.text('Banana'), findsOneWidget);
    expect(source.calls.where((c) => c.startsWith('remove')), isEmpty);
  });

  testWidgets('cancelling the playlist choice changes nothing', (tester) async {
    source.playlistList.add(const RemotePlaylist(id: 4, name: 'Gym', songCount: 0));
    await open(tester);
    await tester.drag(find.text('Banana'), const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // outside the sheet
    await tester.pumpAndSettle();
    expect(source.calls, isEmpty);
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets('the Online Library tracks in the queue are removed too, but cannot be put back',
      (tester) async {
    source.queue.add(_item(
        20,
        const RemoteSong(
            id: 0, title: 'Stream Track', artist: 'Net', album: 'Web')));
    await open(tester);
    await swipeLeft(tester, 'Stream Track');
    expect(source.calls, ['remove 20']);
    expect(find.text('Undo'), findsNothing, reason: 'a link is not a library song');
    expect(find.text('Removed "Stream Track"'), findsOneWidget);
  });

  group('picking several rows', () {
    testWidgets('a long-press starts it, taps pick more, and the bar counts them', (tester) async {
      await open(tester);
      expect(find.text('3 in queue'), findsOneWidget);
      await tester.longPress(find.text('Apple'));
      await settleUi(tester);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('3 in queue'), findsNothing, reason: 'the bar replaces the usual row');
      await tester.tap(find.text('Cherry'));
      await settleUi(tester);
      expect(find.text('2 selected'), findsOneWidget);
      expect(source.calls, isEmpty, reason: 'taps pick, they do not play');
      await tester.tap(find.text('Cherry'));
      await settleUi(tester);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('the picked songs go into a playlist together', (tester) async {
      source.playlistList.add(const RemotePlaylist(id: 4, name: 'Gym', songCount: 0));
      await open(tester);
      await tester.longPress(find.text('Apple'));
      await settleUi(tester);
      await tester.tap(find.text('Cherry'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Add selected to a playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();
      expect(source.calls.last, 'addToPlaylist 4 [1, 3]');
      expect(find.textContaining('selected'), findsNothing, reason: 'the selection ends');
      expect(find.text('3 in queue'), findsOneWidget, reason: 'the queue is unchanged');
    });

    testWidgets('the picked songs can be taken out of the queue together', (tester) async {
      await open(tester);
      await tester.longPress(find.text('Apple'));
      await settleUi(tester);
      await tester.tap(find.text('Banana'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Remove selected from the queue'));
      await settleUi(tester);
      expect(source.calls, ['remove 10', 'remove 11']);
      expect(find.text('Removed 2 songs from the queue'), findsOneWidget);
      expect(find.text('Cherry'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
    });

    testWidgets('Select all, and Cancel leaves everything as it was', (tester) async {
      await open(tester);
      await tester.longPress(find.text('Banana'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Select all'));
      await settleUi(tester);
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel selection'));
      await settleUi(tester);
      expect(find.textContaining('selected'), findsNothing);
      expect(find.text('3 in queue'), findsOneWidget);
      expect(source.calls, isEmpty);
    });

    testWidgets('while picking, swiping does nothing and there are no drag handles', (tester) async {
      await open(tester);
      expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(3));
      await tester.longPress(find.text('Apple'));
      await settleUi(tester);
      expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
      await tester.drag(find.text('Banana'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(source.calls, isEmpty);
      expect(find.text('Banana'), findsOneWidget);
    });

    testWidgets('a link from the Online Library can be picked and removed, but not put in a playlist',
        (tester) async {
      source.playlistList.add(const RemotePlaylist(id: 4, name: 'Gym', songCount: 0));
      source.queue.add(_item(
          20, const RemoteSong(id: 0, title: 'Stream Track', artist: 'Net', album: 'Web')));
      await open(tester);
      await tester.longPress(find.text('Stream Track'));
      await settleUi(tester);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.playlist_add_rounded)).onPressed,
          isNull,
          reason: 'only a link is picked: nothing for a playlist');
      await tester.tap(find.text('Apple'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Add selected to a playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gym'));
      await tester.pumpAndSettle();
      expect(source.calls.last, 'addToPlaylist 4 [1]', reason: 'the link is left out of the list');
    });
  });

  testWidgets('a link from the Online Library does not swipe to the right (no playlist for it)',
      (tester) async {
    source.queue.add(_item(
        20, const RemoteSong(id: 0, title: 'Stream Track', artist: 'Net', album: 'Web')));
    await open(tester);
    await tester.drag(find.text('Stream Track'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(source.calls, isEmpty);
    expect(find.text('Stream Track'), findsOneWidget);
  });

  testWidgets('works while searching the queue too', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Search the queue'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'cherry');
    await tester.pump();
    await swipeLeft(tester, 'Cherry');
    expect(source.calls, ['remove 12']);
  });

  testWidgets('if the Player refuses, the song comes back and the reason is shown',
      (tester) async {
    source = _Refusing(songs: source.library, queue: source.queue);
    await open(tester);
    await swipeLeft(tester, 'Banana');
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Banana'), findsOneWidget, reason: 'it is still in the queue');
  });
}

/// A Player that does not let anything be removed.
class _Refusing extends FakeMusicSource {
  _Refusing({super.songs, super.queue});

  @override
  Future<void> removeQueueItem(int id) async => throw StateError('no');
}
