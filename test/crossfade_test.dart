import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/features/player/audio/crossfade_backend.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id, {int duration = 100, bool url = false}) => url
    ? PlayableSong.stream(url: 'https://x/$id.mp3', title: 'S$id', artist: 'A', album: 'B')
    : PlayableSong(
        id: id,
        title: 'S$id',
        artist: 'A',
        album: 'B',
        filePath: '/m/$id.mp3',
        durationSeconds: duration);

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('two players, one backend', () {
    late FakeAudioBackend a;
    late FakeAudioBackend b;
    late CrossfadeBackend x;

    setUp(() {
      a = FakeAudioBackend();
      b = FakeAudioBackend();
      x = CrossfadeBackend(a, b, tick: const Duration(milliseconds: 5));
    });

    tearDown(() async => x.dispose());

    test('everything normal goes to the first player', () async {
      await x.load('/m/1.mp3');
      await x.play();
      await x.setVolume(0.6);
      await x.setSpeed(1.5);
      expect(a.currentPath, '/m/1.mp3');
      expect(a.playing, isTrue);
      expect(a.volume, 0.6);
      expect([a.speed, b.speed], [1.5, 1.5], reason: 'both, so a fade does not change speed');
      expect(b.currentPath, isNull);
      expect(x.supportsCrossfade, isTrue);
    });

    test('a slow first load, with the song ending meanwhile, still gives one clean change',
        () async {
      await x.load('/m/1.mp3');
      await x.play();
      a.emitDuration(const Duration(seconds: 100));
      await wait(5);
      a.position = const Duration(milliseconds: 99500);
      final gate = Completer<void>();
      b.loadGate = gate.future;
      final completed = <void>[];
      final advanced = <String?>[];
      x.completedStream.listen(completed.add);
      x.advancedStream.listen(advanced.add);
      final fade = x.crossfadeTo('/m/2.mp3', const Duration(seconds: 2));
      await wait(10);
      a.emitCompleted(); // the song ran out while the next was still loading
      await wait(10);
      gate.complete();
      expect(await fade, isTrue);
      expect(completed, isEmpty, reason: 'the engine must not start the next song itself');
      expect(advanced, ['/m/2.mp3']);
      expect(b.playing, isTrue);
    });

    test('with time to spare the next song waits, loaded, until the fade should begin', () async {
      await x.load('/m/1.mp3');
      await x.play();
      a.emitDuration(const Duration(seconds: 100));
      await wait(5);
      a.position = const Duration(milliseconds: 99700);
      final fade = x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 100));
      await wait(30);
      expect(b.currentPath, '/m/2.mp3');
      expect(b.playing, isFalse, reason: 'not started yet: 500 ms of the song are still to play');
      expect(await fade, isTrue);
      expect(b.playing, isTrue);
    });

    test('only the audible player is heard', () async {
      final positions = <Duration>[];
      x.positionStream.listen(positions.add);
      a.emitPosition(const Duration(seconds: 3));
      b.emitPosition(const Duration(seconds: 99));
      await wait(10);
      expect(positions, [const Duration(seconds: 3)]);
    });

    test('a fade ends with the next song audible and the old one stopped', () async {
      await x.load('/m/1.mp3');
      await x.play();
      await x.setVolume(0.8);
      final advanced = <String?>[];
      x.advancedStream.listen(advanced.add);
      final ok = await x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 100));
      expect(ok, isTrue);
      expect(advanced, ['/m/2.mp3']);
      expect(b.currentPath, '/m/2.mp3');
      expect(b.playing, isTrue);
      expect(b.volume, closeTo(0.8, 1e-9), reason: 'the new song ends at full volume');
      expect(a.playing, isFalse, reason: 'the old one is stopped');
      // Now b is the audible one: it gets the positions and the commands.
      final positions = <Duration>[];
      x.positionStream.listen(positions.add);
      b.emitPosition(const Duration(seconds: 7));
      a.emitPosition(const Duration(seconds: 50));
      await wait(10);
      expect(positions, [const Duration(seconds: 7)]);
      await x.setVolume(0.4);
      expect(b.volume, 0.4);
    });

    test('while fading, the two volumes keep the loudness even (equal power)', () async {
      await x.load('/m/1.mp3');
      await x.play();
      await x.setVolume(1.0);
      final fade = x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 300));
      var checks = 0;
      for (var i = 0; i < 8; i++) {
        await wait(25);
        final out = a.volume;
        final into = b.volume;
        if (out + into > 0.01 && into < 1) {
          expect(out * out + into * into, closeTo(1.0, 0.06));
          checks++;
        }
      }
      expect(checks, greaterThan(3));
      await fade;
    });

    test('the new song starts silent and the old one starts at full volume', () async {
      await x.load('/m/1.mp3');
      await x.play();
      final fade = x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 200));
      await wait(10);
      expect(b.playing, isTrue);
      expect(b.volume, lessThan(0.2));
      expect(a.volume, greaterThan(0.8));
      await fade;
    });

    test('pausing holds the fade where it is, and playing carries on', () async {
      await x.load('/m/1.mp3');
      await x.play();
      final fade = x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 200));
      await wait(60);
      await x.pause();
      expect(a.playing, isFalse);
      expect(b.playing, isFalse);
      final held = b.volume;
      await wait(120);
      expect(b.volume, closeTo(held, 0.001), reason: 'no progress while paused');
      await x.play();
      expect(await fade, isTrue);
    });

    test('loading something else ends a fade and restores the volume', () async {
      await x.load('/m/1.mp3');
      await x.play();
      await x.setVolume(0.7);
      final fade = x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 500));
      await wait(30);
      await x.load('/m/3.mp3');
      expect(await fade, isFalse);
      expect(a.currentPath, '/m/3.mp3');
      expect(a.volume, 0.7);
      expect(b.playing, isFalse);
    });

    test('seeking during a fade lets the next song take over, and it is the one sought', () async {
      await x.load('/m/1.mp3');
      await x.play();
      final fade = x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 500));
      await wait(30);
      await x.seek(const Duration(seconds: 10));
      expect(await fade, isTrue);
      expect(a.playing, isFalse, reason: 'the old song stopped');
      expect(b.playing, isTrue);
      expect(b.position, const Duration(seconds: 10));
      expect(a.position, isNot(const Duration(seconds: 10)));
    });

    test('a song that cannot be loaded does not start a fade', () async {
      await x.load('/m/1.mp3');
      await x.play();
      b.unplayable.add('/m/bad.mp3');
      expect(await x.crossfadeTo('/m/bad.mp3', const Duration(milliseconds: 100)), isFalse);
      expect(a.playing, isTrue);
      expect(a.volume, 1.0);
    });

    test('one fade at a time, and a zero length is refused', () async {
      await x.load('/m/1.mp3');
      await x.play();
      final first = x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 200));
      await wait(10);
      expect(await x.crossfadeTo('/m/3.mp3', const Duration(milliseconds: 100)), isFalse);
      await first;
      expect(await x.crossfadeTo('/m/3.mp3', Duration.zero), isFalse);
    });

    test('the equalizer is set on both players', () async {
      await x.setEqualizer(enabled: true, gains: [1, 2, 3, 4, 5]);
      expect(a.eqCalls.last.gains, [1, 2, 3, 4, 5]);
      expect(b.eqCalls.last.gains, [1, 2, 3, 4, 5]);
      expect(await x.equalizerBands(), isNotNull);
    });

    test('a second fade works after the first (the roles swap back and forth)', () async {
      await x.load('/m/1.mp3');
      await x.play();
      await x.crossfadeTo('/m/2.mp3', const Duration(milliseconds: 60));
      await x.crossfadeTo('/m/3.mp3', const Duration(milliseconds: 60));
      expect(a.currentPath, '/m/3.mp3');
      expect(a.playing, isTrue);
      expect(b.playing, isFalse);
    });
  });

  group('the engine fades near the end of a song', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;

    setUp(() {
      backend = FakeAudioBackend()..canCrossfade = true;
      engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
    });

    tearDown(() => engine.dispose());

    Future<void> near(num seconds) async {
      backend.emitPosition(Duration(milliseconds: (seconds * 1000).round()));
      await settle();
    }

    test('off by default: songs change as before (the next one is lined up)', () async {
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await near(97);
      expect(backend.crossfades, isEmpty);
      expect(backend.nextPath, '/m/2.mp3');
    });

    test('on: it starts fading into the next song when the time is right', () async {
      await engine.setCrossfade(4);
      await engine.playSongs([song(1), song(2)]);
      await settle();
      expect(backend.nextPath, isNull, reason: 'not lined up: the fade starts the next one');
      await near(50);
      expect(backend.crossfades, isEmpty, reason: 'too early');
      await near(96);
      expect(backend.crossfades, hasLength(1));
      expect(backend.crossfades.single.path, '/m/2.mp3');
      expect(backend.crossfades.single.length, const Duration(seconds: 4));
      // The backend says the change happened: the queue moved on.
      expect(engine.state.title, 'S2');
      expect(engine.state.queueIndex, 1);
      expect(engine.state.isPlaying, isTrue);
    });

    test('it fades only once per song (the last one has nothing after it)', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await near(97);
      await near(98);
      await near(98.5);
      expect(backend.crossfades, hasLength(1));
    });

    test('and again for the next song', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1), song(2), song(3)]);
      await settle();
      await near(97);
      await near(97);
      expect(backend.crossfades.map((c) => c.path), ['/m/2.mp3', '/m/3.mp3']);
    });

    test('the last song has nothing to fade into', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1)]);
      await settle();
      await near(98);
      expect(backend.crossfades, isEmpty);
    });

    test('repeat-all fades from the last song back to the first', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1), song(2)], startIndex: 1);
      await engine.setRepeatMode(RepeatMode.queue);
      await settle();
      await near(98);
      expect(backend.crossfades.single.path, '/m/1.mp3');
    });

    test('repeat-one never fades into something else', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1), song(2)]);
      await engine.setRepeatMode(RepeatMode.one);
      await settle();
      await near(98);
      expect(backend.crossfades, isEmpty);
    });

    test('internet tracks and missing files are not faded into', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1), song(2, url: true)]);
      await settle();
      await near(98);
      expect(backend.crossfades, isEmpty);
    });

    test('a song too short to fade just changes', () async {
      await engine.setCrossfade(6);
      await engine.playSongs([song(1, duration: 10), song(2)]);
      await settle();
      await near(9);
      expect(backend.crossfades, isEmpty);
    });

    test('not while paused', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1), song(2)]);
      await engine.pause();
      await settle();
      await near(98);
      expect(backend.crossfades, isEmpty);
    });

    test('a backend that cannot crossfade keeps gapless playback', () async {
      backend.canCrossfade = false;
      await engine.setCrossfade(4);
      await engine.playSongs([song(1), song(2)]);
      await settle();
      expect(backend.nextPath, '/m/2.mp3');
      await near(98);
      expect(backend.crossfades, isEmpty);
    });

    test('pressing Next fades into the next song at once (not timed to the end)', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1), song(2), song(3)]);
      await settle();
      await engine.next();
      await settle();
      expect(engine.state.title, 'S2');
      expect(backend.crossfades, hasLength(1));
      expect(backend.crossfades.single.length, const Duration(seconds: 3));
      expect(backend.crossfadeImmediate.single, isTrue);
    });

    test('the volume and tags still apply to the song faded into', () async {
      await engine.setCrossfade(3);
      await engine.playSongs([song(1), song(2)]);
      await settle();
      await near(97);
      expect(engine.state.title, 'S2');
      expect(engine.state.volume, 0.8);
    });
  });
}
