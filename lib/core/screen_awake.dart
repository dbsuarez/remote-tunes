import 'package:flutter/services.dart';

/// Keeps the screen on while a long job runs (adding music, reading tags), so
/// the phone does not lock and pause it halfway. Jobs can overlap: the screen
/// is released when the last one lets go.
class ScreenAwake {
  ScreenAwake._();

  static const _channel = MethodChannel('remotetunes/group');
  static int _holds = 0;

  /// How many jobs are holding the screen on (for tests).
  static int get holds => _holds;

  /// Turns the screen-on flag by hand (tests replace this).
  static Future<void> Function(bool on) setFlag = _setNative;

  static Future<void> _setNative(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } catch (_) {
      // Not on Android (tests), or the phone refused: the job still runs.
    }
  }

  /// Runs [job] with the screen kept on, and lets go afterwards whatever
  /// happens.
  static Future<T> during<T>(Future<T> Function() job) async {
    if (_holds++ == 0) await setFlag(true);
    try {
      return await job();
    } finally {
      if (--_holds == 0) await setFlag(false);
    }
  }
}
