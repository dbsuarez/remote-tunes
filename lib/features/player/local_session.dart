import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../../core/session/playback_session.dart';
import '../music/local_music_source.dart';
import '../music/music_source.dart';
import 'queue_aware_engine.dart';
import 'server/player_library.dart';
import 'sleep_timer.dart';

/// Plays this phone's own music: direct calls into the engine and the library.
class LocalSession implements PlaybackSession {
  LocalSession({
    required this.engine,
    required this.library,
    required this.sleepTimer,
    required PlaybackState playback,
    this.onChanged,
  })  : _playback = playback,
        source = LocalMusicSource(library, engine);

  final QueueAwareEngine engine;
  final PlayerLibrary library;
  final SleepTimerService sleepTimer;
  final PlaybackState _playback;

  /// Called after something changed that the engine does not report itself
  /// (a favorite), so the screen draws again.
  final VoidCallback? onChanged;

  @override
  final MusicSource source;

  @override
  PlaybackState get state {
    final id = _playback.songId;
    return _playback.copyWith(
      sleepTimerSeconds: sleepTimer.secondsLeft,
      favorite: id != null && id > 0 && library.isFavorite(id),
    );
  }

  @override
  bool get enabled => true;

  @override
  bool get isRemote => false;

  @override
  Future<void> toggle() => engine.toggle();

  @override
  Future<void> next() => engine.next();

  @override
  Future<void> previous() => engine.previous();

  @override
  Future<void> seek(int seconds) => engine.seek(seconds);

  @override
  Future<void> setVolume(double volume) => engine.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => engine.setSpeed(speed);

  @override
  Future<void> setShuffle(bool enabled) => engine.setShuffle(enabled);

  @override
  Future<void> setRepeat(RepeatMode mode) => engine.setRepeatMode(mode);

  @override
  Future<void> setSleepTimer(int minutes) async =>
      sleepTimer.set(minutes <= 0 ? null : Duration(minutes: minutes));

  @override
  Future<void> setFavorite(int songId, bool favorite) async {
    await library.setFavorite(songId, favorite);
    onChanged?.call();
  }

  @override
  Future<RemoteLyrics> lyrics(int songId) => library.lyrics(songId);

  @override
  Widget art(int? songId, {required double size, double? radius}) =>
      LocalArt(path: _playback.localArtPath, size: size, radius: radius);
}

/// The cover of the song playing on this phone (a music note when it has none).
class LocalArt extends StatelessWidget {
  const LocalArt({super.key, required this.path, required this.size, this.radius});

  final String? path;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = radius ?? size / 5;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(r),
      ),
      child: Icon(Icons.music_note_rounded, color: theme.colorScheme.primary, size: size / 2),
    );
    final p = path;
    if (p == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Image.file(
        File(p),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).round(),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
