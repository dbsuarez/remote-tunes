import 'dart:io';

import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/features/ambience/ambience_controller.dart';
import 'package:remote_tunes/features/ambience/ambience_remote.dart';
import 'package:remote_tunes/features/ambience/ambience_session.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/player/audio/player_audio_handler.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'ambience_controller_test.dart' show FakeEngine, FakeFiles, MemoryAmbienceStore;
import 'helpers/fake_audio_backend.dart';

Future<void> waitFor(bool Function() c) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeEngine sound;
  late QueuePlaybackEngine music;
  late AmbienceController ambience;

  setUp(() {
    sound = FakeEngine();
    music = QueuePlaybackEngine(backend: FakeAudioBackend(), fileExists: (_) => true, urlChecker: FakeUrlChecker());
    ambience = AmbienceController(
      engine: sound,
      files: FakeFiles(),
      store: MemoryAmbienceStore(),
      pauseMusic: () async {
        if (music.state.isPlaying) await music.pause();
      },
    );
  });

  tearDown(() async {
    await ambience.stop();
    ambience.dispose();
    await music.dispose();
  });

  const song = PlayableSong(id: 1, title: 'Song', artist: 'A', album: 'B', filePath: '/m/1.mp3', durationSeconds: 60);

  group('with the music and the notification', () {
    late RemoteTunesAudioHandler handler;
    late void Function() disconnect;

    setUp(() {
      handler = RemoteTunesAudioHandler()..attach(music);
      disconnect = connectAmbience(ambience, music, handler);
    });
    tearDown(() => disconnect());

    Future<void> beat() => Future<void>.delayed(const Duration(milliseconds: 30));

    test('only one of them plays', () async {
      await music.playSongs([song]);
      await ambience.setActive('white-noise', true);
      await beat();
      expect(music.state.isPlaying, isFalse);
      expect(ambience.state.playing, isTrue);
      await music.play();
      await waitFor(() => sound.voices.isEmpty);
      expect(ambience.state.playing, isFalse);
      expect(music.state.isPlaying, isTrue);
    });

    test('the notification is ambience\'s while it plays, and the music\'s again after', () async {
      await music.playSongs([song]);
      await beat();
      expect(handler.mediaItem.value!.title, 'Song');
      await ambience.setActive('white-noise', true);
      await ambience.setTimer(30);
      await beat();
      expect(handler.mediaItem.value!.title, 'RemoteTunes Ambience');
      expect(handler.mediaItem.value!.artist, '1 sound · 30 min left');
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.controls, [svc.MediaControl.pause, svc.MediaControl.stop]);
      await handler.pause();
      await beat();
      expect((ambience.state.playing, handler.playbackState.value.playing), (false, false));
      expect(handler.mediaItem.value!.artist, '1 sound · paused');
      await handler.skipToNext();
      expect(music.state.isPlaying, isFalse, reason: 'a skip button does nothing now');
      await handler.click();
      await beat();
      expect(ambience.state.playing, isTrue);
      await handler.stop();
      await beat();
      expect(sound.voices, isEmpty);
      expect(handler.mediaItem.value!.title, 'Song');
    });
  });

  test('the notification uses the name the owner chose', () async {
    final handler = RemoteTunesAudioHandler()..attach(music);
    final disconnect = connectAmbience(ambience, music, handler, name: () => 'Pampatulog');
    await ambience.setActive('white-noise', true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(handler.mediaItem.value!.title, 'RemoteTunes Pampatulog');
    disconnect();
  });

  group('from the other phone', () {
    late PlayerServer server;
    late ControllerClient client;

    Future<void> connect({bool offered = true}) async {
      server = PlayerServer(
        engine: music,
        deviceName: 'P',
        port: 0,
        bindAddress: InternetAddress.loopbackIPv4,
        ambience: offered ? ambience : null,
      );
      await server.start();
      client = ControllerClient(transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p));
      await client.connect(host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
      final code = server.current.pending!.code;
      server.acceptPairing();
      await client.submitCode(code);
      await waitFor(() => client.current.isConnected);
    }

    tearDown(() async {
      await client.dispose();
      await server.stop();
    });

    test('sees the sounds and controls them', () async {
      await connect();
      await ambience.addFile('rain', '/d/rain.mp3');
      final remote = RemoteAmbience(client);
      await remote.refresh();
      expect(remote.state.sound('rain')!.available, isTrue);
      await remote.setActive('rain', true);
      await remote.setActive('white-noise', true);
      await remote.setVolume('rain', 0.9);
      await remote.setMaster(0.5);
      await remote.setTimer(45);
      expect(sound.voices.keys, {'rain', 'white-noise'});
      expect(sound.voices['rain'], closeTo(0.45, 0.001));
      expect(remote.state.timerMinutes, 45);
      await remote.pause();
      expect(remote.state.playing, isFalse);
      await remote.play();
      await remote.saveMix('Night');
      final mix = remote.state.mixes.last;
      expect(mix.name, 'Night');
      await remote.stop();
      expect(sound.voices, isEmpty);
      expect(await remote.startMix('sleep'), isEmpty);
      await remote.deleteMix(mix.id);
      expect(remote.state.mixes.map((m) => m.name), isNot(contains('Night')));
      remote.dispose();
    });

    test('cannot go louder than the Player allows', () async {
      await connect();
      await ambience.setMaxVolume(0.2);
      final remote = RemoteAmbience(client);
      await remote.setActive('white-noise', true);
      await remote.setMaster(1);
      await remote.setVolume('white-noise', 1);
      expect(sound.voices['white-noise'], closeTo(0.2, 0.001));
      expect(remote.state.maxVolume, closeTo(0.2, 0.001));
      remote.dispose();
    });

    test('keeps up with changes made on the Player while the screen is open', () async {
      await connect();
      final remote = RemoteAmbience(client, every: const Duration(milliseconds: 100));
      void listen() {}
      remote.addListener(listen);
      await ambience.setActive('pink-noise', true);
      await waitFor(() => remote.state.active.containsKey('pink-noise'));
      remote.removeListener(listen);
      remote.dispose();
    });

    test('gets plain reasons', () async {
      await connect();
      final remote = RemoteAmbience(client);
      await expectLater(remote.setActive('rain', true),
          throwsA(isA<ControllerException>().having((e) => e.message, 'message', contains('Add a file for Morning Rain'))));
      await expectLater(client.sendCommand(RemoteActions.ambience, {'op': 'volume', 'id': 'rain', 'volume': 'loud'}),
          throwsA(isA<ControllerException>()));
      await expectLater(client.sendCommand(RemoteActions.ambience, {'op': 'explode'}), throwsA(isA<ControllerException>()));
      remote.dispose();
    });

    test('a Player without ambience says so on the screen', () async {
      await connect(offered: false);
      final remote = RemoteAmbience(client);
      await expectLater(remote.refresh(), throwsA(isA<ControllerException>()));
      expect(remote.state.error, contains("can't play ambience"));
      remote.dispose();
    });
  });
}
