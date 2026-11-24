import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/widgets/edge_swipe.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/controller/controller_views.dart';

import 'music_widgets_test.dart' show settleUi;

class _Client extends ControllerClient {
  _Client() : super();

  @override
  Future<QueueSnapshot> getQueue() async => QueueSnapshot(items: [
        for (var i = 1; i <= 6; i++)
          RemoteQueueItem(
            queueItemId: i,
            isCurrent: false,
            song: RemoteSong(id: i, title: 'Song $i', artist: 'Band', album: 'A', durationSeconds: 100),
          ),
      ]);

  @override
  Future<LibraryPage<RemoteSong>> songs({
    String query = '',
    String? artist,
    String? album,
    String? view,
    int? playlistId,
    int? folderId,
    int offset = 0,
    int limit = 50,
  }) async =>
      const LibraryPage(items: [], total: 0, offset: 0);
}

void main() {
  group('the edge strips', () {
    Future<void> pump(WidgetTester tester,
        {VoidCallback? left, VoidCallback? right, VoidCallback? onTap, bool enabled = true}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EdgeSwipe(
            enabled: enabled,
            onFromLeft: left,
            onFromRight: right,
            child: Center(
              child: ElevatedButton(onPressed: onTap ?? () {}, child: const Text('middle')),
            ),
          ),
        ),
      ));
    }

    testWidgets('a swipe in from the left edge counts', (tester) async {
      var n = 0;
      await pump(tester, left: () => n++);
      await tester.dragFrom(const Offset(8, 400), const Offset(120, 0));
      expect(n, 1);
    });

    testWidgets('a swipe in from the right edge counts', (tester) async {
      var n = 0;
      await pump(tester, right: () => n++);
      await tester.dragFrom(const Offset(392, 400), const Offset(-120, 0));
      expect(n, 1);
    });

    testWidgets('a swipe the wrong way, or too short, does nothing', (tester) async {
      var l = 0, r = 0;
      await pump(tester, left: () => l++, right: () => r++);
      await tester.dragFrom(const Offset(8, 400), const Offset(-60, 0));
      await tester.dragFrom(const Offset(392, 400), const Offset(60, 0));
      await tester.dragFrom(const Offset(8, 400), const Offset(15, 0));
      expect([l, r], [0, 0]);
    });

    testWidgets('a swipe in the middle of the screen does nothing', (tester) async {
      var n = 0;
      await pump(tester, left: () => n++, right: () => n++);
      await tester.dragFrom(const Offset(200, 400), const Offset(150, 0));
      await tester.dragFrom(const Offset(200, 400), const Offset(-150, 0));
      expect(n, 0);
    });

    testWidgets('one swipe counts once, however far it goes', (tester) async {
      var n = 0;
      await pump(tester, left: () => n++);
      await tester.dragFrom(const Offset(8, 400), const Offset(300, 0));
      expect(n, 1);
    });

    testWidgets('taps still reach the page underneath', (tester) async {
      var taps = 0;
      await pump(tester, left: () {}, right: () {}, onTap: () => taps++);
      await tester.tap(find.text('middle'));
      expect(taps, 1);
    });

    testWidgets('switched off, there are no strips', (tester) async {
      var n = 0;
      await pump(tester, left: () => n++, enabled: false);
      await tester.dragFrom(const Offset(8, 400), const Offset(150, 0));
      expect(n, 0);
    });
  });

  group('on the Now Playing screen', () {
    final state = ControllerClientState(
      status: ControllerStatus.connected,
      playerName: 'P',
      playback: const PlaybackState(
        title: 'Song 1',
        artist: 'Band',
        durationSeconds: 100,
        queueLength: 6,
        queueIndex: 0,
        queueRevision: 1,
      ),
    );

    Future<void> screen(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(body: ControllerDashboard(client: _Client(), state: state)),
        ),
      ));
      await settleUi(tester);
    }

    testWidgets('swiping in from the right edge raises the queue, twice for all of it',
        (tester) async {
      await screen(tester);
      expect(find.text('Song 4'), findsNothing);
      await tester.dragFrom(const Offset(394, 300), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(find.text('Song 4'), findsOneWidget, reason: 'the next three are showing');
      await tester.dragFrom(const Offset(394, 300), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(find.text('Song 6'), findsOneWidget, reason: 'the whole queue is showing');
    });

    testWidgets('swiping in from the left edge opens the Library', (tester) async {
      await screen(tester);
      expect(find.text('All Songs'), findsNothing);
      await tester.dragFrom(const Offset(6, 300), const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(find.text('All Songs'), findsOneWidget, reason: 'the Library list is showing');
    });

    testWidgets('the normal swipe between tabs still works', (tester) async {
      await screen(tester, width: 520); // (the test font is wide; the queue bar needs room)
      await tester.dragFrom(const Offset(250, 300), const Offset(-200, 0));
      await settleUi(tester);
      // The Queue tab is open: its search button is there.
      expect(find.byTooltip('Search the queue'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // let go of the screen's timers
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
