import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/protocol/protocol.dart';
import '../controller/controller_client.dart';
import 'calibration_analysis.dart';
import 'calibration_track.dart';
import 'group_follower_core.dart';
import 'group_models.dart';
import 'mic_recorder.dart';

/// What [GroupCalibrator] needs from the follower service.
abstract class CalibrationHost {
  GroupFollowerCore? get core;
  ControllerClient get client;
  bool get isOn;
  String get route;
  int get nudgeMs;
  Future<void> setNudgeMs(int ms);
}

/// "Auto-align": measures with the microphone how much later (or earlier) this
/// phone sounds than the Player, and corrects the fine-tune by that much.
///
///  1. The Player plays a click track (through the normal group-play path).
///  2. This phone, muted but in step, records the microphone while the Player's
///     clicks play; then the Player mutes itself, this phone unmutes, and its
///     clicks are recorded in the same way.
///  3. Both trains are located in the recording to a fraction of a millisecond
///     ([measureSyncOffset]); the microphone's own delay cancels out because it
///     is the same for both.
///  4. The fine-tune is moved by the difference. Running it again measures what
///     is left, so it can be repeated to check.
///
/// Everything it changes on the Player (queue, volume) is put back afterwards,
/// including when something goes wrong half way.
class GroupCalibrator {
  GroupCalibrator({
    required this.host,
    MicRecorder? recorder,
    this.waitForMedia,
    this.analyze,
    this.startTimeout = const Duration(seconds: 25),
  }) : _recorder = recorder ?? RecordMicRecorder();

  final CalibrationHost host;
  final MicRecorder _recorder;

  /// Waits until the track has played to this many seconds. Tests replace it.
  final Future<void> Function(double mediaSeconds)? waitForMedia;

  /// Analyses the recording. Tests replace it; the default runs the heavy
  /// maths off the main thread.
  final Future<SyncMeasurement> Function(Float64List recording)? analyze;

  final Duration startTimeout;
  bool _cancelled = false;

  /// Stops it as soon as possible (everything is put back).
  void cancel() => _cancelled = true;

  Future<void> _command(String step) =>
      host.client.sendCommand(RemoteActions.groupCalibrate, {'step': step});

