import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/group/calibration_analysis.dart';
import 'package:remote_tunes/features/group/calibration_track.dart';
import 'package:remote_tunes/features/group/group_calibrator.dart';
import 'package:remote_tunes/features/group/group_follower_core.dart';
import 'package:remote_tunes/features/group/group_models.dart';
import 'package:remote_tunes/features/group/mic_recorder.dart';

import 'helpers/fake_audio_backend.dart';

class _Audio implements GroupAudioSource {
  final ready = <int, String>{1: '/cache/1.mp3', CalibrationTrack.songId: '/cache/-1.wav'};
  @override
  String? pathIfReady(int id) => ready[id];
  @override
  Future<void> fetch(int id) async {}
  @override
  String? failureOf(int id) => null;
  @override
  double? progressOf(int id) => null;
}

class _Client extends ControllerClient {
  _Client() : super();
  final steps = <String>[];

  @override
  Future<void> sendCommand(String action, [Map<String, dynamic> params = const {}]) async {
    steps.add('${params['step']}');
  }
}

class _Mic implements MicRecorder {
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<Float64List> stop() async => Float64List(0);
  @override
  Future<void> dispose() async {}
}

class _Host implements CalibrationHost {
  _Host(this.core, this.client);
  @override
  final GroupFollowerCore core;
  @override
  final ControllerClient client;
  @override
  bool get isOn => true;
  @override
  String get route => 'speaker';
  @override
  int nudgeMs = 0;
  @override
  Future<void> setNudgeMs(int ms) async => nudgeMs = ms;
}

void main() {
  late FakeAudioBackend backend;
  late GroupFollowerCore core;
  late _Client client;
  var now = 1000.0;

  GroupSync sync({required int song, required int pos, bool playing = true}) =>
      GroupSync(songId: song, positionMs: pos, atMs: now + 500, playing: playing);

  setUp(() {
    backend = FakeAudioBackend();
    now = 1000.0;
    core = GroupFollowerCore(
      backend: backend,
      audio: _Audio(),
      nowMs: () => now,
      offsetMs: () => 500.0,
      onStatus: (_) {},
    );
    client = _Client();
  });

  test('the Player is not muted while an ordinary song is the one playing, however far '
      'into it', () async {
    // This phone is playing along with a normal song, 70 seconds in.
    await core.onSync(sync(song: 1, pos: 70000));
    expect(core.isPlayingAlong, isTrue);
    expect(core.positionMs, greaterThan(60000));

    final cal = GroupCalibrator(
      host: _Host(core, client),
      recorder: _Mic(),
      analyze: (_) async => const SyncMeasurement(offsetMs: 0),
    );
    final run = cal.run();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(client.steps, ['start'],
        reason: 'position 70 s of another song must not count as the click track');

    // The Player switches to the click track and it plays up to the muting point.
    now += 100;
    await core.onSync(sync(song: CalibrationTrack.songId, pos: 2000));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(client.steps, ['start'], reason: 'only 2 s into the click track');

    now += 100;
    backend.position = const Duration(milliseconds: 8700);
    await core.onSync(sync(song: CalibrationTrack.songId, pos: 8700));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(client.steps, ['start', 'mutePlayer']);

    now += 100;
    backend.position = const Duration(milliseconds: 9300);
    await core.onSync(sync(song: CalibrationTrack.songId, pos: 9300));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(backend.volume, 1.0, reason: 'this phone unmuted after the Player went quiet');

    now += 100;
    backend.position = const Duration(milliseconds: 14900);
    await core.onSync(sync(song: CalibrationTrack.songId, pos: 14900));
    final report = await run.timeout(const Duration(seconds: 5));
    expect(report.ok, isTrue, reason: report.message);
    expect(client.steps, ['start', 'mutePlayer', 'end']);
  });

  test('if the click track never starts, it gives up with a plain message and puts '
      'things back', () async {
    await core.onSync(sync(song: 1, pos: 70000));
    final cal = GroupCalibrator(
      host: _Host(core, client),
      recorder: _Mic(),
      startTimeout: const Duration(milliseconds: 300),
      analyze: (_) async => const SyncMeasurement(offsetMs: 0),
    );
    // Make the follower stop playing along, so the wait cannot succeed.
    await core.onSync(sync(song: 1, pos: 70000, playing: false));
    final report = await cal.run().timeout(const Duration(seconds: 20));
    expect(report.ok, isFalse);
    expect(report.message, anyOf(contains('playing along'), contains('too long')));
    expect(client.steps.last, 'end', reason: 'the Player is told to put things back');
    expect(backend.volume, 1.0);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
