import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/queue_view.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi;

RemoteQueueItem item(int id, String title, String artist, String album) => RemoteQueueItem(
      queueItemId: id,
      isCurrent: false,
      song: RemoteSong(id: id, title: title, artist: artist, album: album),
    );

void main() {
  late FakeMusicSource source;

  setUp(() {
    source = FakeMusicSource(queue: [
      item(10, 'Blue Moon', 'Ann', 'Night'),
      item(11, 'Red Sun', 'Bob', 'Day'),
      item(12, 'Green Hill', 'Ann Marie', 'Spring'),
      item(13, 'Dark Moon Rising', 'Cy', 'Night'),
    ]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host(QueueView(
      source: source,
      revision: 1,
      currentIndex: -1,
      shuffle: false,
      repeat: RepeatMode.off,
      enabled: true,
    )));
    await settleUi(tester);
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  testWidgets('the search button is off for an empty queue', (tester) async {
    source.queue.clear();
    await open(tester);
    final b = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.search_rounded));
    expect(b.onPressed, isNull);
  });

  testWidgets('no search box until asked for', (tester) async {
    await open(tester);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Search the queue'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing narrows the list by title and says how many match', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Search the queue'));
    await tester.pump();
    await search(tester, 'moon');
    expect(find.text('Blue Moon'), findsOneWidget);
    expect(find.text('Dark Moon Rising'), findsOneWidget);
    expect(find.text('Red Sun'), findsNothing);
    expect(find.text('Green Hill'), findsNothing);
    expect(find.text('2 of 4'), findsOneWidget);
  });

  testWidgets('artist and album are searched too, ignoring case', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Search the queue'));
    await tester.pump();
    await search(tester, 'ANN');
    expect(find.text('Blue Moon'), findsOneWidget);
    expect(find.text('Green Hill'), findsOneWidget, reason: 'artist "Ann Marie"');
    expect(find.text('Red Sun'), findsNothing);

    await search(tester, 'night');
    expect(find.text('Blue Moon'), findsOneWidget);
    expect(find.text('Dark Moon Rising'), findsOneWidget);
    expect(find.text('Green Hill'), findsNothing, reason: 'album Spring');
  });

  testWidgets('no match is said plainly', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Search the queue'));
    await tester.pump();
    await search(tester, 'zzzz');
    expect(find.text('No matches in the queue.'), findsOneWidget);
  });

  testWidgets('while searching: no drag handles; tap plays that one; the cross removes it',
      (tester) async {
    await open(tester);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(4));
    await tester.tap(find.byTooltip('Search the queue'));
    await tester.pump();
    await search(tester, 'red');
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);

    await tester.tap(find.text('Red Sun'));
    await settleUi(tester);
    expect(source.calls, ['jump 11'], reason: 'the real queue entry, not its place in the list');

    await tester.drag(find.text('Red Sun'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await settleUi(tester);
    expect(source.calls.last, 'remove 11');
  });

  testWidgets('clearing the text, or closing the search, brings the whole queue back',
      (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Search the queue'));
    await tester.pump();
    await search(tester, 'moon');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Red Sun'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(4));

    await search(tester, 'moon');
    expect(find.text('Red Sun'), findsNothing);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Red Sun'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(4));
  });

  testWidgets('the current song stays marked when it is among the matches', (tester) async {
    await tester.pumpWidget(host(QueueView(
      source: source,
      revision: 1,
      currentIndex: 3, // Dark Moon Rising
      shuffle: false,
      repeat: RepeatMode.off,
      enabled: true,
    )));
    await settleUi(tester);
    await tester.tap(find.byTooltip('Search the queue'));
    await tester.pump();
    await search(tester, 'moon');
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Dark Moon Rising')).selected,
        isTrue);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Blue Moon')).selected, isFalse);
  });

  testWidgets('each queue row shows the artist and the album the song belongs to', (tester) async {
    await open(tester);
    expect(find.text('Ann · Night'), findsOneWidget);
    expect(find.text('Bob · Day'), findsOneWidget);
    expect(find.text('Cy · Night'), findsOneWidget);
  });
}