  /// Waits until the click track is loaded and has played to [seconds]. The
  /// song must really be the click track: an earlier song that happens to be
  /// past that position does not count.
  Future<void> _defaultWait(double seconds, {required Duration limit}) async {
    final end = DateTime.now().add(limit);
    var lastPlaying = DateTime.now();
    while (true) {
      if (_cancelled) throw CalibrationCancelled();
      final core = host.core;
      if (core == null || !host.isOn) {
        throw CalibrationFailed('Group play stopped during the test.');
      }
      if (core.isPlayingAlong) lastPlaying = DateTime.now();
      if (core.isPlayingAlong &&
          core.loadedSongId == CalibrationTrack.songId &&
          core.positionMs / 1000.0 >= seconds) {
        return;
      }
      if (DateTime.now().difference(lastPlaying) > const Duration(seconds: 6) &&
          seconds > 0.1) {
        throw CalibrationFailed(
            "This phone isn't playing along with the Player right now, so the "
            'test cannot run. Wait until the card says "Playing in sync".');
      }
      if (DateTime.now().isAfter(end)) {
        throw CalibrationFailed('The sync test took too long. Please try again.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _waitMedia(double s, {Duration? limit}) =>
      waitForMedia != null
          ? waitForMedia!(s)
          : _defaultWait(s, limit: limit ?? const Duration(seconds: 30));

  Future<SyncMeasurement> _analyze(Float64List rec) => analyze != null
      ? analyze!(rec)
      : Isolate.run(() => measureSyncOffset(rec));

  /// Runs the whole measurement. Never throws for "normal" problems: they come
  /// back as a [CalibrationReport] with a plain-language message.
  Future<CalibrationReport> run({void Function(String)? onProgress}) async {
    void say(String s) => onProgress?.call(s);
    final core = host.core;
    if (!host.isOn || core == null) {
      return const CalibrationReport(
          ok: false,
          message: 'Switch on "Play on this phone too" first, and wait until it '
              'says "Playing in sync".');
    }
    if (host.route == 'bluetooth') {
      return const CalibrationReport(
          ok: false,
          message: 'The sound is going to Bluetooth, whose delay keeps changing. '
              'Use the phone speaker, then try again.');
    }
    bool allowed;
    try {
      allowed = await _recorder.ensurePermission();
    } catch (_) {
      allowed = false;
    }
    if (!allowed) {
      return const CalibrationReport(
          ok: false,
          message: 'Auto-align needs the microphone. Allow it in Android '
              'settings (RemoteTunes > Permissions) and try again.');
    }

    _cancelled = false;
    Float64List? samples;
    var started = false;
    try {
      say('Put the two phones side by side, about 10 cm apart. Starting…');
      await _recorder.start();
      await _command('start');
      started = true;
      await core.setMuted(true);

      say('Listening to the Player… keep quiet.');
      // Wait for the track to be playing along, then for the Player's part.
      await _waitMedia(CalibrationTrack.playerWindow.start,
          limit: startTimeout + const Duration(seconds: 10));
      await _waitMedia(CalibrationTrack.mutePlayerAt);
      await _command('mutePlayer');
      await _waitMedia(CalibrationTrack.unmuteFollowerAt);
      await core.setMuted(false);

      say('Listening to this phone…');
      await _waitMedia(CalibrationTrack.endAt);
    } on CalibrationCancelled {
      await _finish(started);
      await _stopRecorder();
      return const CalibrationReport(ok: false, message: 'Cancelled.');
    } on CalibrationFailed catch (e) {
      await _finish(started);
      await _stopRecorder();
      return CalibrationReport(ok: false, message: e.message);
    } on ControllerException catch (e) {
      await _finish(started);
      await _stopRecorder();
      return CalibrationReport(ok: false, message: e.message);
    } catch (_) {
      await _finish(started);
      await _stopRecorder();
      return const CalibrationReport(
          ok: false, message: "The sync test couldn't run. Please try again.");
    }

    samples = await _stopRecorder();
    await _finish(started);

    say('Working out the difference…');
    final SyncMeasurement m;
    try {
      m = await _analyze(samples);
    } catch (_) {
      return const CalibrationReport(
          ok: false, message: "Couldn't work out the result. Please try again.");
    }
    if (!m.ok) {
      return CalibrationReport(ok: false, message: m.problem ?? 'No result.');
    }

    final before = host.nudgeMs;
    final measured = m.offsetMs!;
    final after = (before + measured.round()).clamp(-300, 300);
    await host.setNudgeMs(after);
    final late = measured > 0;
    final abs = measured.abs();
    final text = abs < 3
        ? 'Already lined up: this phone is within ${abs.toStringAsFixed(1)} ms of '
            'the Player. Left the fine-tune at ${after > 0 ? '+' : ''}$after ms.'
        : 'This phone was ${abs.toStringAsFixed(1)} ms ${late ? 'late' : 'early'}. '
            'Fine-tune set to ${after > 0 ? '+' : ''}$after ms. Run it again to '
            'check.';
    return CalibrationReport(
      ok: true,
      message: text,
      offsetMs: measured,
      nudgeMs: after,
      clamped: after != before + measured.round(),
    );
  }

  Future<Float64List> _stopRecorder() async {
    try {
      return await _recorder.stop();
    } catch (_) {
      return Float64List(0);
    }
  }

  /// Puts everything back: this phone's volume, and the Player's queue and
  /// volume.
  Future<void> _finish(bool started) async {
    try {
      await host.core?.setMuted(false);
    } catch (_) {}
    if (started) {
      try {
        await _command('end');
      } catch (_) {}
    }
  }

  Future<void> dispose() => _recorder.dispose();
}

class CalibrationCancelled implements Exception {}

class CalibrationFailed implements Exception {
  CalibrationFailed(this.message);
  final String message;
}
