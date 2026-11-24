import 'dart:math' as math;
import 'dart:typed_data';

import 'calibration_track.dart';

/// Where a known sound was found in a recording.
class Alignment {
  const Alignment({required this.startSeconds, required this.confidence});

  /// Recording time at which the template starts, in seconds (sub-sample).
  final double startSeconds;

  /// How much stronger the best match is than the next best (separated)
  /// match. About 1 means "could be anywhere"; above ~3 means "found it".
  final double confidence;
}

/// The result of measuring how much later this phone sounds than the Player.
class SyncMeasurement {
  const SyncMeasurement({
    this.offsetMs,
    this.playerConfidence = 0,
    this.followerConfidence = 0,
    this.problem,
  });

  /// Positive: this phone sounds LATER than the Player. Negative: earlier.
  final double? offsetMs;
  final double playerConfidence;
  final double followerConfidence;

  /// Plain-language reason when no measurement could be made.
  final String? problem;

  bool get ok => offsetMs != null;
}

/// A best match must be at least this much stronger than the next best.
const double minConfidence = 3.0;

int _nextPow2(int n) {
  var p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}

/// Averages neighbouring samples in pairs: half the sample rate, with a gentle
/// low-pass, so the correlation is four times cheaper.
Float64List _halve(Float64List x) {
  final out = Float64List(x.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = (x[2 * i] + x[2 * i + 1]) / 2;
  }
  return out;
}

/// Cross-correlates one recording with several templates. The recording's FFT is
/// computed once and reused.
class Correlator {
  Correlator(Float64List recording, int sampleRate, int longestTemplate)
      : fs = sampleRate / 2.0,
        _rec = _halve(recording) {
    _n = _nextPow2(_rec.length + longestTemplate ~/ 2 + 1);
    _cos = Float64List(_n ~/ 2);
    _sin = Float64List(_n ~/ 2);
    for (var k = 0; k < _n ~/ 2; k++) {
      final a = 2 * math.pi * k / _n;
      _cos[k] = math.cos(a);
      _sin[k] = math.sin(a);
    }
    _rr = Float64List(_n)..setRange(0, _rec.length, _rec);
    _ri = Float64List(_n);
    _fft(_rr, _ri, inverse: false);
    _tr = Float64List(_n);
    _ti = Float64List(_n);
  }

  /// Sample rate the correlation runs at (half the recording's).
  final double fs;
  final Float64List _rec;
  late final int _n;
  late final Float64List _cos;
  late final Float64List _sin;
  late final Float64List _rr;
  late final Float64List _ri;
  late final Float64List _tr;
  late final Float64List _ti;

  /// In-place iterative radix-2 FFT of [re] + i[im] (length a power of two).
  void _fft(Float64List re, Float64List im, {required bool inverse}) {
    final n = re.length;
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final stride = n ~/ len;
      for (var i = 0; i < n; i += len) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * stride];
          final wi = inverse ? _sin[k * stride] : -_sin[k * stride];
          final a = i + k;
          final b = a + half;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
    if (inverse) {
      for (var i = 0; i < n; i++) {
        re[i] /= n;
        im[i] /= n;
      }
    }
  }

  /// Where [template] (at the recording's full sample rate) starts in the
  /// recording, searching only start times from [from] to [to] seconds.
  Alignment? locate(Float64List template, {double? from, double? to}) {
    final t = _halve(template);
    if (t.isEmpty || _rec.length < t.length) return null;
    _tr.fillRange(0, _n, 0);
    _ti.fillRange(0, _n, 0);
    _tr.setRange(0, t.length, t);
    _fft(_tr, _ti, inverse: false);
    // recording * conj(template): the correlation at every shift.
    for (var i = 0; i < _n; i++) {
      final a = _rr[i];
      final b = _ri[i];
      final c = _tr[i];
      final d = -_ti[i];
      _tr[i] = a * c - b * d;
      _ti[i] = a * d + b * c;
    }
    _fft(_tr, _ti, inverse: true);

    final maxAll = _rec.length - t.length;
    final minLag = from == null ? 0 : math.max(0, (from * fs).round());
    final maxLag = to == null ? maxAll : math.min(maxAll, (to * fs).round());
    if (minLag >= maxLag) return null;

    var best = minLag;
    var bestV = 0.0;
    for (var k = minLag; k <= maxLag; k++) {
      final v = _tr[k].abs();
      if (v > bestV) {
        bestV = v;
        best = k;
      }
    }
    if (bestV <= 0) return null;

    // The direct sound arrives first; room echoes and speaker ringing come a
    // little later and can be stronger in the correlation. So if there is a
    // nearly-as-strong peak shortly before the best one, that is the real
    // arrival.
    final lookBack = (0.04 * fs).round();
    for (var k = math.max(minLag + 1, best - lookBack); k < best; k++) {
      final v = _tr[k].abs();
      if (v >= 0.6 * bestV && v >= _tr[k - 1].abs() && v >= _tr[k + 1].abs()) {
        best = k;
        bestV = v;
        break;
      }
    }
    // The best match elsewhere. Echoes within 60 ms belong to the same
    // arrival, so they do not count as a competing match.
    final exclude = (0.06 * fs).round();
    var second = 0.0;
    for (var k = minLag; k <= maxLag; k++) {
      if ((k - best).abs() <= exclude) continue;
      final v = _tr[k].abs();
      if (v > second) second = v;
    }
    // Sub-sample position: a parabola through the peak and its neighbours.
    var frac = 0.0;
    if (best > minLag && best < maxLag) {
      final y0 = _tr[best - 1].abs();
      final y1 = bestV;
      final y2 = _tr[best + 1].abs();
      final denom = y0 - 2 * y1 + y2;
      if (denom != 0) frac = (0.5 * (y0 - y2) / denom).clamp(-0.5, 0.5);
    }
    return Alignment(
      startSeconds: (best + frac) / fs,
      confidence: second <= 0 ? 1e9 : bestV / second,
    );
  }
}

