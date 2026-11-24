import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id, {int duration = 100}) => PlayableSong(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      filePath: '/m/$id.mp3',
      durationSeconds: duration,
    );

List<PlayableSong> songs(int n) => [for (var i = 1; i <= n; i++) song(i)];

void main() {
  late FakeAudioBackend backend;
  late QueuePlaybackEngine engine;
  late Set<String> missing;
  late List<int> started;

  setUp(() {
    backend = FakeAudioBackend();
    missing = {};
    started = [];
    engine = QueuePlaybackEngine(
      backend: backend,
      fileExists: (p) => !missing.contains(p),
      onSongStarted: started.add,
    );
  });

  tearDown(() => engine.dispose());

  test('the next song is lined up as soon as one starts', () async {
    await engine.playSongs(songs(3));
    await settle();
    expect(backend.nextPath, '/m/2.mp3');
  });

  test('moving on by itself switches songs with no new load', () async {
    await engine.playSongs(songs(3));
    await settle();
    backend.advanceGapless();
    await settle();
    expect(backend.loaded, ['/m/1.mp3'], reason: 'nothing was loaded again');
    expect(engine.state.title, 'Song 2');
    expect(engine.state.queueIndex, 1);
    expect(engine.state.isPlaying, isTrue);
    expect(engine.state.positionSeconds, 0);
    expect(engine.state.durationSeconds, 100);
    expect(started, [1, 2], reason: 'counted as played');
    // And the one after is lined up next.
    expect(backend.nextPath, '/m/3.mp3');
  });

  test('it keeps going through the whole queue', () async {
    await engine.playSongs(songs(3));
    await settle();
    backend.advanceGapless();
    await settle();
    backend.advanceGapless();
    await settle();
    expect(engine.state.title, 'Song 3');
    expect(backend.nextPath, isNull, reason: 'nothing follows the last song');
    backend.completeTrack();
    await settle();
    expect(engine.state.isPlaying, isFalse);
  });

  test('the last song has nothing lined up', () async {
    await engine.playSongs(songs(1));
    await settle();
    expect(backend.nextPath, isNull);
  });

  test('skipping loads normally and lines up the right song again', () async {
    await engine.playSongs(songs(4));
    await settle();
    await engine.next();
    await settle();
    expect(engine.state.title, 'Song 2');
    expect(backend.nextPath, '/m/3.mp3');
  });

  test('changing the queue changes what is lined up', () async {
    await engine.playSongs(songs(3));
    await settle();
    expect(backend.nextPath, '/m/2.mp3');
    await engine.enqueue([song(9)], playNext: true);
    await settle();
    expect(backend.nextPath, '/m/9.mp3');
    final next = engine.queueSnapshot().items[1].queueItemId;
    await engine.removeQueueItem(next);
    await settle();
    expect(backend.nextPath, '/m/2.mp3');
  });

  test('clearing the queue takes the lined-up song away', () async {
    await engine.playSongs(songs(3));
    await settle();
    await engine.clearQueue();
    await settle();
    expect(backend.nextPath, isNull);
  });

  test('repeat one is not lined up (it replays the same song)', () async {
    await engine.playSongs(songs(3));
    await settle();
    await engine.setRepeatMode(RepeatMode.one);
    await settle();
    expect(backend.nextPath, isNull);
  });

  test('repeat the queue wraps from the last song to the first', () async {
    await engine.playSongs(songs(2), startIndex: 1);
    await engine.setRepeatMode(RepeatMode.queue);
    await settle();
    expect(backend.nextPath, '/m/1.mp3');
    backend.advanceGapless();
    await settle();
    expect(engine.state.title, 'Song 1');
  });

  test('a missing file is not lined up; it is skipped the usual way', () async {
    missing.add('/m/2.mp3');
    await engine.playSongs(songs(3));
    await settle();
    expect(backend.nextPath, isNull);
    backend.completeTrack();
    await settle();
    expect(engine.state.title, 'Song 3');
  });

  test('internet tracks are not lined up', () async {
    await engine.playSongs([
      song(1),
      PlayableSong.stream(url: 'https://x/a.mp3', title: 'T', artist: 'A', album: 'B'),
    ]);
    await settle();
    expect(backend.nextPath, isNull);
  });

  test('if the backend moved to a different file than the queue expects, it loads the right one',
      () async {
    await engine.playSongs(songs(3));
    await settle();
    backend.nextPath = '/m/3.mp3'; // the backend is playing song 3, the queue expects 2
    backend.advanceGapless();
    await settle();
    expect(backend.loaded.last, '/m/2.mp3');
    expect(engine.state.title, 'Song 2');
    expect(backend.playing, isTrue);
  });

  test('pausing before the change keeps it paused afterwards', () async {
    await engine.playSongs(songs(3));
    await settle();
    await engine.pause();
    await settle();
    expect(backend.nextPath, '/m/2.mp3', reason: 'still ready');
  });
}
