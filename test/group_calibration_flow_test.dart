import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/drift_queue_store.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/group/calibration_analysis.dart';
import 'package:remote_tunes/features/group/calibration_track.dart';
import 'package:remote_tunes/features/group/group_audio_cache.dart';
import 'package:remote_tunes/features/group/group_calibrator.dart';
import 'package:remote_tunes/features/group/group_follower_service.dart';
import 'package:remote_tunes/features/group/group_native.dart';
import 'package:remote_tunes/features/group/mic_recorder.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/synthetic_recording.dart';

Future<void> waitFor(bool Function() c,
    {String? reason, Duration timeout = const Duration(seconds: 8)}) async {
  final end = DateTime.now().add(timeout);
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _MemNudge implements NudgeStore {
  final byRoute = <String, int>{};
  @override
  Future<int> load(String route) async => byRoute[route] ?? 0;
  @override
  Future<void> save(String route, int ms) async => byRoute[route] = ms;
}

class _Native implements GroupNative {
  String route = 'speaker';
  final locks = <bool>[];
  @override
  Future<void> setLocks({required bool enabled, bool keepScreenOn = false}) async =>
      locks.add(enabled);
  @override
  Future<String> outputRoute() async => route;
  @override
  Future<int?> outputLatencyMs() async => 37;
}

class FakeMic implements MicRecorder {
  FakeMic({this.permission = true, this.recording, this.failStart = false});
  final bool permission;
  final bool failStart;
  Float64List? recording;
  bool started = false;
  bool stopped = false;

  @override
  Future<bool> ensurePermission() async => permission;
  @override
  Future<void> start() async {
    if (failStart) throw StateError('no microphone');
    started = true;
  }

  @override
  Future<Float64List> stop() async {
    stopped = true;
    return recording ?? Float64List(0);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late AppDatabase db;
  late LibraryRepository repo;
  late FakeAudioBackend playerBackend;
  late QueuePlaybackEngine engine;
  late PlayerServer server;
  late ControllerClient client;
  late FakeAudioBackend follower;
  late _MemNudge nudges;
  late _Native native;
  final ids = <String, int>{};

  GroupFollowerService makeService({
    FakeMic? mic,
    Future<SyncMeasurement> Function(Float64List)? analyze,
    Future<void> Function(double)? waitForMedia,
  }) =>
      GroupFollowerService(
        client: client,
        makeBackend: () => follower,
        audio: GroupAudioCache(
          requestFor: client.groupAudioRequest,
          folder: () async => Directory('${tmp.path}/cache'),
        ),
        nudges: nudges,
        native: native,
        makeRecorder: () => mic ?? FakeMic(),
        analyze: analyze,
        waitForMedia: waitForMedia ?? (s) async {},
        resyncEvery: const Duration(seconds: 30),
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt_cal_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    for (final name in ['One', 'Two', 'Three']) {
      final f = File('${tmp.path}/$name.mp3')..writeAsBytesSync(List.filled(5000, name.length));
      ids[name] = await repo.addSong(
          title: name, artist: 'A', album: 'B', filePath: f.path, durationSeconds: 100);
    }
    playerBackend = FakeAudioBackend();
    engine = QueuePlaybackEngine(backend: playerBackend, fileExists: (_) => true);
    server = PlayerServer(
      engine: engine,
      deviceName: 'P',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      library: RepositoryPlayerLibrary(repo),
      scratchDir: tmp,
    );
    await server.start();
    client = ControllerClient(
      transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p),
      heartbeatInterval: const Duration(milliseconds: 200),
    );
    await client.connect(
        host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    final code = server.current.pending!.code;
    server.acceptPairing();
    await client.submitCode(code);
    await waitFor(() => client.current.isConnected, reason: 'paired');

    follower = FakeAudioBackend();
    nudges = _MemNudge();
    native = _Native();

    // The Player is playing song One at 5 s, with Two and Three queued.
    final songs = await repo.songsByIds([ids['One']!, ids['Two']!, ids['Three']!]);
    await engine.playSongs([for (final s in songs) s.toPlayable()!]);
    playerBackend.emitPosition(const Duration(seconds: 5));
    await settle();
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
    await engine.dispose();
    await db.close();
    // On Windows a file still being streamed cannot be deleted yet: retry.
    for (var i = 0; i < 30; i++) {
      try {
        await tmp.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  List<String> queueTitles() =>
      [for (final i in engine.queueSnapshot().items) i.song.title];

  /// Joins group play and waits until this phone is playing along.
  Future<GroupFollowerService> joined(GroupFollowerService s) async {
    await s.join();
    await waitFor(() => follower.playing, reason: 'follower playing');
    return s;
  }

  test('the Player plays the click track, mutes itself on request, and all is put back',
      () async {
    final snapshots = <double, ({String title, double volume, List<String> queue})>{};
    final s = await joined(makeService(waitForMedia: (sec) async {
      snapshots[sec] =
          (title: engine.state.title, volume: engine.state.volume, queue: queueTitles());
      if (sec == CalibrationTrack.playerWindow.start) {
        await waitFor(() => engine.state.title.startsWith('Sync test'), reason: 'click track');
      }
    }, analyze: (_) async => const SyncMeasurement(offsetMs: 0.4)));
    final original = engine.state.volume;

    final r = await s.autoAlign();
    expect(r.ok, isTrue);

    final start = snapshots[CalibrationTrack.playerWindow.start]!;
    expect(start.title, 'Sync test (Auto-align)');
    expect(start.queue, ['One', 'Sync test (Auto-align)', 'Two', 'Three']);
    expect(start.volume, original, reason: 'the Player is audible while it is measured');

    final muted = snapshots[CalibrationTrack.unmuteFollowerAt]!;
    expect(muted.volume, 0.0, reason: 'the Player is silent while this phone is measured');

    // Afterwards: the song that was playing, where it was, the volume, no test track.
    await waitFor(() => engine.state.title == 'One', reason: 'back on One');
    expect(queueTitles(), ['One', 'Two', 'Three']);
    expect(engine.state.volume, original);
    expect(playerBackend.position.inSeconds, 5);
    expect(engine.state.isPlaying, isTrue, reason: 'it was playing before');
  });

  test('this phone is silent while the Player is measured, then loud, then back to normal',
      () async {
    final volumes = <double, double>{};
    final s = await joined(makeService(waitForMedia: (sec) async {
      volumes[sec] = follower.volume;
    }, analyze: (_) async => const SyncMeasurement(offsetMs: 0.1)));
    await s.autoAlign();
    expect(volumes[CalibrationTrack.playerWindow.start], 0.0);
    expect(volumes[CalibrationTrack.mutePlayerAt], 0.0);
    expect(volumes[CalibrationTrack.unmuteFollowerAt], 0.0, reason: 'unmuted just after this');
    expect(volumes[CalibrationTrack.endAt], 1.0);
    expect(follower.volume, 1.0);
  });

  test('the measured difference moves the fine-tune', () async {
    nudges.byRoute['speaker'] = 10;
    final s = await joined(makeService(
        analyze: (_) async => const SyncMeasurement(offsetMs: 37.4)));
    final r = await s.autoAlign();
    expect(r.ok, isTrue);
    expect(r.nudgeMs, 47, reason: 'was +10, this phone was 37 ms late');
    expect(nudges.byRoute['speaker'], 47);
    expect(s.status.nudgeMs, 47);
    expect(r.message, contains('37.4 ms late'));
    expect(r.message, contains('+47 ms'));
  });

  test('an early phone gets a negative fine-tune', () async {
    final s = await joined(makeService(
        analyze: (_) async => const SyncMeasurement(offsetMs: -22.0)));
    final r = await s.autoAlign();
    expect(r.nudgeMs, -22);
    expect(r.message, contains('early'));
  });

  test('a correction bigger than the fine-tune can hold is clamped and said so', () async {
    final s = await joined(makeService(
        analyze: (_) async => const SyncMeasurement(offsetMs: 500)));
    final r = await s.autoAlign();
    expect(r.nudgeMs, 300);
    expect(r.clamped, isTrue);
  });

  test('already lined up: it says so and leaves the fine-tune alone', () async {
    nudges.byRoute['speaker'] = 25;
    final s = await joined(
        makeService(analyze: (_) async => const SyncMeasurement(offsetMs: 0.8)));
    final r = await s.autoAlign();
    expect(r.ok, isTrue);
    expect(r.message, contains('Already lined up'));
    expect(r.nudgeMs, 26, reason: 'moved by the 0.8 ms that was measured, no more');
  });

  test('with the real analysis: a recording where this phone is 37 ms late', () async {
    final mic = FakeMic(
        recording: syntheticRecording(playerLatencyMs: 80, followerLatencyMs: 117, noise: 0.01));
    final s = await joined(makeService(mic: mic));
    final r = await s.autoAlign();
    expect(r.message, isNotEmpty);
    expect(r.ok, isTrue, reason: r.message);
    expect(r.offsetMs!, closeTo(37, 0.5));
    expect(nudges.byRoute['speaker'], 37);
    expect(mic.started && mic.stopped, isTrue);
  });

  test('running it again after the correction finds it lined up', () async {
    // After the first run this phone plays 37 ms ahead, so now it sounds in step.
    final first = FakeMic(recording: syntheticRecording(playerLatencyMs: 80, followerLatencyMs: 117));
    var s = await joined(makeService(mic: first));
    await s.autoAlign();
    expect(nudges.byRoute['speaker'], 37);
    await s.leave();

    follower = FakeAudioBackend();
    final second = FakeMic(recording: syntheticRecording(playerLatencyMs: 80, followerLatencyMs: 80));
    s = await joined(makeService(mic: second));
    final r = await s.autoAlign();
    expect(r.message, contains('Already lined up'));
    expect(nudges.byRoute['speaker'], 37, reason: 'unchanged within a millisecond');
  });

  test('a silent recording changes nothing and says why', () async {
    final s = await joined(makeService(mic: FakeMic(recording: Float64List(44100 * 16))));
    final r = await s.autoAlign();
    expect(r.ok, isFalse);
    expect(r.message, contains('microphone'));
    expect(nudges.byRoute['speaker'] ?? 0, 0);
    await waitFor(() => queueTitles().length == 3, reason: 'queue restored');
  });

  test('without the microphone permission nothing is started on the Player', () async {
    final mic = FakeMic(permission: false);
    final s = await joined(makeService(mic: mic));
    final r = await s.autoAlign();
    expect(r.ok, isFalse);
    expect(r.message, contains('microphone'));
    expect(mic.started, isFalse);
    expect(queueTitles(), ['One', 'Two', 'Three'], reason: 'no click track queued');
  });

  test('a recorder that fails to start is reported, and nothing is left changed', () async {
    final s = await joined(makeService(mic: FakeMic(failStart: true)));
    final r = await s.autoAlign();
    expect(r.ok, isFalse);
    expect(queueTitles(), ['One', 'Two', 'Three']);
    expect(engine.state.volume, closeTo(0.8, 1e-9));
    expect(follower.volume, 1.0);
  });

  test('cancelling puts everything back', () async {
    var calls = 0;
    final mic = FakeMic();
    final s = await joined(makeService(mic: mic, waitForMedia: (sec) async {
      calls++;
      if (calls == 2) throw CalibrationCancelled();
    }));
    final r = await s.autoAlign();
    expect(r.ok, isFalse);
    expect(r.message, 'Cancelled.');
    expect(mic.stopped, isTrue);
    await waitFor(() => engine.state.title == 'One', reason: 'back on One');
    expect(queueTitles(), ['One', 'Two', 'Three']);
    expect(engine.state.volume, closeTo(0.8, 1e-9));
    expect(follower.volume, 1.0);
  });

  test('if this phone stops playing along mid-test, the Player is still restored', () async {
    var calls = 0;
    late GroupFollowerService s;
    s = await joined(makeService(waitForMedia: (sec) async {
      calls++;
      if (calls == 2) {
        await s.leave(); // group play ends right in the middle
        throw CalibrationFailed('Group play stopped during the test.');
      }
    }));
    final r = await s.autoAlign();
    expect(r.ok, isFalse);
    await waitFor(() => queueTitles().length == 3 && engine.state.volume > 0.7,
        reason: 'Player restored');
    expect(queueTitles(), ['One', 'Two', 'Three']);
  });

  test('the Controller leaving the group mid-test makes the Player undo it by itself',
      () async {
    final s = await joined(makeService(waitForMedia: (sec) async {
      if (sec == CalibrationTrack.mutePlayerAt) {
        await client.setGroupJoin(false); // without telling the calibrator
      }
    }, analyze: (_) async => const SyncMeasurement(offsetMs: 1)));
    await s.autoAlign();
    await waitFor(() => queueTitles().length == 3 && engine.state.volume > 0.7,
        reason: 'Player restored by itself');
  });

  test('Bluetooth output is refused with an explanation', () async {
    native.route = 'bluetooth';
    final s = await joined(makeService());
    final r = await s.autoAlign();
    expect(r.ok, isFalse);
    expect(r.message, contains('Bluetooth'));
    expect(queueTitles(), ['One', 'Two', 'Three']);
  });

  test('not joined: it says to switch group play on first', () async {
    final s = makeService();
    final r = await s.autoAlign();
    expect(r.ok, isFalse);
    expect(r.message, contains('Play on this phone too'));
  });

  group('the Player side', () {
    test('refuses the commands when the Controller has not joined', () async {
      await expectLater(
        client.sendCommand('groupCalibrate', {'step': 'start'}),
        throwsA(isA<ControllerException>()
            .having((e) => e.message, 'message', contains('Play on this phone too'))),
      );
      expect(queueTitles(), ['One', 'Two', 'Three']);
    });

    test('refuses an unknown step', () async {
      await client.setGroupJoin(true);
      await expectLater(client.sendCommand('groupCalibrate', {'step': 'dance'}),
          throwsA(isA<ControllerException>()));
    });

    test('the click track can be downloaded only while a test is running', () async {
      await client.setGroupJoin(true);
      final req = client.groupAudioRequest(CalibrationTrack.songId)!;

      Future<int> status() async {
        final c = HttpClient();
        try {
          final r = await (await c.getUrl(req.uri)
                ..headers.set('x-rt-session', req.headers['x-rt-session']!)
                ..headers.set('x-rt-token', req.headers['x-rt-token']!))
              .close();
          await r.drain<void>();
          return r.statusCode;
        } finally {
          c.close(force: true);
        }
      }

      expect(await status(), 404, reason: 'no test running');
      await client.sendCommand('groupCalibrate', {'step': 'start'});
      expect(await status(), 200);
      await client.sendCommand('groupCalibrate', {'step': 'end'});
      expect(await status(), 404);
    });

    test('the click track file is the one both phones use', () async {
      await client.setGroupJoin(true);
      await client.sendCommand('groupCalibrate', {'step': 'start'});
      final req = client.groupAudioRequest(CalibrationTrack.songId)!;
      final c = HttpClient();
      final res = await (await c.getUrl(req.uri)
            ..headers.set('x-rt-session', req.headers['x-rt-session']!)
            ..headers.set('x-rt-token', req.headers['x-rt-token']!))
          .close();
      final body = <int>[];
      await for (final chunk in res) {
        body.addAll(chunk);
      }
      c.close(force: true);
      expect(body, CalibrationTrack.wavBytes());
      await client.sendCommand('groupCalibrate', {'step': 'end'});
    });

    test('ending twice, or ending without a start, is harmless', () async {
      await client.setGroupJoin(true);
      await client.sendCommand('groupCalibrate', {'step': 'end'});
      await client.sendCommand('groupCalibrate', {'step': 'start'});
      await client.sendCommand('groupCalibrate', {'step': 'end'});
      await client.sendCommand('groupCalibrate', {'step': 'end'});
      expect(queueTitles(), ['One', 'Two', 'Three']);
    });

    test('starting twice does not pile up click tracks', () async {
      await client.setGroupJoin(true);
      await client.sendCommand('groupCalibrate', {'step': 'start'});
      await client.sendCommand('groupCalibrate', {'step': 'start'});
      expect(queueTitles().where((t) => t.startsWith('Sync test')).length, 1);
      await client.sendCommand('groupCalibrate', {'step': 'end'});
      expect(queueTitles(), ['One', 'Two', 'Three']);
    });

    test('the click track is never saved with the queue', () async {
      final store = DriftQueueStore(db);
      final saver = QueuePlaybackEngine(
          backend: FakeAudioBackend(), fileExists: (_) => true, queueStore: store);
      await saver.playSongs([
        PlayableSong(
            id: CalibrationTrack.songId,
            title: 'Sync test',
            artist: 'x',
            album: 'y',
            filePath: '${tmp.path}/rt_calibration.wav'),
        (await repo.songsByIds([ids['One']!])).first.toPlayable()!,
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await saver.dispose();
      final loaded = await store.load();
      expect([for (final s in loaded.songs) s.title], ['One']);
    });
  });
}