/// Finds where [template] starts inside [recording] (both at [sampleRate] Hz).
Alignment? locateOne(Float64List recording, Float64List template, int sampleRate,
    {double? from, double? to}) {
  return Correlator(recording, sampleRate, template.length)
      .locate(template, from: from, to: to);
}

/// Works out how much later (+) or earlier (-) this phone sounded than the
/// Player, from a mono microphone recording of the Auto-align track
/// ([CalibrationTrack]) played as described there.
///
/// Two steps, so that a loud phone cannot be mistaken for a faint one:
///  1. Find where the track as a whole sits in the recording (the louder train
///     leads; that is only needed roughly).
///  2. Look for each train only close to where it must then be (the two trains
///     are 6 s apart, far from each other's cross-talk), and compare.
SyncMeasurement measureSyncOffset(Float64List recording,
    {int sampleRate = CalibrationTrack.sampleRate}) {
  // Is there anything to hear at all?
  var peak = 0.0;
  for (final v in recording) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  if (recording.length < sampleRate * 8 || peak < 0.002) {
    return const SyncMeasurement(
      problem: "The microphone didn't pick up anything. Allow the microphone, "
          'and hold the phones close together in a quiet room.',
    );
  }

  const pw = CalibrationTrack.playerWindow;
  const fw = CalibrationTrack.followerWindow;
  final whole = CalibrationTrack.segment((start: pw.start, end: fw.end));
  final a = CalibrationTrack.segment(pw);
  final b = CalibrationTrack.segment(fw);
  final corr = Correlator(recording, sampleRate, whole.length);

  // Step 1: where does the whole thing start? The recording began before the
  // track (up to a few seconds), and the sound takes under a second to come out.
  final coarse = corr.locate(whole, from: pw.start - 0.2, to: pw.start + 6.0);
  if (coarse == null || coarse.confidence < 1.3) {
    return const SyncMeasurement(
      problem: "Couldn't hear the clicks clearly. Turn both phones' volume up, "
          'put them side by side (about 10 cm apart) and keep the room quiet.',
    );
  }
  final l0 = coarse.startSeconds;
  const slack = 0.7;

  // Step 2: each train near where it must be.
  final pa = corr.locate(a, from: l0 - slack, to: l0 + slack);
  final gap = fw.start - pw.start;
  final fb = corr.locate(b, from: l0 + gap - slack, to: l0 + gap + slack);
  if (pa == null || fb == null) {
    return const SyncMeasurement(
        problem: 'The recording was too short. Please try again.');
  }
  if (pa.confidence < minConfidence && fb.confidence < minConfidence) {
    return SyncMeasurement(
      playerConfidence: pa.confidence,
      followerConfidence: fb.confidence,
      problem: "Couldn't hear the clicks clearly. Turn both phones' volume up, "
          'put them side by side (about 10 cm apart) and keep the room quiet.',
    );
  }
  if (pa.confidence < minConfidence) {
    return SyncMeasurement(
      playerConfidence: pa.confidence,
      followerConfidence: fb.confidence,
      problem: "Couldn't hear the Player's clicks clearly. Turn the Player's "
          'volume up and put the phones closer together.',
    );
  }
  if (fb.confidence < minConfidence) {
    return SyncMeasurement(
      playerConfidence: pa.confidence,
      followerConfidence: fb.confidence,
      problem: "Couldn't hear this phone's clicks clearly. Turn its volume up "
          'and try again.',
    );
  }
  // The second train should come exactly `gap` after the first. The
  // difference is how much later this phone sounded.
  final offset = ((fb.startSeconds - pa.startSeconds) - gap) * 1000;
  if (offset.abs() > 600) {
    return SyncMeasurement(
      playerConfidence: pa.confidence,
      followerConfidence: fb.confidence,
      problem: 'The two phones are too far apart in time for this measurement '
          '(${offset.round()} ms). Try again; if it keeps happening, switch '
          'group play off and on first.',
    );
  }
  return SyncMeasurement(
    offsetMs: offset,
    playerConfidence: pa.confidence,
    followerConfidence: fb.confidence,
  );
}
