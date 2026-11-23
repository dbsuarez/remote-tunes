import 'dart:async';
import 'dart:convert';

import '../../core/protocol/protocol.dart';
import '../player/playback_engine.dart';
import 'external_media.dart';

/// Controls *another* music app on the Player phone (Spotify, YouTube Music, …)
/// through its Android media session. Basic transport only: play, pause, next,
/// previous, seek (if the app allows it), and the phone's media volume.
///
/// It never promises more than the other app allows: every action checks what
/// the app currently permits and explains plainly when it cannot.
class ExternalAppEngine implements PlaybackEngine {
  ExternalAppEngine({required ExternalMediaBridge bridge}) : _bridge = bridge;

  final ExternalMediaBridge _bridge;
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  StreamSubscription<ExternalMediaSnapshot>? _sub;
  Timer? _ticker;
  ExternalMediaSnapshot _snap = ExternalMediaSnapshot.empty;
  int _positionMs = 0;
  bool _active = false;
  String _lastSent = '';

  bool get isActive => _active;

  /// Name of the app being controlled, or '' if none is playing.
  String get appName => _snap.current?.label ?? '';

  /// What the user can pick from when several apps have sessions.
  List<ExternalSession> get sessions => _snap.sessions;

  // ----------------------------------------------------------------- lifecycle

  /// Starts watching media sessions. Throws a [PlaybackException] with
  /// [ErrorCodes.permissionDenied] if Notification access is not allowed.
  Future<void> activate() async {
    if (_active) return;
    final ExternalMediaSnapshot first;
    try {
      first = await _bridge.start();
    } on ExternalMediaException catch (e) {
      throw _asPlayback(e);
    }
    if (!first.accessGranted) {
      await _bridge.stop();
      throw PlaybackException(
        ErrorCodes.permissionDenied,
        'Notification access is not allowed on the Player. Open the Player '
        'and allow it under External App Control.',
      );
    }
    _active = true;
    _apply(first);
    _sub = _bridge.snapshots.listen(_apply);
  }

  /// Stops watching, and pauses the other app so two apps never play at once.
  Future<void> deactivate() async {
    if (!_active) return;
    _active = false;
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    try {
      if (_snap.current?.isPlaying == true) await _bridge.pause();
    } on ExternalMediaException {
      // The app may already be gone.
    }
    try {
      await _bridge.stop();
    } on ExternalMediaException {
      // Nothing more to release.
    }
    _snap = ExternalMediaSnapshot.empty;
    _positionMs = 0;
  }

  // --------------------------------------------------------------------- state

  void _apply(ExternalMediaSnapshot snap) {
    _snap = snap;
    _positionMs = snap.current?.positionMs ?? 0;
    _ticker?.cancel();
    _ticker = null;
    if (snap.current?.isPlaying == true) {
      // Advance the clock between updates so the position keeps moving.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final d = _snap.current?.durationMs ?? 0;
        _positionMs += 1000;
        if (d > 0 && _positionMs > d) _positionMs = d;
        _emit();
      });
    }
    _emit();
  }

  @override
  PlaybackState get state {
    final t = _snap.current;
    return PlaybackState(
      title: t == null ? '' : (t.title.isEmpty ? t.label : t.title),
      artist: t?.artist ?? '',
      album: t?.album ?? '',
      positionSeconds: _positionMs ~/ 1000,
      durationSeconds: (t?.durationMs ?? 0) ~/ 1000,
      isPlaying: t?.isPlaying ?? false,
      isLoading: t?.isBuffering ?? false,
      volume: _snap.volume,
      source: 'external',
      externalApp: t?.label ?? '',
      externalEnabled: true,
      canSeek: t?.canSeek ?? false,
      canSkip: t != null && (t.canNext || t.canPrevious),
      error: (_active && t == null)
          ? 'No music app is playing on the Player phone. Start Spotify or '
              'YouTube Music there.'
          : '',
    );
  }

  @override
  Stream<PlaybackState> get states => _controller.stream;

  void _emit() {
    if (_controller.isClosed) return;
    final s = state;
    // Native updates can be frequent; only forward real changes.
    final key = jsonEncode(s.toJson());
    if (key == _lastSent) return;
    _lastSent = key;
    _controller.add(s);
  }

  // ------------------------------------------------------------------ commands

  PlaybackException _asPlayback(ExternalMediaException e) => PlaybackException(
        e.noAccess ? ErrorCodes.permissionDenied : ErrorCodes.playbackFailed,
        e.message,
      );

  Future<void> _run(Future<void> Function() action) async {
    if (!_active) {
      throw PlaybackException(
        ErrorCodes.invalidAction,
        'External App Control is not active on the Player.',
      );
    }
    try {
      await action();
    } on ExternalMediaException catch (e) {
      throw _asPlayback(e);
    }
  }

  ExternalTrack _session() {
    final t = _snap.current;
    if (t == null) {
      throw PlaybackException(
        ErrorCodes.playbackFailed,
        'No music app is playing on the Player phone. Start Spotify or '
        'YouTube Music there first.',
      );
    }
    return t;
  }

  @override
  Future<void> play() => _run(() async {
        _session();
        await _bridge.play();
      });

  @override
  Future<void> pause() => _run(() async {
        _session();
        await _bridge.pause();
      });

  @override
  Future<void> toggle() async {
    if (_snap.current?.isPlaying == true) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> next() => _run(() async {
        final t = _session();
        if (!t.canNext) {
          throw PlaybackException(
            ErrorCodes.invalidAction,
            "${t.label} doesn't allow skipping to the next track right now.",
          );
        }
        await _bridge.next();
      });

  @override
  Future<void> previous() => _run(() async {
        final t = _session();
        if (!t.canPrevious) {
          throw PlaybackException(
            ErrorCodes.invalidAction,
            "${t.label} doesn't allow going to the previous track right now.",
          );
        }
        await _bridge.previous();
      });

  @override
  Future<void> stop() => pause();

  @override
  Future<void> seek(int positionSeconds) => _run(() async {
        final t = _session();
        if (!t.canSeek) {
          throw PlaybackException(
            ErrorCodes.invalidAction,
            "${t.label} doesn't allow seeking right now.",
          );
        }
        final max = t.durationMs ~/ 1000;
        if (positionSeconds < 0 || (max > 0 && positionSeconds > max)) {
          throw PlaybackException(
            ErrorCodes.invalidPosition,
            'That position is outside the track (0–${max}s).',
          );
        }
        await _bridge.seekTo(Duration(seconds: positionSeconds));
      });

  @override
  Future<void> setVolume(double volume) => _run(() async {
        if (volume.isNaN || volume < 0 || volume > 1) {
          throw PlaybackException(
            ErrorCodes.invalidAction,
            'Volume must be between 0 and 1.',
          );
        }
        await _bridge.setVolume(volume);
      });

  /// Pick which app to control when several have sessions (null = automatic).
  Future<void> selectApp(String? package) => _run(() => _bridge.selectSession(package));

  @override
  Future<void> dispose() async {
    await deactivate();
    await _controller.close();
  }
}
