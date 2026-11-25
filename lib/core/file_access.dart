import 'package:flutter/services.dart';

/// Android's "All files access": needed to write tags into music files in
/// shared folders (Android 11 and newer). Off by default; the user switches it on
/// in the phone's own settings page.
class FileAccess {
  const FileAccess();

  static const _channel = MethodChannel('remotetunes/update');

  /// True when the app may change any file (also true where the question does
  /// not apply, e.g. old Android or tests).
  Future<bool> canWriteAll() async {
    try {
      return await _channel.invokeMethod<bool>('canWriteAllFiles') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the phone's page where the right is switched on.
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openAllFilesSettings');
    } catch (_) {}
  }
}
