import 'dart:math' as math;
import 'dart:typed_data';

/// The sound used by Auto-align: two trains of short, sharp chirps with
/// different, irregular timing, separated by quiet.
///
/// Both phones play this file through the normal group-play path. During the
/// first train only the Player is audible (this phone is muted), during the
/// second only this phone (the Player is muted). Hearing both through one
/// microphone, the time between the two trains tells exactly how much later
/// (or earlier) this phone sounds than the Player, with the microphone's own
/// delay cancelling out because it is the same in both.
///
/// A chirp has a very sharp correlation peak, and the irregular spacing makes
/// the train's pattern unique, so each train can be located in the recording to
/// a fraction of a millisecond, even with some room noise.
class CalibrationTrack {
  CalibrationTrack._();

  static const int sampleRate = 44100;

  /// Library id used for this track in group play (never a real song id).
  static const int songId = -1;

  /// The whole track is this long (seconds).
  static const double seconds = 17.0;

  /// Only the Player is audible during this window (media time, seconds).
  static const playerWindow = (start: 4.0, end: 8.0);

  /// Only this phone is audible during this window.
  static const followerWindow = (start: 10.0, end: 14.0);

  /// When this phone sends "mute the Player" (media time).
  static const mutePlayerAt = 8.6;

  /// When this phone unmutes itself (the Player is already silent).
  static const unmuteFollowerAt = 9.2;

  /// When recording can stop.
  static const endAt = 14.8;

  /// Chirp: sweeps from [chirpFrom] to [chirpTo] Hz in [chirpMs] ms.
  static const double chirpFrom = 1200;
  static const double chirpTo = 9000;
  static const double chirpMs = 5;

  static Float64List _chirp() {
    final n = (sampleRate * chirpMs / 1000).round();
    final out = Float64List(n);
    final k = (chirpTo - chirpFrom) / (chirpMs / 1000);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final phase = 2 * math.pi * (chirpFrom * t + 0.5 * k * t * t);
      final hann = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      out[i] = 0.9 * hann * math.sin(phase);
    }
    return out;
  }

  /// The click times (seconds) of one train: irregular gaps of 0.16 to 0.34 s,
  /// from a fixed generator so every phone makes the identical train.
  static List<double> _times(({double start, double end}) w, int seed) {
    var state = seed;
    double next() {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      return state / 0x7fffffff;
    }

    final times = <double>[];
    var t = w.start + 0.1;
    while (t < w.end - 0.1) {
      times.add(t);
      t += 0.16 + 0.18 * next();
    }
    return times;
  }

  /// Click times of the Player's train and of this phone's train (seconds).
  static List<double> get playerClicks => _times(playerWindow, 12345);
  static List<double> get followerClicks => _times(followerWindow, 67890);

  static Float64List? _cache;

  /// The whole track, mono, -1 to 1.
  static Float64List samples() {
    final cached = _cache;
    if (cached != null) return cached;
    final total = (seconds * sampleRate).round();
    final out = Float64List(total);
    final chirp = _chirp();
    for (final t in [...playerClicks, ...followerClicks]) {
      final at = (t * sampleRate).round();
      for (var i = 0; i < chirp.length && at + i < total; i++) {
        out[at + i] += chirp[i];
      }
    }
    return _cache = out;
  }

  /// The part of the track in [w] (what the matched filter looks for).
  static Float64List segment(({double start, double end}) w) {
    final all = samples();
    final from = (w.start * sampleRate).round();
    final to = (w.end * sampleRate).round();
    return Float64List.sublistView(all, from, to.clamp(from, all.length));
  }

  /// The track as a 16-bit mono WAV file (what is played).
  static Uint8List wavBytes() {
    final s = samples();
    final data = ByteData(44 + s.length * 2);
    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        data.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + s.length * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, s.length * 2, Endian.little);
    for (var i = 0; i < s.length; i++) {
      data.setInt16(44 + i * 2, (s[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
