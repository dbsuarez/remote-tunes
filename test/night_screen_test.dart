import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/screen_awake.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/controller/controller_views.dart';
import 'package:remote_tunes/features/music/sleep_timer_dialog.dart';

/// A connection that only notes what it is asked.
class _Client extends ControllerClient {
  final sent = <String>[];

  @override
  Future<void> sendCommand(String action, [Map<String, dynamic> params = const {}]) async => sent.add(action);

  @override
  Future<Map<String, dynamic>> sendCommandForResult(String action,
          [Map<String, dynamic> params = const {}, Duration? timeout]) async =>
      const {};

  @override
  Future<QueueSnapshot> getQueue() async => const QueueSnapshot(items: []);
}

void main() {
  testWidgets('the button on the cover opens the night screen, which follows the song', (tester) async {
    final dims = <double?>[];
    final awake = <bool>[];
    ScreenDim.apply = (v) async => dims.add(v);
    ScreenAwake.setFlag = (v) async => awake.add(v);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _Client();
    ControllerClientState song(String title, {bool playing = true, int sleep = 0}) => ControllerClientState(
          status: ControllerStatus.connected,
          playerName: 'P',
          playback: PlaybackState(
              title: title, artist: 'Band', durationSeconds: 100, isPlaying: playing, sleepTimerSeconds: sleep, songId: 1),
        );
    Future<void> show(ControllerClientState state) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: Scaffold(body: ControllerDashboard(client: client, state: state))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await show(song('First'));
    await tester.tap(find.byKey(const Key('night-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('First · Band'), findsOneWidget);
    expect(find.byKey(const Key('night-timer')), findsNothing);
    expect(dims, [0.01]);
    expect(awake, [true]);
    await show(song('Second', playing: false, sleep: 600));
    expect(find.text('Second · Band'), findsOneWidget);
    expect(find.text('Sleep timer: 10 min left'), findsOneWidget);
    expect(find.byKey(const Key('night-play')), findsNothing, reason: 'nothing bright until tapped');
    await tester.tap(find.byKey(const Key('night-screen')));
    await tester.pump();
    for (final key in ['night-previous', 'night-play', 'night-next']) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }
    expect(client.sent, [RemoteActions.previous, RemoteActions.toggle, RemoteActions.next]);
    await tester.pump(const Duration(seconds: 7));
    expect(find.byKey(const Key('night-play')), findsNothing);
    await tester.tap(find.byKey(const Key('night-screen')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('night-leave')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('night-time')), findsNothing);
    expect(dims, [0.01, null]);
    expect(awake, [true, false]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the sleep timer window opens it too, keeping a time only if one was chosen', (tester) async {
    ScreenDim.apply = (v) async {};
    ScreenAwake.setFlag = (v) async {};
    SleepTimerMemory.minutes = 30;
    SleepTimerMemory.finishSong = false;
    SleepTimerMemory.save = null;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _Client();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ControllerDashboard(
            client: client,
            state: const ControllerClientState(
              status: ControllerStatus.connected,
              playerName: 'P',
              playback: PlaybackState(title: 'S', durationSeconds: 10, songId: 1),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    Future<void> open() async {
      await tester.tap(find.byTooltip('Set sleep timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sleep-night')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('night-time')), findsOneWidget);
      expect(find.byKey(const Key('sleep-title')), findsNothing);
      await tester.tap(find.byKey(const Key('night-screen')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('night-leave')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await open();
    expect(client.sent, isEmpty, reason: 'nothing was chosen');
    await tester.tap(find.byTooltip('Set sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play last song to end'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sleep-night')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(client.sent, [RemoteActions.setSleepTimer]);
    expect(find.byKey(const Key('night-time')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('there is room for the cover\'s three buttons on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ControllerDashboard(
            client: _Client(),
            state: const ControllerClientState(
              status: ControllerStatus.connected,
              playerName: 'P',
              playback: PlaybackState(title: 'S', durationSeconds: 10, songId: 1),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('night-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
