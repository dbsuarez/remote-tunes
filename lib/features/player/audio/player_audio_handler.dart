import 'dart:async';

import 'package:audio_service/audio_service.dart' as svc;

import '../../../core/models/enums.dart';
import '../../../core/protocol/protocol.dart';
import '../playback_engine.dart';
import '../queue_aware_engine.dart';

/// What the notification shows while ambience has the sound, and what its buttons do.
class AmbienceNotice {
  const AmbienceNotice({
    this.title = 'RemoteTunes Ambience',
    required this.subtitle,
    required this.playing,
    required this.play,
    required this.pause,
    required this.stop,
  });

  final String title;
  final String subtitle;
  final bool playing;
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function() stop;
}

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

  /// Lets the lock screen's heart button read and change favorites (set by the
  /// app; without it there is no heart).
  bool Function(int songId)? isFavorite;
  Future<void> Function(int songId, bool favorite)? setFavorite;

  bool _keepAlive = false;

  /// True while remote playback is on: the service then stays in the foreground
  /// even with nothing playing, so the Player keeps accepting Controller
  /// commands with the screen off. When false, nothing is shown while nothing
  /// plays (a normal music player).
  set keepAlive(bool value) {
    if (_keepAlive == value) return;
    _keepAlive = value;
    final e = _engine;
    if (e != null) _publish(e.state);
  }

  AmbienceNotice? _ambience;

  /// While set, the notification and headset buttons are ambience's; null gives them back to the music.
  set ambience(AmbienceNotice? notice) {
    _ambience = notice;
    _lastKey = null;
    if (notice != null) {
      mediaItem.add(svc.MediaItem(id: 'remotetunes.ambience', title: notice.title, artist: notice.subtitle));
      playbackState.add(svc.PlaybackState(
        controls: [if (notice.playing) svc.MediaControl.pause else svc.MediaControl.play, svc.MediaControl.stop],
        systemActions: const {svc.MediaAction.play, svc.MediaAction.pause},
        androidCompactActionIndices: const [0, 1],
        processingState: svc.AudioProcessingState.ready,
        playing: notice.playing,
      ));
      return;
    }
    final e = _engine;
    if (e != null) {
      _publish(e.state);
    } else {
      detach();
    }
  }

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

  // What was last given to Android, so the notification is only rebuilt when
  // something changed. (Android works out the position while playing by itself;
  // sending it every second rebuilt the notification thousands of times a day.)
  String? _lastKey;
  int _lastPosition = 0;
  DateTime _lastAt = DateTime.now();
  bool _lastPlaying = false;
  double _lastSpeed = 1.0;

  void _publish(PlaybackState s) {
    if (_ambience != null) return;
    final songId = s.songId;
    final hasHeart = isFavorite != null && setFavorite != null && songId != null && songId > 0;
    final favorite = hasHeart && isFavorite!(songId);
    final key = '$hasHeart|$favorite|${s.songId}|${s.title}|${s.artist}|${s.album}|${s.durationSeconds}|'
        '${s.isPlaying}|${s.isLoading}|${s.queueIndex}|${s.queueLength}|${s.shuffleEnabled}|'
        '${s.repeatMode}|${s.speed}|${s.localArtPath}|${s.canSkip}|$_keepAlive';
    final now = DateTime.now();
    final expected = _lastPosition +
        (_lastPlaying ? (now.difference(_lastAt).inMilliseconds * _lastSpeed / 1000) : 0);
    final jumped = (s.positionSeconds - expected).abs() > 2.5;
    if (key == _lastKey && !jumped) return;
    _lastKey = key;
    _lastPosition = s.positionSeconds;
    _lastAt = now;
    _lastPlaying = s.isPlaying;
    _lastSpeed = s.isPlaying ? s.speed : 1.0;

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
          : (_keepAlive ? _idleItem : null),
    );
    playbackState.add(svc.PlaybackState(
      controls: [
        svc.MediaControl.skipToPrevious,
        if (s.isPlaying) svc.MediaControl.pause else svc.MediaControl.play,
        svc.MediaControl.skipToNext,
        if (hasHeart)
          svc.MediaControl.custom(
            androidIcon: favorite ? 'drawable/ic_favorite' : 'drawable/ic_favorite_border',
            label: favorite ? 'Remove from favorites' : 'Add to favorites',
            name: 'favorite',
          ),
        svc.MediaControl.stop,
      ],
      systemActions: const {
        svc.MediaAction.seek,
        svc.MediaAction.skipToNext,
        svc.MediaAction.skipToPrevious,
        svc.MediaAction.play,
        svc.MediaAction.pause,
        svc.MediaAction.setShuffleMode,
        svc.MediaAction.setRepeatMode,
        svc.MediaAction.setSpeed,
      },
      androidCompactActionIndices: const [0, 1, 2],
      // Kept "ready" even with an empty queue so the service stays in the
      // foreground while Player mode is open.
      processingState: !(s.hasTrack || _keepAlive)
          ? svc.AudioProcessingState.idle
          : (s.isLoading ? svc.AudioProcessingState.loading : svc.AudioProcessingState.ready),
      playing: s.isPlaying,
      updatePosition: Duration(seconds: s.positionSeconds),
      speed: s.isPlaying ? s.speed : 1.0,
      queueIndex: s.queueLength > 0 ? s.queueIndex : null,
      // Lets the lock screen and Android 13+ media controls show (and change)
      // shuffle and repeat.
      repeatMode: switch (s.repeatMode) {
        RepeatMode.one => svc.AudioServiceRepeatMode.one,
        RepeatMode.queue => svc.AudioServiceRepeatMode.all,
        RepeatMode.off => svc.AudioServiceRepeatMode.none,
      },
      shuffleMode: s.shuffleEnabled
          ? svc.AudioServiceShuffleMode.all
          : svc.AudioServiceShuffleMode.none,
    ));
  }

  // Commands arriving from the notification / headset buttons.

  @override
  Future<void> click([svc.MediaButton button = svc.MediaButton.media]) async {
    final ambience = _ambience;
    if (ambience != null && button == svc.MediaButton.media) {
      await (ambience.playing ? ambience.pause() : ambience.play());
      return;
    }
    await super.click(button);
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name != 'favorite') return super.customAction(name, extras);
    final e = _engine;
    final id = e?.state.songId;
    final get = isFavorite;
    final set = setFavorite;
    if (e == null || id == null || id <= 0 || get == null || set == null) return null;
    try {
      await set(id, !get(id));
    } catch (_) {
      return null;
    }
    // Draw the heart again (the song itself did not change).
    _lastKey = null;
    _publish(e.state);
    return null;
  }

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
  Future<void> play() => _ambience?.play() ?? _run((e) => e.play());

  @override
  Future<void> pause() => _ambience?.pause() ?? _run((e) => e.pause());

  @override
  Future<void> stop() => _ambience?.stop() ?? _run((e) => e.pause());

  @override
  Future<void> seek(Duration position) =>
      _run((e) => e.seek(position.inSeconds));

  @override
  Future<void> setShuffleMode(svc.AudioServiceShuffleMode shuffleMode) => _run((e) async {
        if (e is QueueAwareEngine) {
          await e.setShuffle(shuffleMode != svc.AudioServiceShuffleMode.none);
        }
      });

  @override
  Future<void> setRepeatMode(svc.AudioServiceRepeatMode repeatMode) => _run((e) async {
        if (e is QueueAwareEngine) {
          await e.setRepeatMode(switch (repeatMode) {
            svc.AudioServiceRepeatMode.one => RepeatMode.one,
            svc.AudioServiceRepeatMode.all || svc.AudioServiceRepeatMode.group => RepeatMode.queue,
            svc.AudioServiceRepeatMode.none => RepeatMode.off,
          });
        }
      });

  @override
  Future<void> setSpeed(double speed) => _run((e) async {
        if (e is QueueAwareEngine) await e.setSpeed(speed.clamp(0.5, 2.0));
      });

  // A headset's skip button must not start the music over the ambience.
  @override
  Future<void> skipToNext() async {
    if (_ambience == null) await _run((e) => e.next());
  }

  @override
  Future<void> skipToPrevious() async {
    if (_ambience == null) await _run((e) => e.previous());
  }
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
          // Created by the app itself (MainActivity) with normal importance and no
          // sound, so it also shows on the lock screen.
          androidNotificationChannelId: 'com.remotetunes.remote_tunes.media',
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
