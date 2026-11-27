import 'package:flutter/widgets.dart';

import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../../core/session/playback_session.dart';
import '../music/music_source.dart';
import 'controller_client.dart';
import 'remote_art.dart';

/// Controls another phone's player through a [ControllerClient].
class RemoteSession implements PlaybackSession {
  RemoteSession({required this.client, required this.connection})
      : source = RemoteMusicSource(client);

  final ControllerClient client;

  /// The connection as it is now (the screen builds a new session whenever it
  /// changes).
  final ControllerClientState connection;

  @override
  final MusicSource source;

  @override
  PlaybackState get state => connection.playback;

  @override
  bool get enabled => connection.isConnected;

  @override
  bool get isRemote => true;

  Future<void> _send(String action, [Map<String, dynamic> params = const {}]) =>
      client.sendCommand(action, params);

  @override
  Future<void> toggle() => _send(RemoteActions.toggle);

  @override
  Future<void> next() => _send(RemoteActions.next);

  @override
  Future<void> previous() => _send(RemoteActions.previous);

  @override
  Future<void> seek(int seconds) => _send(RemoteActions.seek, {'positionSeconds': seconds});

  @override
  Future<void> setVolume(double volume) => _send(RemoteActions.setVolume, {'volume': volume});

  @override
  Future<void> setSpeed(double speed) => _send(RemoteActions.setSpeed, {'speed': speed});

  @override
  Future<void> setShuffle(bool enabled) => source.setShuffle(enabled);

  @override
  Future<void> setRepeat(RepeatMode mode) => source.setRepeat(mode);

  @override
  Future<void> setSleepTimer(int minutes, {bool finishSong = false}) =>
      _send(RemoteActions.setSleepTimer, {'minutes': minutes, if (finishSong) 'finishSong': true});

  @override
  Future<void> setFavorite(int songId, bool favorite) => source.setFavorite(songId, favorite);

  @override
  Future<RemoteLyrics> lyrics(int songId) => source.lyrics(songId);

  @override
  Widget art(int? songId, {required double size, double? radius}) =>
      RemoteArt(client: client, songId: songId, size: size, radius: radius);
}
