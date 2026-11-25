import 'package:remote_tunes/features/player/eq/equalizer_controller.dart';

/// Equalizer settings kept in memory (tests).
class MemoryEqStore implements EqStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}
