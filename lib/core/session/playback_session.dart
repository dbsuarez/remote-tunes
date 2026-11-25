import 'package:flutter/widgets.dart';

import '../models/enums.dart';
import '../protocol/library_models.dart';
import '../protocol/protocol.dart';
import '../../features/music/music_source.dart';

/// What the Now Playing screen needs, whichever phone the music is on.
///
/// There are two: one that plays this phone's own music, and one that controls
/// another phone's player over the network. The screen is the same for both.
///
/// Every command may throw (a [ControllerException] for a Controller, a
/// [PlaybackException] on this phone); the screen shows the message.
abstract class PlaybackSession {
  /// What is playing right now.
  PlaybackState get state;

  /// False when commands cannot be sent (for example while reconnecting).
  bool get enabled;

  /// True when this controls another phone.
  bool get isRemote;

  /// The library and queue the screen shows.
  MusicSource get source;

  Future<void> toggle();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(int seconds);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeat(RepeatMode mode);

  /// Starts the sleep timer for [minutes]; 0 cancels it.
  Future<void> setSleepTimer(int minutes);
  Future<void> setFavorite(int songId, bool favorite);
  Future<RemoteLyrics> lyrics(int songId);

  /// The cover of [songId] (null: no library song), [size] pixels wide.
  Widget art(int? songId, {required double size, double? radius});
}
