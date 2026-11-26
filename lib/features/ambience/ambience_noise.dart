import 'dart:math';
import 'dart:typed_data';

enum NoiseColor { white, pink, brown }

/// Which noise a built-in sound is, or null.
NoiseColor? noiseColorOf(String soundId) => switch (soundId) {
      'white-noise' => NoiseColor.white,
      'pink-noise' => NoiseColor.pink,
      'brown-noise' => NoiseColor.brown,
      _ => null,
    };

const noiseSampleRate = 44100;

/// A loop of noise as a 16-bit mono WAV file. White is flat hiss; pink is softer (like steady rain);
/// brown is deep (like a far waterfall). All three are made equally strong, and the end runs into the
/// start, so it loops without a click.
Uint8List noiseWav(NoiseColor color, {int seconds = 20, Random? random}) {
  final r = random ?? Random(7);
  final n = noiseSampleRate * seconds;
  final overlap = min(noiseSampleRate, n ~/ 4);
  final raw = Float64List(n + overlap);
  var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0, brown = 0.0;
  // The filters settle first, so the start sounds like the rest.
  for (var i = -noiseSampleRate; i < raw.length; i++) {
    final white = r.nextDouble() * 2 - 1;
    final double v;
    switch (color) {
      case NoiseColor.white:
        v = white;
      case NoiseColor.pink: // Paul Kellet's filter
        b0 = 0.99886 * b0 + white * 0.0555179;
        b1 = 0.99332 * b1 + white * 0.0750759;
        b2 = 0.96900 * b2 + white * 0.1538520;
        b3 = 0.86650 * b3 + white * 0.3104856;
        b4 = 0.55000 * b4 + white * 0.5329522;
        b5 = -0.7616 * b5 - white * 0.0168980;
        v = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362;
        b6 = white * 0.115926;
      case NoiseColor.brown:
        brown = (brown + 0.02 * white) / 1.02;
        v = brown;
    }
    if (i >= 0) raw[i] = v;
  }

  // The extra at the end is blended into the start: the last sample then leads into the first.
  final loop = Float64List(n);
  for (var i = 0; i < n; i++) {
    if (i < overlap) {
      final t = i / overlap;
      loop[i] = raw[i] * sin(t * pi / 2) + raw[n + i] * cos(t * pi / 2);
    } else {
      loop[i] = raw[i];
    }
  }

  var sum = 0.0;
  for (final v in loop) {
    sum += v * v;
  }
  final strength = sqrt(sum / n);
  final gain = strength == 0 ? 0.0 : 0.18 / strength;

  final data = ByteData(44 + n * 2);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, noiseSampleRate, Endian.little);
  data.setUint32(28, noiseSampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    data.setInt16(44 + i * 2, (loop[i] * gain * 32767).round().clamp(-32767, 32767), Endian.little);
  }
  return data.buffer.asUint8List();
}
