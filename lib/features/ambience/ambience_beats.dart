/// Binaural beats the app makes itself: a pure tone for each ear, a little apart. The brain hears the
/// difference as a slow beat, which only works when each ear gets its own tone (stereo headphones).
/// Plain code, shared by the playing phone and the one controlling it.
library;

import 'dart:math';
import 'dart:typed_data';

const ambienceBeatCategory = 'Binaural Beats';

/// The tone both ears are built around, in Hz.
const beatCarrier = 200.0;

/// Sound id to the beat (the difference between the ears), in Hz.
const ambienceBeats = <String, double>{
  'beat-deep-sleep': 0.5,
  'beat-sleep': 1.5,
  'beat-relaxation': 2.5,
  'beat-calm': 3.5,
  'beat-meditation': 4.5,
  'beat-intuition': 5.5,
  'beat-creativity': 7.5,
  'beat-focus': 8,
  'beat-alert': 10.5,
};

bool isAmbienceBeat(String soundId) => ambienceBeats.containsKey(soundId);

/// Whether the sounds of a group are for headphones.
bool ambienceNeedsHeadphones(String? category) => category == ambienceBeatCategory;

/// The two tones of a beat sound, or null.
({double left, double right})? beatTones(String soundId) {
  final beat = ambienceBeats[soundId];
  return beat == null ? null : (left: beatCarrier - beat / 2, right: beatCarrier + beat / 2);
}

/// A loop of a beat as a 16-bit stereo WAV file. Four seconds hold a whole number of waves in each ear
/// for beats in steps of half a Hz, so it loops without a click.
Uint8List beatWav(double beat, {double carrier = beatCarrier, int seconds = 4, double amplitude = 0.25}) {
  const rate = 44100;
  final left = carrier - beat / 2, right = carrier + beat / 2;
  final frames = rate * seconds;
  final data = ByteData(44 + frames * 4);

  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + frames * 4, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 2, Endian.little); // left and right
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 4, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, frames * 4, Endian.little);
  for (var i = 0; i < frames; i++) {
    final t = i / rate;
    data.setInt16(44 + i * 4, (sin(2 * pi * left * t) * amplitude * 32767).round(), Endian.little);
    data.setInt16(46 + i * 4, (sin(2 * pi * right * t) * amplitude * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
