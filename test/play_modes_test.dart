import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/player/play_modes_saver.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id) => PlayableSong(
    id: id, title: 'S$id', artist: 'A', album: 'B', filePath: '/m/$id.mp3', durationSeconds: 100);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late SettingsRepository repo;
  late FakeAudioBackend backend;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SettingsRepository(db);
    backend = FakeAudioBackend();
  });

  tearDown(() => db.close());

  QueuePlaybackEngine engine() => QueuePlaybackEngine(backend: backend, fileExists: (_) => true);

  test('shuffle and repeat start off', () async {
    final s = await repo.load();
    expect([s.shuffleEnabled, s.repeatMode], [false, RepeatMode.off]);
  });

  test('a change is saved, and the next run starts with it', () async {
    final first = engine();
    final saver = PlayModesSaver(
        engine: first, store: repo, shuffle: false, repeat: RepeatMode.off)
      ..start();
    await first.playSongs([song(1), song(2)]);
    await first.setShuffle(true);
    await first.setRepeatMode(RepeatMode.queue);
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    saver.dispose();
    await first.dispose();

    final saved = await repo.load();
    expect([saved.shuffleEnabled, saved.repeatMode], [true, RepeatMode.queue]);

    // The next run applies them before anything plays.
    backend = FakeAudioBackend();
    final second = engine();
    await second.setShuffle(saved.shuffleEnabled);
    await second.setRepeatMode(saved.repeatMode);
    expect(second.state.shuffleEnabled, isTrue);
    expect(second.state.repeatMode, RepeatMode.queue);
    // ... and they stay on when a queue is put back or new songs are played.
    await second.playSongs([song(1), song(2), song(3)]);
    expect(second.state.shuffleEnabled, isTrue);
    expect(second.state.repeatMode, RepeatMode.queue);
    await second.dispose();
  });

  test('turning them off is remembered too', () async {
    await repo.setShuffleEnabled(true);
    await repo.setRepeatMode(RepeatMode.one);
    final e = engine();
    await e.setShuffle(true);
    await e.setRepeatMode(RepeatMode.one);
    final saver = PlayModesSaver(engine: e, store: repo, shuffle: true, repeat: RepeatMode.one)
      ..start();
    await e.setShuffle(false);
    await e.setRepeatMode(RepeatMode.off);
    await settle();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    saver.dispose();
    await e.dispose();
    final s = await repo.load();
    expect([s.shuffleEnabled, s.repeatMode], [false, RepeatMode.off]);
  });

  test('nothing is written when nothing changed', () async {
    final e = engine();
    final saver = PlayModesSaver(engine: e, store: repo, shuffle: false, repeat: RepeatMode.off)
      ..start();
    await e.playSongs([song(1)]);
    await e.setVolume(0.5);
    await settle();
    saver.dispose();
    await e.dispose();
    expect(await repo.readValue(SettingKeys.shuffleEnabled), isNull);
    expect(await repo.readValue(SettingKeys.repeatMode), isNull);
  });

  test('a junk saved repeat value falls back to off', () async {
    await repo.writeValue(SettingKeys.repeatMode, 'sideways');
    expect((await repo.load()).repeatMode, RepeatMode.off);
  });
}
