import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/music/sleep_timer_dialog.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/sleep_timer.dart';

import 'helpers/fake_audio_backend.dart';

void main() {
  setUp(() {
    SleepTimerMemory.minutes = 30;
    SleepTimerMemory.finishSong = false;
    SleepTimerMemory.save = null;
  });

  group('the dial', () {
    Future<List<SleepChoice?>> open(WidgetTester tester,
        {int secondsLeft = 0, bool waiting = false, bool offer = true, Size size = const Size(400, 900)}) async {
      final answers = <SleepChoice?>[];
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(await showSleepTimerDialog(context,
                secondsLeft: secondsLeft, waiting: waiting, offerFinishSong: offer)),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return answers;
    }

    int shown(WidgetTester tester) =>
        int.parse(tester.widget<Text>(find.byKey(const Key('sleep-minutes'))).data!.split(' ').first);

    /// Turns the knob by [turns] of a circle (negative is backwards), starting at the top.
    Future<void> turn(WidgetTester tester, double turns) async {
      final dial = find.byKey(const Key('sleep-dial'));
      final middle = tester.getCenter(dial);
      final radius = tester.getSize(dial).width * 0.4;
      Offset at(double share) => middle + Offset(cos(share * 2 * pi - pi / 2), sin(share * 2 * pi - pi / 2)) * radius;
      final finger = await tester.startGesture(at(0));
      final steps = (turns.abs() * 24).ceil();
      for (var i = 1; i <= steps; i++) {
        await finger.moveTo(at(turns * i / steps));
      }
      await finger.up();
      await tester.pump();
    }

    testWidgets('a full turn is an hour, and it can go round many times', (tester) async {
      await open(tester);
      expect(shown(tester), 30);
      await turn(tester, 1);
      expect(shown(tester), 90);
      await turn(tester, 2.5);
      expect(shown(tester), 240);
      await turn(tester, -1.5);
      expect(shown(tester), 150);
    });

    testWidgets('it stops at one minute and at twelve hours, and turns back at once', (tester) async {
      await open(tester);
      await turn(tester, -2);
      expect(shown(tester), 1);
      await turn(tester, 0.25);
      expect(shown(tester), 16);
      await turn(tester, 14);
      expect(shown(tester), sleepTimerMost);
      await turn(tester, -0.5);
      expect(shown(tester), sleepTimerMost - 30);
      expect(tester.takeException(), isNull);
    });

    testWidgets('OK gives the time and the tick, and both are remembered', (tester) async {
      final saved = <String>[];
      SleepTimerMemory.save = (m, f) async => saved.add('$m $f');
      var answers = await open(tester);
      expect(find.text('Sleep Timer'), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const Key('sleep-disable'))).onPressed, isNull);
      await turn(tester, 0.3);
      await tester.tap(find.text('Play last song to end'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('sleep-ok')));
      await tester.pumpAndSettle();
      expect(answers.single, (minutes: 48, finishSong: true));
      expect(saved, ['48 true']);
      answers = await open(tester);
      expect(shown(tester), 48);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('sleep-finish-song'))).value, isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answers.single, isNull);
    });

    testWidgets('a running timer shows what is left and can be disabled', (tester) async {
      final answers = await open(tester, secondsLeft: 58 * 60 - 20);
      expect(find.text('Sleep Timer: in 58 min'), findsOneWidget);
      expect(shown(tester), 58);
      await tester.tap(find.byKey(const Key('sleep-disable')));
      await tester.pumpAndSettle();
      expect(answers.single!.minutes, 0);
    });

    testWidgets('waiting for the last song says so; other apps get no tick; small screens fit', (tester) async {
      await open(tester, waiting: true, offer: false, size: const Size(320, 480));
      expect(find.text('Sleep Timer: after this song'), findsOneWidget);
      expect(find.byKey(const Key('sleep-finish-song')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await open(tester, secondsLeft: sleepTimerMost * 60, size: const Size(320, 480));
      expect(tester.takeException(), isNull);
    });
  });

  group('the last song', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;
    late SleepTimerService timer;
    var paused = 0;

    PlayableSong song(int id) =>
        PlayableSong(id: id, title: 'S$id', artist: 'A', album: 'B', filePath: '/m/$id.mp3', durationSeconds: 200);

    setUp(() {
      paused = 0;
      backend = FakeAudioBackend();
      engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
      timer = SleepTimerService(
        onFire: () async {
          paused++;
          await engine.pause();
        },
        afterSong: engine.stopAfterSong,
        cancelAfterSong: engine.cancelStopAfterSong,
      );
    });
    tearDown(() async {
      timer.dispose();
      await engine.dispose();
    });

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

    Future<void> run({bool finish = true}) async {
      await engine.playSongs([song(1), song(2), song(3)]);
      timer.set(const Duration(milliseconds: 20), finishSong: finish);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    test('without the tick it pauses at the time', () async {
      await run(finish: false);
      expect(paused, 1);
      expect(engine.state.isPlaying, isFalse);
    });

    test('with it the song plays on, then the next waits paused', () async {
      await run();
      expect(paused, 0);
      expect(engine.state.isPlaying, isTrue);
      expect(timer.finishingSong, isTrue);
      expect(backend.nextPath, isNull, reason: 'nothing lined up behind it');
      backend.emitCompleted();
      await settle();
      expect(engine.state.title, 'S2');
      expect(engine.state.isPlaying, isFalse);
      expect(timer.finishingSong, isFalse);
      // And playing again goes on as usual.
      await engine.play();
      backend.emitCompleted();
      await settle();
      expect(engine.state.title, 'S3');
      expect(engine.state.isPlaying, isTrue);
    });

    test('it does not fade into the next song', () async {
      backend.canCrossfade = true;
      await engine.setCrossfade(4);
      await run();
      backend.emitPosition(const Duration(seconds: 197));
      await settle();
      expect(backend.crossfades, isEmpty);
    });

    test('repeating one song, it stops at its end', () async {
      await engine.setRepeatMode(RepeatMode.one);
      await run();
      backend.emitCompleted();
      await settle();
      expect(engine.state.title, 'S1');
      expect(engine.state.isPlaying, isFalse);
      expect(backend.position, Duration.zero);
    });

    test('disabled while waiting, the music carries on', () async {
      await run();
      timer.set(null);
      expect(timer.finishingSong, isFalse);
      backend.emitCompleted();
      await settle();
      expect(engine.state.title, 'S2');
      expect(engine.state.isPlaying, isTrue);
    });

    test('with nothing playing it just pauses', () async {
      await engine.playSongs([song(1)]);
      await engine.pause();
      timer.set(const Duration(milliseconds: 20), finishSong: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(paused, 1);
      expect(timer.finishingSong, isFalse);
    });
  });

  test('a new timer drops the wait of the old one', () {
    fakeAsync((async) {
      var cancelled = 0;
      late void Function() done;
      final t = SleepTimerService(
        onFire: () async {},
        afterSong: (d) async {
          done = d;
          return true;
        },
        cancelAfterSong: () => cancelled++,
      );
      t.set(const Duration(minutes: 1), finishSong: true);
      async.elapse(const Duration(minutes: 2));
      expect(t.finishingSong, isTrue);
      final old = done;
      t.set(const Duration(minutes: 5));
      expect(cancelled, 1);
      old();
      expect(t.isRunning, isTrue);
      t.dispose();
    });
  });

  test('the waiting travels to the other phone', () {
    const state = PlaybackState(sleepAfterSong: true);
    expect(PlaybackState.fromJson(state.toJson()).sleepAfterSong, isTrue);
    expect(PlaybackState.fromJson(const PlaybackState().toJson()).sleepAfterSong, isFalse);
  });
}
