import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Thrown when a file cannot be loaded or played.
class AudioBackendException implements Exception {
  AudioBackendException(this.message);

  /// Plain-language reason, safe to show to the user.
  final String message;

  @override
  String toString() => 'AudioBackendException: $message';
}

/// The smallest audio surface the engine needs. The real implementation wraps
/// just_audio; tests use a fake so queue/engine logic runs without plugins.
abstract class AudioBackend {
  /// Playback position updates while playing.
  Stream<Duration> get positionStream;

  /// Actual playing/paused state of the underlying player.
  Stream<bool> get playingStream;

  /// Fires when the loaded track plays to its end.
  Stream<void> get completedStream;

  /// The loaded source's duration once known (streams often learn it late).
  Stream<Duration?> get durationStream;

  /// Playback problems after a track was loaded (e.g. a stream that dropped),
  /// as plain-language messages.
  Stream<String> get errorStream;

  /// Loads a local file and returns its duration if known.
  Future<Duration?> load(String filePath);

  /// Opens an internet audio URL and returns its duration if known. May take
  /// a few seconds while the stream buffers.
  Future<Duration?> loadUrl(String url);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// 0.0–1.0
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

class JustAudioBackend implements AudioBackend {
  JustAudioBackend() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<String> get errorStream => _player.errorStream.map(
        (_) => 'Playback stopped. The connection may have dropped, or the '
            'audio could not be read.',
      );

  @override
  Future<Duration?> load(String filePath) async {
    try {
      return await _player.setFilePath(filePath);
    } on PlayerInterruptedException {
      // A newer load replaced this one; not an error for the user.
      return null;
    } on PlayerException {
      throw AudioBackendException(
        "This file couldn't be played. It may be damaged or in a format "
        'this phone does not support.',
      );
    } catch (_) {
      throw AudioBackendException("This file couldn't be played.");
    }
  }

  @override
  Future<Duration?> loadUrl(String url) async {
    try {
      return await _player.setUrl(url);
    } on PlayerInterruptedException {
      return null;
    } on PlayerException {
      throw AudioBackendException(
        "The Player couldn't play this link. It may not be a direct audio "
        'file, may be in a format this phone does not support, or the '
        'connection may have dropped.',
      );
    } catch (_) {
      throw AudioBackendException("The Player couldn't play this link.");
    }
  }

  @override
  Future<void> play() async {
    // just_audio's play() completes only when playback ends or pauses, so it
    // must not be awaited here.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}
