import 'dart:math';
import 'dart:typed_data';

import 'package:remote_tunes/features/group/calibration_track.dart';

const _fs = CalibrationTrack.sampleRate;

/// A microphone recording of the Auto-align track, as it would be heard:
///  * the Player is audible until [CalibrationTrack.mutePlayerAt], this phone
///    from [CalibrationTrack.unmuteFollowerAt];
///  * the Player's sound arrives [playerLatencyMs] after "media time 0" and this
///    phone's [followerLatencyMs] after it (both after [leadSeconds] of
///    recording that came before the track started);
///  * each has its own loudness, optional echoes and background noise.
Float64List syntheticRecording({
  required double playerLatencyMs,
  required double followerLatencyMs,
  double leadSeconds = 1.3,
  double playerGain = 0.3,
  double followerGain = 0.5,
  double noise = 0.0,
  bool echo = false,
  bool followerInverted = false,
  bool playerSilent = false,
  int seed = 1,
}) {
  final track = CalibrationTrack.samples();
  final total = ((leadSeconds + CalibrationTrack.seconds + 1.5) * _fs).round();
  final out = Float64List(total);
  void add(double fromMedia, double toMedia, double latencyMs, double gain, double sign) {
    final delay = ((leadSeconds + latencyMs / 1000) * _fs).round();
    final a = (fromMedia * _fs).round();
    final b = min((toMedia * _fs).round(), track.length);
    for (var j = a; j < b; j++) {
      final at = j + delay;
      if (at < 0 || at >= total) continue;
      out[at] += sign * gain * track[j];
      if (echo) {
        for (final (ms, g) in [(14.0, 0.4), (31.0, 0.25)]) {
          final e = at + (ms * _fs / 1000).round();
          if (e < total) out[e] += sign * gain * g * track[j];
        }
      }
    }
  }

  if (!playerSilent) add(0, CalibrationTrack.mutePlayerAt, playerLatencyMs, playerGain, 1);
  add(CalibrationTrack.unmuteFollowerAt, CalibrationTrack.seconds, followerLatencyMs,
      followerGain, followerInverted ? -1 : 1);

  if (noise > 0) {
    final rnd = Random(seed);
    for (var i = 0; i < total; i++) {
      out[i] += (rnd.nextDouble() * 2 - 1) * noise;
    }
  }
  return out;
}
