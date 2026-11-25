import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/haptics.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/controller/controller_views.dart';
import 'package:remote_tunes/features/music/now_playing_controls.dart';

import 'music_widgets_test.dart' show settleUi;

class _Client extends ControllerClient {
  _Client() : super();
  final sent = <String>[];
  final params = <Map<String, dynamic>>[];

  @override
  Future<QueueSnapshot> getQueue() async => const QueueSnapshot(items: []);

  @override
  Future<void> sendCommand(String action, [Map<String, dynamic> p = const {}]) async {
    sent.add(action);
    params.add(p);
  }

  @override
  Future<Map<String, dynamic>> sendCommandForResult(String action,
      [Map<String, dynamic> p = const {}, Duration? timeout]) async {
    if (action == RemoteActions.getArt) return const {}; // the cover, not a button
    sent.add(action);
    params.add(p);
    return const {};
  }
}

ControllerClientState state({
  int position = 60,
  bool shuffle = false,
  RepeatMode repeat = RepeatMode.off,
  bool favorite = false,
  String source = 'local_file',
  int? songId = 5,
  bool playing = true,
}) =>
    ControllerClientState(
      status: ControllerStatus.connected,
      playerName: 'P',
      playback: PlaybackState(
        title: 'Killing in the Name',
        artist: 'Rage',
        album: 'Rage Against',
        durationSeconds: 300,
        positionSeconds: position,
        isPlaying: playing,
        queueLength: 12,
        queueIndex: 2,
        shuffleEnabled: shuffle,
        repeatMode: repeat,
        favorite: favorite,
        source: source,
        songId: songId,
      ),
    );

