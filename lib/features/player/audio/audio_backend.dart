import 'dart:async';

import 'dart:io' show Platform;

import 'package:just_audio/just_audio.dart';

import '../eq/eq_model.dart';

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

  /// The position right now (not the last update from [positionStream]).
  Duration get position;

  /// Actual playing/paused state of the underlying player.
  Stream<bool> get playingStream;

  /// Fires when the loaded track plays to its end.
  Stream<void> get completedStream;

  /// The loaded source's duration once known (streams often learn it late).
  Stream<Duration?> get durationStream;

  /// Playback problems after a track was loaded (e.g. a stream that dropped),
  /// as plain-language messages.
  Stream<String> get errorStream;

  /// Fires when playback moved on by itself to the track given to [setNext]
  /// (with no gap). Carries that track's file path.
  Stream<String?> get advancedStream;

  /// Gets a local file ready to follow the loaded track with no gap. Null
  /// removes it. Replaced by the next [load].
  Future<void> setNext(String? filePath);

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

  /// 0.5–2.0 (1.0 = normal).
  Future<void> setSpeed(double speed);

  /// True when [crossfadeTo] works (two players are available).
  bool get supportsCrossfade;

  /// Starts [filePath] on a second player and fades into it over [length].
  /// Completes when the change is done (the new song is then the one playing and
  /// [advancedStream] has fired), or with false if it could not be done.
  Future<bool> crossfadeTo(String filePath, Duration length);

  /// The bands of the phone's equalizer, or null when it has none (or has not
  /// been set up yet: Android does that when the first song is loaded).
  Future<EqBands?> equalizerBands();

  /// Switches the equalizer on or off and sets the gain (dB) of each band.
  Future<void> setEqualizer({required bool enabled, required List<double> gains});

  Future<void> dispose();
}

class JustAudioBackend implements AudioBackend {
  JustAudioBackend() : this._(Platform.isAndroid ? AndroidEqualizer() : null);

  JustAudioBackend._(this._eq)
      : _player = AudioPlayer(
          audioPipeline: _eq == null ? null : AudioPipeline(androidAudioEffects: [_eq]),
        );

  final AndroidEqualizer? _eq;
  final AudioPlayer _player;

  @override
  bool get supportsCrossfade => false;

  @override
  Future<bool> crossfadeTo(String filePath, Duration length) async => false;

  @override
  Future<EqBands?> equalizerBands() async {
    final eq = _eq;
    if (eq == null) return null;
    try {
      // Available once the first song has been loaded.
      final p = await eq.parameters;
      if (p.bands.isEmpty) return null;
      return EqBands(
        minDb: p.minDecibels,
        maxDb: p.maxDecibels,
        centersHz: [for (final b in p.bands) b.centerFrequency],
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setEqualizer({required bool enabled, required List<double> gains}) async {
    final eq = _eq;
    if (eq == null) return;
    final p = await eq.parameters;
    await eq.setEnabled(enabled);
    for (var i = 0; i < p.bands.length && i < gains.length; i++) {
      await p.bands[i].setGain(gains[i].clamp(p.minDecibels, p.maxDecibels).toDouble());
    }
  }

  // The player holds a short list: the loaded track and, after it, the one
  // given to setNext, so the change between them is gapless.
  final List<String?> _paths = [null]; // what is at each index (null: a link)
  int _baseIndex = 0;
  bool _indexWatched = false;
  Future<void> _nextWork = Future.value();
  final StreamController<String?> _advanced = StreamController<String?>.broadcast();

  void _watchIndex() {
    if (_indexWatched) return;
    _indexWatched = true;
    _player.currentIndexStream.listen((i) {
      if (i == null || i <= _baseIndex) return;
      _baseIndex = i;
      _advanced.add(i < _paths.length ? _paths[i] : null);
    });
  }

  @override
  Stream<String?> get advancedStream => _advanced.stream;

  @override
  Future<void> setNext(String? filePath) {
    final job = _nextWork.then((_) async {
      final nextIndex = _baseIndex + 1;
      try {
        if (_paths.length > nextIndex) {
          if (_paths[nextIndex] == filePath) return;
          await _player.removeAudioSourceAt(nextIndex);
          _paths.removeRange(nextIndex, _paths.length);
        }
        if (filePath != null) {
          await _player.addAudioSource(AudioSource.file(filePath));
          _paths.add(filePath);
        }
      } catch (_) {
        // No gapless change this time; the track after this one loads normally.
        _paths.removeRange(
            (_baseIndex + 1).clamp(0, _paths.length), _paths.length);
      }
    });
    _nextWork = job;
    return job;
  }

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Duration get position => _player.position;

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

  void _resetList(String? path) {
    _watchIndex();
    _baseIndex = 0;
    _paths
      ..clear()
      ..add(path);
  }

  @override
  Future<Duration?> load(String filePath) async {
    try {
      _resetList(filePath);
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
      _resetList(null);
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
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> dispose() => _player.dispose();
}
