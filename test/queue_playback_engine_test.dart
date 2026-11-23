import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id, {int duration = 100, String? art}) => PlayableSong(
      id: id,
      title: 'Song $id',
      artist: 'Artist $id',
      album: 'Album',
      filePath: '/private/music/$id.mp3',
      durationSeconds: duration,
      albumArtPath: art,
    );

List<PlayableSong> songs(int n) => [for (var i = 1; i <= n; i++) song(i)];

void main() {
  late FakeAudioBackend backend;
  late QueuePlaybackEngine engine;
  late Set<String> missing;

  setUp(() {
    backend = FakeAudioBackend();
    missing = {};
    engine = QueuePlaybackEngine(
      backend: backend,
      fileExists: (p) => !missing.contains(p),
    );
  });

  tearDown(() => engine.dispose());

  test('playSongs loads the start song and reports state', () async {
    await engine.playSongs(songs(3), startIndex: 1);
    await settle();
    expect(backend.currentPath, '/private/music/2.mp3');
    expect(backend.playing, isTrue);
    final s = engine.state;
    expect(s.title, 'Song 2');
    expect(s.artist, 'Artist 2');
    expect(s.isPlaying, isTrue);
    expect(s.queueIndex, 1);
    expect(s.queueLength, 3);
    expect(s.songId, 2);
    expect(s.durationSeconds, 100);
  });

  test('position updates are reported once per second', () async {
    await engine.playSongs(songs(1));
    final seen = <int>[];
    final sub = engine.states.listen((s) => seen.add(s.positionSeconds));
    backend.emitPosition(const Duration(milliseconds: 1200));
    backend.emitPosition(const Duration(milliseconds: 1700)); // same second
    backend.emitPosition(const Duration(milliseconds: 2100));
    await settle();
    await sub.cancel();
    expect(seen, [1, 2]);
  });

  test('play with an empty queue reports QUEUE_EMPTY', () async {
    await expectLater(
      engine.play(),
      throwsA(isA<PlaybackException>()
          .having((e) => e.code, 'code', ErrorCodes.queueEmpty)),
    );
  });

  test('enqueue shows the first song without starting; play then starts it',
      () async {
    await engine.enqueue(songs(2));
    expect(engine.state.title, 'Song 1');
    expect(engine.state.isPlaying, isFalse);
    expect(backend.loaded, isEmpty);
    await engine.play();
    expect(backend.loaded, ['/private/music/1.mp3']);
    expect(engine.state.isPlaying, isTrue);
  });

  test('pause / toggle / stop', () async {
    await engine.playSongs(songs(2));
    await engine.pause();
    expect(engine.state.isPlaying, isFalse);
    await engine.toggle();
    expect(engine.state.isPlaying, isTrue);
    await engine.toggle();
    expect(engine.state.isPlaying, isFalse);
    backend.emitPosition(const Duration(seconds: 7));
    await settle();
    await engine.stop();
    expect(engine.state.positionSeconds, 0);
    expect(backend.position, Duration.zero);
  });

  test('next keeps the playing state; at the end it does nothing', () async {
    await engine.playSongs(songs(2));
    await engine.next();
    expect(engine.state.title, 'Song 2');
    expect(engine.state.isPlaying, isTrue);
    await engine.next(); // end of queue
    expect(engine.state.title, 'Song 2');

    await engine.pause();
    await engine.previous();
    expect(engine.state.title, 'Song 1');
    expect(engine.state.isPlaying, isFalse, reason: 'stays paused');
  });

  test('previous restarts a track that has played more than 3 seconds', () async {
    await engine.playSongs(songs(3), startIndex: 1);
    backend.emitPosition(const Duration(seconds: 10));
    await settle();
    await engine.previous();
    expect(engine.state.title, 'Song 2');
    expect(engine.state.positionSeconds, 0);
    await engine.previous();
    expect(engine.state.title, 'Song 1');
  });

  test('a finished track advances to the next one automatically', () async {
    await engine.playSongs(songs(3));
    backend.completeTrack();
    await settle();
    expect(engine.state.title, 'Song 2');
    expect(engine.state.isPlaying, isTrue);
  });

  test('end of the queue rewinds and stops on the last track', () async {
    await engine.playSongs(songs(2), startIndex: 1);
    backend.completeTrack();
    await settle();
    expect(engine.state.title, 'Song 2');
    expect(engine.state.isPlaying, isFalse);
    expect(engine.state.positionSeconds, 0);
  });

  test('repeat one replays the same track without reloading', () async {
    await engine.setRepeatMode(RepeatMode.one);
    await engine.playSongs(songs(3));
    backend.completeTrack();
    await settle();
    expect(engine.state.title, 'Song 1');
    expect(backend.loaded, ['/private/music/1.mp3']);
    expect(engine.state.isPlaying, isTrue);
  });

  test('repeat queue wraps around to the first track', () async {
    await engine.setRepeatMode(RepeatMode.queue);
    await engine.playSongs(songs(2), startIndex: 1);
    backend.completeTrack();
    await settle();
    expect(engine.state.title, 'Song 1');
    expect(engine.state.isPlaying, isTrue);
  });

  test('missing files are skipped', () async {
    missing.add('/private/music/2.mp3');
    await engine.playSongs(songs(3));
    await engine.next();
    expect(engine.state.title, 'Song 3');
    expect(engine.state.isPlaying, isTrue);
  });

  test('unplayable files are skipped', () async {
    backend.unplayable.add('/private/music/2.mp3');
    await engine.playSongs(songs(3));
    await engine.next();
    expect(engine.state.title, 'Song 3');
  });

  test('if nothing can play, the error is reported and the engine stops', () async {
    missing.addAll({'/private/music/1.mp3', '/private/music/2.mp3'});
    await expectLater(
      engine.playSongs(songs(2)),
      throwsA(isA<PlaybackException>()
          .having((e) => e.code, 'code', ErrorCodes.fileNotFound)),
    );
    expect(engine.state.isPlaying, isFalse);
  });

  test('removing the current song while playing moves on to the next', () async {
    await engine.playSongs(songs(3));
    final firstId = engine.queueSnapshot().items.first.queueItemId;
    await engine.removeQueueItem(firstId);
    expect(engine.state.title, 'Song 2');
    expect(engine.state.isPlaying, isTrue);
    expect(engine.state.queueLength, 2);
  });

  test('removing the only song stops playback', () async {
    await engine.playSongs(songs(1));
    await engine.removeQueueItem(engine.queueSnapshot().items.single.queueItemId);
    expect(engine.state.isPlaying, isFalse);
    expect(engine.state.title, '');
    expect(engine.state.queueLength, 0);
  });

  test('moveQueueItem, playQueueItem and clearQueue', () async {
    await engine.playSongs(songs(3));
    final ids = engine.queueSnapshot().items.map((i) => i.queueItemId).toList();
    await engine.moveQueueItem(ids[0], 2);
    expect(engine.queueSnapshot().items.map((i) => i.song.id), [2, 3, 1]);

    await engine.playQueueItem(ids[1]);
    expect(engine.state.title, 'Song 2');
    await expectLater(engine.playQueueItem(9999), throwsA(isA<PlaybackException>()));
    await expectLater(engine.moveQueueItem(9999, 0), throwsA(isA<PlaybackException>()));
    await expectLater(engine.removeQueueItem(9999), throwsA(isA<PlaybackException>()));

    await engine.clearQueue();
    expect(engine.state.queueLength, 0);
    expect(engine.state.isPlaying, isFalse);
    expect(engine.queueSnapshot().items, isEmpty);
  });

  test('queue revision changes with content, not with position', () async {
    await engine.playSongs(songs(3));
    final r = engine.state.queueRevision;
    await engine.next();
    expect(engine.state.queueRevision, r);
    await engine.enqueue([song(9)]);
    expect(engine.state.queueRevision, r + 1);
  });

  test('shuffle and repeat are reflected in state', () async {
    await engine.playSongs(songs(5));
    await engine.setShuffle(true);
    await engine.setRepeatMode(RepeatMode.queue);
    expect(engine.state.shuffleEnabled, isTrue);
    expect(engine.state.repeatMode, RepeatMode.queue);
    final snap = engine.queueSnapshot();
    expect(snap.shuffle, isTrue);
    expect(snap.repeat, RepeatMode.queue);
  });

  test('seek and volume are validated', () async {
    await expectLater(engine.seek(5), throwsA(isA<PlaybackException>()),
        reason: 'nothing loaded');
    await engine.playSongs(songs(1));
    await expectLater(
      engine.seek(101),
      throwsA(isA<PlaybackException>()
          .having((e) => e.code, 'code', ErrorCodes.invalidPosition)),
    );
    await engine.seek(40);
    expect(engine.state.positionSeconds, 40);
    await expectLater(engine.setVolume(2), throwsA(isA<PlaybackException>()));
    await engine.setVolume(0.25);
    expect(backend.volume, 0.25);
    expect(engine.state.volume, 0.25);
  });

  test('rapid commands are applied one at a time, in order', () async {
    await engine.playSongs(songs(6));
    await Future.wait([for (var i = 0; i < 4; i++) engine.next()]);
    expect(engine.state.title, 'Song 5');
    expect(backend.loaded.last, '/private/music/5.mp3');
  });

  test('file paths never leave the Player (state and queue JSON)', () async {
    await engine.playSongs([song(1, art: '/private/art/1.jpg')]);
    final stateJson = jsonEncode(engine.state.toJson());
    final queueJson = jsonEncode(engine.queueSnapshot().toJson());
    for (final json in [stateJson, queueJson]) {
      expect(json, isNot(contains('/private')));
      expect(json, isNot(contains('.mp3')));
      expect(json, isNot(contains('.jpg')));
      expect(json, isNot(contains('localArtPath')));
    }
    expect(engine.state.localArtPath, '/private/art/1.jpg',
        reason: 'available locally for the Player UI');
  });

  test('missing files are flagged unavailable in the queue snapshot', () async {
    await engine.enqueue(songs(2));
    missing.add('/private/music/2.mp3');
    final items = engine.queueSnapshot().items;
    expect(items[0].song.available, isTrue);
    expect(items[1].song.available, isFalse);
  });
}
