import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/group/calibration_analysis.dart';
import 'package:remote_tunes/features/group/calibration_track.dart';

import 'helpers/synthetic_recording.dart';

const fs = CalibrationTrack.sampleRate;

void main() {
  group('the test sound', () {
    test('two different, irregular click trains in their own windows', () {
      final p = CalibrationTrack.playerClicks;
      final f = CalibrationTrack.followerClicks;
      expect(p.length, greaterThanOrEqualTo(12));
      expect(f.length, greaterThanOrEqualTo(12));
      expect(p.first, greaterThanOrEqualTo(CalibrationTrack.playerWindow.start));
      expect(p.last, lessThan(CalibrationTrack.playerWindow.end));
      expect(f.first, greaterThanOrEqualTo(CalibrationTrack.followerWindow.start));
      expect(f.last, lessThan(CalibrationTrack.followerWindow.end));
      // Irregular, so the pattern is unique.
      final gaps = [for (var i = 1; i < p.length; i++) p[i] - p[i - 1]];
      expect(gaps.reduce(max) - gaps.reduce(min), greaterThan(0.08));
      // The two phones make the very same trains every time.
      expect(CalibrationTrack.playerClicks, p);
    });

    test('quiet between the windows, so the muting has time to happen', () {
      final s = CalibrationTrack.samples();
      double energy(double a, double b) {
        var e = 0.0;
        for (var i = (a * fs).round(); i < (b * fs).round(); i++) {
          e += s[i] * s[i];
        }
        return e;
      }

      expect(energy(0, 4.0), 0);
      expect(energy(8.0, 10.0), 0);
      expect(energy(14.0, 17.0), 0);
      expect(energy(4.0, 8.0), greaterThan(0));
      expect(energy(10.0, 14.0), greaterThan(0));
    });

    test('the mute and unmute moments fall in the quiet gap', () {
      expect(CalibrationTrack.mutePlayerAt, inInclusiveRange(8.0, 10.0));
      expect(CalibrationTrack.unmuteFollowerAt, inInclusiveRange(8.0, 10.0));
      expect(CalibrationTrack.mutePlayerAt, lessThan(CalibrationTrack.unmuteFollowerAt),
          reason: 'the Player goes quiet before this phone comes on');
    });

    test('it is a valid 16-bit mono WAV file', () {
      final w = CalibrationTrack.wavBytes();
      final d = ByteData.sublistView(w);
      expect(String.fromCharCodes(w.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(w.sublist(8, 12)), 'WAVE');
      expect(d.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(d.getUint32(24, Endian.little), fs);
      expect(d.getUint16(34, Endian.little), 16);
      expect(d.getUint32(40, Endian.little), CalibrationTrack.samples().length * 2);
      expect(w.length, 44 + CalibrationTrack.samples().length * 2);
    });
  });

  group('measuring how much later this phone sounds', () {
    void expectOffset(SyncMeasurement m, double expected, {double within = 0.3}) {
      expect(m.problem, isNull, reason: m.problem);
      expect(m.offsetMs!, closeTo(expected, within));
    }

    test('this phone 42 ms late', () {
      final m = measureSyncOffset(
          syntheticRecording(playerLatencyMs: 83, followerLatencyMs: 125));
      expectOffset(m, 42);
      expect(m.playerConfidence, greaterThan(minConfidence));
      expect(m.followerConfidence, greaterThan(minConfidence));
    });

    test('this phone 25 ms early (negative)', () {
      expectOffset(
          measureSyncOffset(syntheticRecording(playerLatencyMs: 140, followerLatencyMs: 115)), -25);
    });

    test('already in step: about zero', () {
      expectOffset(
          measureSyncOffset(syntheticRecording(playerLatencyMs: 90, followerLatencyMs: 90)), 0);
    });

    test('a big 180 ms difference, with a long wait before the track began', () {
      expectOffset(
          measureSyncOffset(syntheticRecording(
              playerLatencyMs: 60, followerLatencyMs: 240, leadSeconds: 3.4)),
          180);
    });

    test('room noise, echoes and very different loudness do not fool it', () {
      final m = measureSyncOffset(syntheticRecording(
        playerLatencyMs: 70,
        followerLatencyMs: 118,
        playerGain: 0.08,
        followerGain: 0.6,
        noise: 0.06,
        echo: true,
      ));
      expectOffset(m, 48, within: 0.6);
    });

    test('one phone far louder than the other: the loud one does not drown the faint',
        () {
      final m = measureSyncOffset(syntheticRecording(
        playerLatencyMs: 95,
        followerLatencyMs: 61,
        playerGain: 0.05,
        followerGain: 0.8,
        noise: 0.02,
      ));
      expectOffset(m, -34, within: 0.5);
    });

    test('the other way: a loud Player and a faint phone', () {
      final m = measureSyncOffset(syntheticRecording(
        playerLatencyMs: 70,
        followerLatencyMs: 111,
        playerGain: 0.8,
        followerGain: 0.05,
        noise: 0.02,
      ));
      expectOffset(m, 41, within: 0.5);
    });

    test('a phone whose speaker is wired the other way round (inverted) is fine', () {
      expectOffset(
          measureSyncOffset(syntheticRecording(
              playerLatencyMs: 80, followerLatencyMs: 101, followerInverted: true)),
          21);
    });

    test('nothing recorded: a plain message', () {
      final m = measureSyncOffset(Float64List(fs * 16));
      expect(m.ok, isFalse);
      expect(m.problem, contains('microphone'));
    });

    test('only noise: it says it could not hear the clicks, and gives no number', () {
      final rnd = Random(5);
      final noise = Float64List(fs * 17)..setAll(0, [for (var i = 0; i < fs * 17; i++) (rnd.nextDouble() - 0.5) * 0.2]);
      final m = measureSyncOffset(noise);
      expect(m.ok, isFalse);
      expect(m.problem, contains("Couldn't hear"));
    });

    test('the Player was not heard: it says so (no wrong number)', () {
      final m = measureSyncOffset(syntheticRecording(
          playerLatencyMs: 80, followerLatencyMs: 120, playerSilent: true, noise: 0.01));
      expect(m.ok, isFalse);
      expect(m.problem, contains("Player's clicks"));
    });

    test('a recording that is too short is refused', () {
      final m = measureSyncOffset(Float64List(fs * 3)..[100] = 0.5);
      expect(m.ok, isFalse);
    });
  });

  group('locating a sound (the correlation itself)', () {
    test('finds a template placed at a known time to a fraction of a millisecond', () {
      // A recording that is silence, then the clicks starting exactly 2.5 s in.
      final tmpl = CalibrationTrack.segment(CalibrationTrack.playerWindow);
      final rec = Float64List((fs * 12).round());
      final at = (2.5 * fs).round();
      rec.setRange(at, at + tmpl.length, tmpl);
      final r = locateOne(rec, tmpl, fs)!;
      expect(r.startSeconds, closeTo(2.5, 0.0001));
      expect(r.confidence, greaterThan(minConfidence));
    });
  });
}
