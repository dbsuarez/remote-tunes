import 'package:flutter/services.dart';

/// Phone-only helpers for group play (see `GroupSupport.kt`).
abstract class GroupNative {
  /// While [enabled]: the CPU stays awake and the Wi-Fi radio stays in a fast
  /// mode (power saving adds jittery delay). [keepScreenOn] also keeps the
  /// screen on (the Controller phone, which plays along, needs it).
  Future<void> setLocks({required bool enabled, bool keepScreenOn = false});

  /// Where the sound is going: `speaker`, `wired`, `bluetooth` (or `unknown`).
  Future<String> outputRoute();

  /// The phone's own estimate of its audio output delay in ms, if it tells.
  Future<int?> outputLatencyMs();
}

class MethodChannelGroupNative implements GroupNative {
  static const _channel = MethodChannel('remotetunes/group');

  @override
  Future<void> setLocks({required bool enabled, bool keepScreenOn = false}) async {
    try {
      await _channel.invokeMethod<void>(
          'setLocks', {'enabled': enabled, 'keepScreenOn': keepScreenOn});
    } on PlatformException {
      // Best effort: group play works without them, just less steadily.
    } on MissingPluginException {
      // Not on Android (tests).
    }
  }

  @override
  Future<String> outputRoute() async {
    try {
      return await _channel.invokeMethod<String>('outputRoute') ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  @override
  Future<int?> outputLatencyMs() async {
    try {
      return await _channel.invokeMethod<int>('outputLatencyMs');
    } catch (_) {
      return null;
    }
  }
}

/// Does nothing (tests, other platforms).
class NoGroupNative implements GroupNative {
  const NoGroupNative();

  @override
  Future<void> setLocks({required bool enabled, bool keepScreenOn = false}) async {}
  @override
  Future<String> outputRoute() async => 'speaker';
  @override
  Future<int?> outputLatencyMs() async => null;
}
