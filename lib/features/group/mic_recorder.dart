import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'calibration_track.dart';

/// Records the microphone for Auto-align. Raw samples only, kept in memory for
/// a few seconds and thrown away after the measurement: nothing is saved or
/// sent anywhere.
abstract class MicRecorder {
  /// Asks for (or checks) the microphone permission.
  Future<bool> ensurePermission();

  /// Starts recording, mono at [CalibrationTrack.sampleRate].
  Future<void> start();

  /// Stops and returns what was recorded, -1 to 1.
  Future<Float64List> stop();

  Future<void> dispose();
}

class RecordMicRecorder implements MicRecorder {
  RecordMicRecorder() : _rec = AudioRecorder();

  final AudioRecorder _rec;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;

  @override
  Future<bool> ensurePermission() => _rec.hasPermission();

  @override
  Future<void> start() async {
    _bytes.clear();
    final stream = await _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: CalibrationTrack.sampleRate,
      numChannels: 1,
      // Any "improvement" by the phone (echo cancelling, noise suppression,
      // automatic gain) would change the very timing being measured.
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.unprocessed,
        manageBluetooth: false,
        // Do not silence the music this phone is playing.
        muteAudio: false,
      ),
    ));
    _sub = stream.listen(_bytes.add);
  }

  @override
  Future<Float64List> stop() async {
    try {
      await _rec.stop();
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    final raw = _bytes.takeBytes();
    final n = raw.length ~/ 2;
    final data = ByteData.sublistView(raw);
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _rec.dispose();
  }
}
