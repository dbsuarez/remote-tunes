import 'package:flutter/services.dart';

/// Where the sound of a song stops, and how long its file is.
typedef SoundEnd = ({int endMs, int durationMs});

/// Asks the phone where a song falls silent (Android decodes the end of the file). Answers are kept
/// while the app runs.
class SilenceFinder {
  static const _channel = MethodChannel('remotetunes/silence');

  final _known = <String, SoundEnd?>{};

  Future<SoundEnd?> find(String path) async {
    if (_known.containsKey(path)) return _known[path];
    SoundEnd? found;
    try {
      final j = await _channel.invokeMapMethod<String, Object?>('soundEnd', {'path': path});
      final end = j?['end'], duration = j?['duration'];
      if (end is int && duration is int) found = (endMs: end, durationMs: duration);
    } catch (_) {
      return null; // Not on this phone, or it failed this time: tried again next time.
    }
    return _known[path] = found;
  }
}