void main() {
  late _Client client;

  setUp(() {
    client = _Client();
    Haptics.enabled = false;
  });

  tearDown(() => Haptics.enabled = true);

  Future<void> open(WidgetTester tester, ControllerClientState s,
      {Size size = const Size(400, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: ControllerDashboard(client: client, state: s)),
      ),
    ));
    await settleUi(tester);
  }

  testWidgets('the big layout: title, artist and album, and where it is in the queue',
      (tester) async {
    await open(tester, state());
    expect(find.text('Killing in the Name'), findsOneWidget);
    expect(find.text('Rage · Rage Against'), findsOneWidget);
    expect(find.text('Track 3 of 12'), findsOneWidget);
    expect(find.text('Now playing'), findsNothing, reason: 'the small card is not used');
  });

  testWidgets('the title is in the accent color', (tester) async {
    await open(tester, state());
    final t = tester.widget<Text>(find.text('Killing in the Name'));
    final primary = Theme.of(tester.element(find.text('Killing in the Name'))).colorScheme.primary;
    expect(t.style?.color, primary);
  });

  testWidgets('the cover is big but never fills a small screen', (tester) async {
    await open(tester, state(), size: const Size(360, 640));
    final art = tester.getSize(find.byType(RemoteArt).first);
    expect(art.width, art.height);
    expect(art.height, lessThanOrEqualTo(640 * 0.42 + 1));
    expect(art.width, greaterThan(120));
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a large phone the cover stops growing', (tester) async {
    await open(tester, state(), size: const Size(600, 1200));
    expect(tester.getSize(find.byType(RemoteArt).first).width, lessThanOrEqualTo(340));
  });

  testWidgets('seek buttons jump 10 seconds back and forward', (tester) async {
    await open(tester, state(position: 60));
    await tester.tap(find.byTooltip('Back 10 seconds'));
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    expect(client.sent, [RemoteActions.seek, RemoteActions.seek]);
    expect(client.params.map((p) => p['positionSeconds']), [50, 70]);
  });

  testWidgets('the jump stays inside the song', (tester) async {
    await open(tester, state(position: 4));
    await tester.tap(find.byTooltip('Back 10 seconds'));
    expect(client.params.single['positionSeconds'], 0);
    client.params.clear();
    await open(tester, state(position: 296));
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    expect(client.params.single['positionSeconds'], 300);
  });

  testWidgets('shuffle, repeat and favorite are right under the title', (tester) async {
    await open(tester, state());
    await tester.tap(find.byTooltip('Shuffle is off'));
    await tester.tap(find.byTooltip('Repeat: Off'));
    await tester.tap(find.byTooltip('Add to favorites'));
    expect(client.sent, [
      RemoteActions.setShuffle,
      RemoteActions.setRepeatMode,
      RemoteActions.setFavorite,
    ]);
    expect(client.params[0]['enabled'], true);
    expect(client.params[1]['mode'], RepeatMode.queue.name);
    expect(client.params[2], {'songId': 5, 'favorite': true});
  });

  testWidgets('repeat steps through all, one, off', (tester) async {
    await open(tester, state(repeat: RepeatMode.queue));
    await tester.tap(find.byTooltip(RegExp('Repeat:')));
    expect(client.params.single['mode'], RepeatMode.one.name);
    client.params.clear();
    await open(tester, state(repeat: RepeatMode.one));
    await tester.tap(find.byTooltip(RegExp('Repeat:')));
    expect(client.params.single['mode'], RepeatMode.off.name);
  });

  testWidgets('what is on shows: shuffle and favorite change their look and words',
      (tester) async {
    await open(tester, state(shuffle: true, favorite: true));
    expect(find.byTooltip('Shuffle is on'), findsOneWidget);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('quick actions give the haptic click', (tester) async {
    Haptics.enabled = true;
    final log = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') log.add('${call.arguments}');
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester, state());
    await tester.tap(find.byTooltip('Shuffle is off'));
    expect(log, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('the speed and the sleep timer are icons in the same row', (tester) async {
    await open(tester, state());
    expect(find.byTooltip('Set playback speed'), findsOneWidget);
    expect(find.byTooltip('Set sleep timer'), findsOneWidget);
    expect(find.text('Sleep timer'), findsNothing, reason: 'no separate card any more');

    await tester.tap(find.byTooltip('Set playback speed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Set sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();
    expect(client.sent, [RemoteActions.setSpeed, RemoteActions.setSleepTimer]);
    expect(client.params[0]['speed'], 1.5);
    expect(client.params[1]['minutes'], 30);
  });

  testWidgets('a speed that is not normal is shown in the row', (tester) async {
    await open(
        tester,
        ControllerClientState(
          status: ControllerStatus.connected,
          playerName: 'P',
          playback: state().playback.copyWith(speed: 1.25),
        ));
    expect(find.text('1.25×'), findsOneWidget);
  });

  testWidgets('a running sleep timer shows its time and can be cancelled', (tester) async {
    await open(
        tester,
        ControllerClientState(
          status: ControllerStatus.connected,
          playerName: 'P',
          playback: state().playback.copyWith(sleepTimerSeconds: 600),
        ));
    expect(find.textContaining(RegExp(r'^(10:00|9:59)$')), findsOneWidget);
    await tester.tap(find.byTooltip('Set sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cancel'));
    await tester.pumpAndSettle();
    expect(client.params.last['minutes'], 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the file format shows between the times', (tester) async {
    await open(
        tester,
        ControllerClientState(
          status: ControllerStatus.connected,
          playerName: 'P',
          playback: state().playback.copyWith(format: '48 kHz · 256 kbps · MP3'),
        ));
    expect(find.text('48 kHz · 256 kbps · MP3'), findsOneWidget);
  });

  testWidgets('controlling another app keeps the sleep timer card', (tester) async {
    await open(
      tester,
      ControllerClientState(
        status: ControllerStatus.connected,
        playerName: 'P',
        playback: const PlaybackState(
            title: 'T', source: 'external', externalApp: 'X', externalEnabled: true),
      ),
    );
    expect(find.text('Sleep timer'), findsOneWidget);
  });

  testWidgets('volume is a button in the quick row; it shows a small vertical slider',
      (tester) async {
    await open(tester, state());
    expect(find.byType(Slider), findsOneWidget, reason: 'only the seek bar until it is pressed');
    await tester.tap(find.byTooltip('Volume'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.text('80%'), findsOneWidget, reason: 'the current volume');
    // The new slider stands up (turned a quarter).
    expect(find.byType(RotatedBox), findsWidgets);
    final volume = tester.widgetList<Slider>(find.byType(Slider)).last;
    volume.onChanged!(0.35);
    await tester.pump(const Duration(milliseconds: 200));
    volume.onChangeEnd!(0.35);
    await tester.pump();
    expect(client.sent, contains(RemoteActions.setVolume));
    expect(client.params.last['volume'], closeTo(0.35, 0.001));
  });

  testWidgets('the volume icon follows the level', (tester) async {
    expect(VolumeButton.iconFor(0), Icons.volume_off_rounded);
    expect(VolumeButton.iconFor(0.3), Icons.volume_down_rounded);
    expect(VolumeButton.iconFor(0.9), Icons.volume_up_rounded);
  });

  testWidgets('the old volume bar is gone from the page', (tester) async {
    await open(tester, state());
    // Only the seek slider is left on the page.
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('an internet track has no favorite, but still has the other actions',
      (tester) async {
    await open(tester, state(songId: -1, source: 'url'));
    expect(find.text('Internet audio'), findsOneWidget);
    expect(find.byTooltip('Shuffle is off'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to favorites'), warnIfMissed: false);
    expect(client.sent, isNot(contains(RemoteActions.setFavorite)));
  });

  testWidgets('controlling another app keeps the small card, with no jump buttons',
      (tester) async {
    await open(
      tester,
      ControllerClientState(
        status: ControllerStatus.connected,
        playerName: 'P',
        playback: const PlaybackState(
          title: 'Their song',
          artist: 'X',
          durationSeconds: 200,
          source: 'external',
          externalApp: 'Some App',
          externalEnabled: true,
        ),
      ),
    );
    expect(find.text('Now playing'), findsOneWidget);
    expect(find.byTooltip('Back 10 seconds'), findsNothing);
    expect(find.byTooltip('Shuffle is off'), findsNothing);
  });

  testWidgets('nothing happens while reconnecting', (tester) async {
    await open(
      tester,
      ControllerClientState(
        status: ControllerStatus.reconnecting,
        playerName: 'P',
        playback: state().playback,
      ),
    );
    await tester.tap(find.byTooltip('Back 10 seconds'), warnIfMissed: false);
    await tester.tap(find.byTooltip('Shuffle is off'), warnIfMissed: false);
    expect(client.sent, isEmpty);
  });
}
