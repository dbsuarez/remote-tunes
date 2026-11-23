import 'dart:async';

import 'package:remote_tunes/features/player/audio/audio_backend.dart';
import 'package:remote_tunes/features/player/url_checker.dart';

/// [UrlChecker] stand-in: records checks, can delay or fail.
class FakeUrlChecker implements UrlChecker {
  final List<Uri> checked = [];
  Object? failWith;
  Duration delay = Duration.zero;

  @override
  Future<void> check(Uri uri) async {
    checked.add(uri);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith != null) throw failWith!;
  }
}

/// Controllable in-memory [AudioBackend] for tests (no plugins, no sound).
class FakeAudioBackend implements AudioBackend {
  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();

  final _duration = StreamController<Duration?>.broadcast();
  final _errors = StreamController<String>.broadcast();

  /// Every path passed to [load], in order.
  final List<String> loaded = [];

  /// Every URL passed to [loadUrl], in order.
  final List<String> loadedUrls = [];
  final Set<String> unplayableUrls = {};
  Duration? urlDuration;
  final Set<String> unplayable = {};
  final Map<String, Duration> durations = {};

  String? currentPath;
  bool playing = false;
  double volume = 1;
  Duration position = Duration.zero;
  int seekCount = 0;

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<String> get errorStream => _errors.stream;

  /// When set, [loadUrl] waits for it (to test the "loading" state).
  Future<void>? urlGate;

  @override
  Future<Duration?> loadUrl(String url) async {
    if (urlGate != null) await urlGate;
    if (unplayableUrls.contains(url)) {
      throw AudioBackendException('Cannot play $url');
    }
    loadedUrls.add(url);
    currentPath = url;
    position = Duration.zero;
    return urlDuration;
  }

  /// Simulates the duration becoming known after loading.
  void emitDuration(Duration? d) => _duration.add(d);

  /// Simulates a playback error after the track loaded.
  void emitError(String message) => _errors.add(message);

  @override
  Future<Duration?> load(String filePath) async {
    if (unplayable.contains(filePath)) {
      throw AudioBackendException('Cannot play $filePath');
    }
    loaded.add(filePath);
    currentPath = filePath;
    position = Duration.zero;
    return durations[filePath] ?? const Duration(seconds: 100);
  }

  @override
  Future<void> play() async {
    playing = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration p) async {
    seekCount++;
    position = p;
    _position.add(p);
  }

  @override
  Future<void> setVolume(double v) async => volume = v;

  /// Simulates playback progress.
  void emitPosition(Duration d) {
    position = d;
    _position.add(d);
  }

  /// Simulates the track playing to its end.
  void completeTrack() => _completed.add(null);

  @override
  Future<void> dispose() async {
    await _position.close();
    await _playing.close();
    await _completed.close();
    await _duration.close();
    await _errors.close();
  }
}

/// Lets queued async work (engine serial queue, stream events) finish.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
