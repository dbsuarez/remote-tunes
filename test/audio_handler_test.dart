import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/features/player/audio/player_audio_handler.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id) => PlayableSong(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      filePath: '/m/$id.mp3',
      durationSeconds: 100,
      albumArtPath: '/art/$id.jpg',
    );

void main() {
  late FakeAudioBackend backend;
  late QueuePlaybackEngine engine;
  late RemoteTunesAudioHandler handler;

  setUp(() async {
    backend = FakeAudioBackend();
    engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
    handler = RemoteTunesAudioHandler()..attach(engine);
    await engine.playSongs([song(1), song(2), song(3)]);
    await settle();
  });

  tearDown(() async {
    handler.detach();
    await engine.dispose();
  });

  test('the lock screen shows the song, its length and its cover', () {
    final item = handler.mediaItem.value!;
    expect(item.title, 'Song 1');
    expect(item.artist, 'Artist');
    expect(item.duration, const Duration(seconds: 100));
    expect(item.artUri, Uri.file('/art/1.jpg'));
  });

  test('shuffle and repeat are shown, and can be changed from the lock screen', () async {
    expect(handler.playbackState.value.shuffleMode, svc.AudioServiceShuffleMode.none);
    expect(handler.playbackState.value.repeatMode, svc.AudioServiceRepeatMode.none);

    await handler.setShuffleMode(svc.AudioServiceShuffleMode.all);
    await handler.setRepeatMode(svc.AudioServiceRepeatMode.all);
    await settle();
    expect(engine.state.shuffleEnabled, isTrue);
    expect(engine.state.repeatMode, RepeatMode.queue);
    expect(handler.playbackState.value.shuffleMode, svc.AudioServiceShuffleMode.all);
    expect(handler.playbackState.value.repeatMode, svc.AudioServiceRepeatMode.all);

    await handler.setRepeatMode(svc.AudioServiceRepeatMode.one);
    await settle();
    expect(engine.state.repeatMode, RepeatMode.one);
    expect(handler.playbackState.value.repeatMode, svc.AudioServiceRepeatMode.one);
  });

  test('speed from the system is passed on, within limits', () async {
    await handler.setSpeed(1.5);
    await settle();
    expect(engine.state.speed, 1.5);
    expect(handler.playbackState.value.speed, 1.5);
    await handler.setSpeed(9);
    await settle();
    expect(engine.state.speed, 2.0);
  });

  test('the system is told which extra actions are allowed', () {
    final actions = handler.playbackState.value.systemActions;
    expect(actions, containsAll({
      svc.MediaAction.seek,
      svc.MediaAction.setShuffleMode,
      svc.MediaAction.setRepeatMode,
      svc.MediaAction.setSpeed,
    }));
  });

  test('play, pause and skip from the lock screen reach the engine', () async {
    await handler.pause();
    await settle();
    expect(engine.state.isPlaying, isFalse);
    await handler.skipToNext();
    await settle();
    expect(engine.state.title, 'Song 2');
    await handler.seek(const Duration(seconds: 30));
    await settle();
    expect(engine.state.positionSeconds, 30);
  });
}
