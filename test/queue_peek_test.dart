import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/controller/controller_views.dart';
import 'package:remote_tunes/features/group/group_card.dart';
import 'package:remote_tunes/features/music/queue_peek.dart';

import 'music_widgets_test.dart' show FakeMusicSource, settleUi;

RemoteQueueItem item(int id, String title, {String artist = 'Band', bool available = true}) =>
    RemoteQueueItem(
      queueItemId: id,
      isCurrent: false,
      song: RemoteSong(
          id: id, title: title, artist: artist, album: 'Album', durationSeconds: 125, available: available),
    );

class _Client extends ControllerClient {
  _Client(this.queue) : super();
  List<RemoteQueueItem> queue;
  final calls = <String>[];

  @override
  Future<QueueSnapshot> getQueue() async => QueueSnapshot(items: queue);

  @override
  Future<void> sendCommand(String action, [Map<String, dynamic> params = const {}]) async =>
      calls.add(action);

  @override
  Future<Map<String, dynamic>> sendCommandForResult(String action,
      [Map<String, dynamic> params = const {}, Duration? timeout]) async {
    calls.add(action);
    return {'queue': QueueSnapshot(items: queue).toJson()};
  }
}

void main() {
  late FakeMusicSource source;

  setUp(() {
    source = FakeMusicSource(queue: [
      item(1, 'Song One'),
      item(2, 'Song Two'),
      item(3, 'Song Three'),
      item(4, 'Song Four'),
      item(5, 'Song Five'),
      item(6, 'Song Six'),
    ]);
  });

  Future<void> open(
    WidgetTester tester, {
    int revision = 1,
    int currentIndex = 0,
    bool enabled = true,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Stack(
          children: [
            const Center(child: Text('the player behind')),
            Positioned.fill(
              child: QueuePeekSheet(
                source: source,
                revision: revision,
                currentIndex: currentIndex,
                enabled: enabled,
              ),
            ),
          ],
        ),
      ),
    ));
    await settleUi(tester);
  }

  /// Slides the sheet up by dragging its handle.
  Future<void> slideUp(WidgetTester tester, {double by = 300}) async {
    await tester.dragFrom(const Offset(200, 785), Offset(0, -by));
    await tester.pumpAndSettle();
  }

  testWidgets('resting: only a handle shows, the player stays clear', (tester) async {
    await open(tester);
    final list = find.descendant(of: find.byType(QueuePeekSheet), matching: find.byType(ListView));
    expect(tester.getSize(list).height, closeTo(QueuePeekSheet.handleHeight, 1));
    expect(find.text('the player behind'), findsOneWidget);
    // The rows are there but below the screen edge: nothing is in the way.
    expect(tester.getTopLeft(find.text('Up next')).dy, greaterThanOrEqualTo(790));
  });

  testWidgets('tapping the handle slides it up, and tapping again tucks it away', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(200, 785));
    await tester.pumpAndSettle();
    expect(find.text('Song Four'), findsOneWidget, reason: 'the next three are showing');
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(QueuePeekSheet), matching: find.byType(ListView));
    expect(tester.getSize(list).height, closeTo(QueuePeekSheet.handleHeight, 1));
  });

  testWidgets('the song playing is marked', (tester) async {
    await open(tester);
    await slideUp(tester);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Song One')).selected, isTrue);
  });

  testWidgets('sliding it up shows the song playing and the next three, then the rest',
      (tester) async {
    await open(tester);
    await slideUp(tester, by: 300);
    for (final t in ['Song One', 'Song Two', 'Song Three', 'Song Four']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // All the way up: everything.
    await tester.dragFrom(const Offset(200, 420), const Offset(0, -500));
    await tester.pumpAndSettle();
    for (final t in ['Song Five', 'Song Six']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('sliding it back down gets it out of the way again', (tester) async {
    await open(tester);
    await slideUp(tester, by: 700);
    expect(find.text('Song Four'), findsOneWidget);
    await tester.dragFrom(const Offset(200, 120), const Offset(0, 800));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(QueuePeekSheet), matching: find.byType(ListView));
    expect(tester.getSize(list).height, closeTo(QueuePeekSheet.handleHeight, 1));
  });

  testWidgets('tapping a song jumps to it', (tester) async {
    await open(tester);
    await slideUp(tester, by: 700);
    await tester.tap(find.text('Song Three'));
    await tester.pump();
    expect(source.calls, ['jump 3']);
  });

  testWidgets('it starts from the song playing now, not from the top of the queue',
      (tester) async {
    await open(tester, currentIndex: 2);
    await slideUp(tester);
    expect(find.text('Song Three'), findsOneWidget, reason: 'the one playing');
    expect(find.text('Song One'), findsNothing, reason: 'already played');
    expect(find.text('3 more · 6 in queue'), findsOneWidget);
  });

  testWidgets('on the last song it says so', (tester) async {
    await open(tester, currentIndex: 5);
    await slideUp(tester);
    expect(find.text('Song Six'), findsOneWidget);
    expect(find.text('Last song'), findsOneWidget);
  });

  testWidgets('it follows the queue: a new revision reads it again', (tester) async {
    await open(tester);
    expect(find.text('5 more · 6 in queue'), findsOneWidget);
    source.queue.add(item(7, 'Song Seven'));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: QueuePeekSheet(source: source, revision: 2, currentIndex: 0),
          ),
        ]),
      ),
    ));
    await settleUi(tester);
    expect(find.text('6 more · 7 in queue'), findsOneWidget);
  });

  testWidgets('an empty queue: nothing is shown at all', (tester) async {
    source.queue.clear();
    await open(tester);
    expect(find.text('Up next'), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets('a queue that cannot be read: it stays out of the way', (tester) async {
    source.failWith = StateError('offline');
    await open(tester);
    expect(find.text('Up next'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('while reconnecting it cannot be used', (tester) async {
    await open(tester, enabled: false);
    await tester.dragFrom(const Offset(200, 785), const Offset(0, -300));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(QueuePeekSheet), matching: find.byType(ListView));
    expect(tester.getSize(list).height, closeTo(QueuePeekSheet.handleHeight, 1),
        reason: 'it did not move');
    expect(source.calls, isEmpty);
  });

  testWidgets('a missing file is flagged', (tester) async {
    source.queue
      ..clear()
      ..add(item(9, 'Ghost', available: false));
    await open(tester);
    await slideUp(tester);
    expect(find.text('File missing from the Player'), findsOneWidget);
  });

  group('on the Now Playing screen', () {
    ControllerClientState connected(int queueLength, {int index = 0}) => ControllerClientState(
          status: ControllerStatus.connected,
          playerName: 'P',
          playback: PlaybackState(
            title: 'Song One',
            artist: 'Band',
            durationSeconds: 125,
            queueLength: queueLength,
            queueIndex: index,
            queueRevision: 1,
          ),
        );

    Future<void> screen(WidgetTester tester, _Client client, ControllerClientState state,
        {Size size = const Size(360, 640)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(body: ControllerDashboard(client: client, state: state)),
        ),
      ));
      await settleUi(tester);
    }

    testWidgets('the peek rests under the player controls on a small phone, without overflow',
        (tester) async {
      final client = _Client([item(1, 'Song One'), item(2, 'Song Two'), item(3, 'Song Three')]);
      await screen(tester, client, connected(3));
      expect(find.text('Up next'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The controls above are still there.
      expect(find.byTooltip('Pause').evaluate().length + find.byTooltip('Play').evaluate().length,
          greaterThan(0));
    });

    testWidgets('the page can still be scrolled to its last card, clear of the sheet',
        (tester) async {
      final client = _Client([item(1, 'Song One'), item(2, 'Song Two')]);
      await screen(tester, client, connected(2));
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
      await tester.pump();
      // The last card of the page (the group card) is reachable.
      expect(find.byType(GroupCard), findsOneWidget);
      final sheetTop = tester.getTopLeft(find.text('Up next')).dy;
      final cardBottom = tester.getBottomLeft(find.byType(GroupCard)).dy;
      expect(cardBottom, lessThan(sheetTop), reason: 'the sheet does not cover it');
    });

    testWidgets('a tap on the player outside the raised sheet slides it back down',
        (tester) async {
      final client = _Client([item(1, 'Song One'), item(2, 'Song Two'), item(3, 'Song Three')]);
      await screen(tester, client, connected(3));
      final restTop = tester.getTopLeft(find.text('Up next')).dy;
      await tester.dragFrom(Offset(180, restTop - 15), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Up next')).dy, lessThan(restTop - 100));
      await tester.tapAt(const Offset(180, 150));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Up next')).dy, closeTo(restTop, 2));
    });

    testWidgets('with nothing queued there is no sheet, and no gap is left', (tester) async {
      final client = _Client([]);
      await screen(tester, client, connected(0));
      expect(find.text('Up next'), findsNothing);
    });
  });
}
