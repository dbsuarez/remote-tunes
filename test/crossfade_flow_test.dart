import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/player/audio/crossfade_backend.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id, {int duration = 12}) => PlayableSong(
      id: id,
      title: 'S$id',
      artist: 'A',
      album: 'B',
      filePath: '/m/$id.mp3',
      durationSeconds: duration,
    );

/// The real engine on the real two-player backend, with two pretend players that
/// keep time like real ones (position moves while playing, the song ends, a cold
/// player is slow to load). Whatever the phone does at the end of a song, this
/// should do too.
void main() {
  late FakeAudioBackend a;
  late FakeAudioBackend b;
  late CrossfadeBackend backend;
  late QueuePlaybackEngine engine;
  Timer? clock;
  final ended = <FakeAudioBackend>{};

  const tick = Duration(milliseconds: 100);

  setUp(() {
    a = FakeAudioBackend();
    b = FakeAudioBackend();
    ended.clear();
    backend = CrossfadeBackend(a, b, tick: const Duration(milliseconds: 20));
    engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
  });

  tearDown(() async {
    clock?.cancel();
    await engine.dispose();
  });

  /// Lets time pass for the pretend players.
  void startClock(Duration songLength) {
    clock = Timer.periodic(tick, (_) {
      for (final p in [a, b]) {
        if (!p.playing) continue;
        p.position += tick;
        p.emitPosition(p.position);
        if (p.position >= songLength && ended.add(p)) {
          p.playing = false;
          p.emitCompleted();
        }
      }
    });
  }

  Future<void> run({
    required int fadeSeconds,
    Duration coldLoad = Duration.zero,
    bool shuffle = false,
    int count = 3,
  }) async {
    await engine.setCrossfade(fadeSeconds);
    if (shuffle) await engine.setShuffle(true);
    await engine.playSongs([for (var i = 1; i <= count; i++) song(i)]);
    a.emitDuration(const Duration(seconds: 12));
    // Start close to the end so the test is short.
    a.position = const Duration(seconds: 7);
    if (coldLoad > Duration.zero) {
      final gate = Completer<void>();
      b.loadGate = gate.future;
      Timer(coldLoad, gate.complete);
    }
    b.durations['/m/2.mp3'] = const Duration(seconds: 12);
    startClock(const Duration(seconds: 12));
    // Long enough for the fade and a little after the old song's end.
    await Future<void>.delayed(const Duration(seconds: 7));
    b.emitDuration(const Duration(seconds: 12));
  }

  void expectOneCleanChange() {
    expect(a.loaded, ['/m/1.mp3'], reason: 'the first song is loaded once');
    expect(b.loaded, hasLength(1), reason: 'the next song is loaded once, never again: ${b.loaded}');
    expect(b.seekCount, 0, reason: 'and never sought back to the start');
    expect(engine.state.queueIndex, 1);
    expect(engine.state.title, isNot('S1'));
  }

  test('a 1 second fade: one clean change, nothing restarts when the old song ends', () async {
    await run(fadeSeconds: 1);
    expectOneCleanChange();
    expect(engine.state.isPlaying, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a slow first load of the other player (it is cold) changes nothing', () async {
    await run(fadeSeconds: 1, coldLoad: const Duration(milliseconds: 2500));
    expectOneCleanChange();
    expect(engine.state.isPlaying, isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('with shuffle on', () async {
    await run(fadeSeconds: 1, shuffle: true, count: 4);
    expect(a.loaded, hasLength(1));
    expect(b.loaded, hasLength(1), reason: '${b.loaded}');
    expect(b.seekCount, 0);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
