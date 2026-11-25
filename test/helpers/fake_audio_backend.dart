import 'dart:async';

import 'package:remote_tunes/features/player/audio/audio_backend.dart';
import 'package:remote_tunes/features/player/eq/eq_model.dart';
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
  final _advanced = StreamController<String?>.broadcast();

  /// Every value passed to [setNext], in order.
  final List<String?> nextRequests = [];

  /// The file lined up to follow the loaded one (null: none).
  String? nextPath;

  @override
  int? audioSessionId;

  /// Whether the pretend phone accepts our own equalizer.
  bool trueEqSupported = true;

  /// Every call to [setTrueEqualizer].
  final List<({bool enabled, List<double> hz, List<double> gains, bool limiter})> trueCalls = [];

  @override
  bool? trueEqualizerActive;

  @override
  Future<bool> setTrueEqualizer({
    required bool enabled,
    required List<double> centersHz,
    required List<double> gains,
    required bool limiter,
  }) async {
    trueCalls.add((enabled: enabled, hz: [...centersHz], gains: [...gains], limiter: limiter));
    if (enabled) trueEqualizerActive = trueEqSupported;
    return trueEqSupported;
  }

  @override
  Stream<String?> get advancedStream => _advanced.stream;

  @override
  Future<void> setNext(String? filePath) async {
    nextRequests.add(filePath);
    nextPath = filePath;
  }

  /// Simulates playback moving on to the lined-up file with no gap.
  void advanceGapless() {
    final p = nextPath;
    nextPath = null;
    currentPath = p;
    position = Duration.zero;
    _advanced.add(p);
  }

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
  double speed = 1;
  @override
  Duration position = Duration.zero;
  int seekCount = 0;

  @override
  Stream<Duration> get positionStream => _position.stream;

  // `position` (a field above) is also the "right now" position.
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

  /// When set, [load] waits for it (a cold player taking its time).
  Future<void>? loadGate;

  /// Simulates the end of the song.
  void emitCompleted() => _completed.add(null);

  @override
  Future<Duration?> load(String filePath) async {
    if (loadGate != null) await loadGate;
    if (unplayable.contains(filePath)) {
      throw AudioBackendException('Cannot play $filePath');
    }
    loaded.add(filePath);
    nextPath = null;
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

  @override
  Future<void> setSpeed(double s) async => speed = s;

  /// The last preamp given (dB).
  double preampDb = 0;

  @override
  Future<void> setPreamp(double db) async => preampDb = db;

  /// Whether this fake can crossfade, and what it was asked to fade into.
  bool canCrossfade = false;
  final List<({String path, Duration length})> crossfades = [];

  @override
  bool get supportsCrossfade => canCrossfade;

  @override
  Future<bool> crossfadeTo(String filePath, Duration length) async {
    if (!canCrossfade) return false;
    crossfades.add((path: filePath, length: length));
    currentPath = filePath;
    position = Duration.zero;
    nextPath = null;
    _advanced.add(filePath);
    return true;
  }

  /// The equalizer the fake phone has (null: none).
  EqBands? eqBands = const EqBands(
      minDb: -12, maxDb: 12, centersHz: [60, 230, 910, 3600, 14000]);

  /// Every (enabled, gains) pair given to [setEqualizer].
  final List<({bool enabled, List<double> gains})> eqCalls = [];

  @override
  Future<EqBands?> equalizerBands() async => eqBands;

  @override
  Future<void> setEqualizer({required bool enabled, required List<double> gains}) async {
    eqCalls.add((enabled: enabled, gains: [...gains]));
  }

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
    await _advanced.close();
  }
}

/// Lets queued async work (engine serial queue, stream events) finish.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));
