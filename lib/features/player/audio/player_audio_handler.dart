import 'dart:async';

import 'package:audio_service/audio_service.dart' as svc;

import '../../../core/protocol/protocol.dart';
import '../playback_engine.dart';

/// Bridges the Player's [PlaybackEngine] to Android's media session, so the
/// notification, lock screen and headset buttons control the same engine that
/// Controllers and the on-screen buttons use.
///
/// While an engine is attached the handler stays active even when idle, which
/// keeps the foreground service (and so the Player's network server) alive
/// with the screen off.
class RemoteTunesAudioHandler extends svc.BaseAudioHandler with svc.SeekHandler {
  PlaybackEngine? _engine;
  StreamSubscription<PlaybackState>? _sub;

  static const _idleItem = svc.MediaItem(
    id: 'remotetunes.idle',
    title: 'RemoteTunes Player',
    artist: 'Waiting for a Controller',
  );

  /// Starts mirroring [engine] to the media session.
  void attach(PlaybackEngine engine) {
    detach(publish: false);
    _engine = engine;
    _sub = engine.states.listen(_publish);
    _publish(engine.state);
  }

  /// Stops mirroring and releases the media session.
  void detach({bool publish = true}) {
    _sub?.cancel();
    _sub = null;
    _engine = null;
    if (publish) {
      playbackState.add(svc.PlaybackState(
        processingState: svc.AudioProcessingState.idle,
        playing: false,
      ));
      mediaItem.add(null);
    }
  }

  void _publish(PlaybackState s) {
    mediaItem.add(
      s.hasTrack
          ? svc.MediaItem(
              id: s.songId?.toString() ?? s.title,
              title: s.title,
              artist: s.artist,
              album: s.album,
              duration: s.durationSeconds > 0
                  ? Duration(seconds: s.durationSeconds)
                  : null,
              artUri: s.localArtPath != null ? Uri.file(s.localArtPath!) : null,
            )
          : _idleItem,
    );
    playbackState.add(svc.PlaybackState(
      controls: [
        svc.MediaControl.skipToPrevious,
        if (s.isPlaying) svc.MediaControl.pause else svc.MediaControl.play,
        svc.MediaControl.skipToNext,
        svc.MediaControl.stop,
      ],
      systemActions: const {
        svc.MediaAction.seek,
        svc.MediaAction.skipToNext,
        svc.MediaAction.skipToPrevious,
        svc.MediaAction.play,
        svc.MediaAction.pause,
      },
      androidCompactActionIndices: const [0, 1, 2],
      // Kept "ready" even with an empty queue so the service stays in the
      // foreground while Player mode is open.
      processingState: svc.AudioProcessingState.ready,
      playing: s.isPlaying,
      updatePosition: Duration(seconds: s.positionSeconds),
      speed: 1.0,
      queueIndex: s.queueLength > 0 ? s.queueIndex : null,
    ));
  }

  // Commands arriving from the notification / headset buttons.

  Future<void> _run(Future<void> Function(PlaybackEngine e) action) async {
    final e = _engine;
    if (e == null) return;
    try {
      await action(e);
    } on PlaybackException {
      // e.g. "queue is empty": nothing useful to do from a notification.
    }
  }

  @override
  Future<void> play() => _run((e) => e.play());

  @override
  Future<void> pause() => _run((e) => e.pause());

  @override
  Future<void> stop() => _run((e) => e.pause());

  @override
  Future<void> seek(Duration position) =>
      _run((e) => e.seek(position.inSeconds));

  @override
  Future<void> skipToNext() => _run((e) => e.next());

  @override
  Future<void> skipToPrevious() => _run((e) => e.previous());
}

/// Starts the Android media service once per process.
class PlayerAudioService {
  PlayerAudioService._();

  static RemoteTunesAudioHandler? _handler;
  static Future<RemoteTunesAudioHandler?>? _starting;

  /// Returns the handler, or null if the media service could not start (the
  /// Player still works, just without a notification).
  static Future<RemoteTunesAudioHandler?> ensureStarted() {
    return _starting ??= _start();
  }

  static Future<RemoteTunesAudioHandler?> _start() async {
    try {
      final handler = await svc.AudioService.init(
        builder: () => RemoteTunesAudioHandler(),
        config: const svc.AudioServiceConfig(
          androidNotificationChannelId: 'com.remotetunes.remote_tunes.playback',
          androidNotificationChannelName: 'RemoteTunes playback',
          // Keep the notification (and foreground service) while paused so the
          // Player keeps accepting Controller commands with the screen off.
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
      _handler = handler;
      return handler;
    } catch (_) {
      _starting = null; // allow a later retry
      return null;
    }
  }

  static RemoteTunesAudioHandler? get handler => _handler;
}
