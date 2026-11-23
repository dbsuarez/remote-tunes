import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../controller/controller_client.dart';
import '../library/import_exception.dart';
import '../player/playback_engine.dart';

/// Everything the library and queue screens need. The Controller implements it
/// by talking to the Player over the network; the Player implements it
/// directly. The same screens work for both.
abstract class MusicSource {
  Future<LibraryPage<RemoteSong>> songs({
    String query,
    String? artist,
    String? album,
    int offset,
    int limit,
  });

  Future<LibraryPage<RemoteArtist>> artists({
    String query,
    int offset,
    int limit,
  });

  Future<LibraryPage<RemoteAlbum>> albums({
    String query,
    String? artist,
    int offset,
    int limit,
  });

  /// Replaces the queue with [songIds] and plays, starting at [startSongId].
  Future<void> playSongs(List<int> songIds, {int? startSongId});

  Future<void> queueSongs(List<int> songIds, {bool playNext = false});

  Future<QueueSnapshot> loadQueue();
  Future<void> removeQueueItem(int queueItemId);
  Future<void> moveQueueItem(int queueItemId, int newIndex);
  Future<void> clearQueue();
  Future<void> playQueueItem(int queueItemId);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeat(RepeatMode mode);
}

/// Controller side: every call is a protocol request to the Player.
class RemoteMusicSource implements MusicSource {
  RemoteMusicSource(this._client);

  final ControllerClient _client;

  @override
  Future<LibraryPage<RemoteSong>> songs({
    String query = '',
    String? artist,
    String? album,
    int offset = 0,
    int limit = 50,
  }) =>
      _client.songs(
          query: query, artist: artist, album: album, offset: offset, limit: limit);

  @override
  Future<LibraryPage<RemoteArtist>> artists({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) =>
      _client.artists(query: query, offset: offset, limit: limit);

  @override
  Future<LibraryPage<RemoteAlbum>> albums({
    String query = '',
    String? artist,
    int offset = 0,
    int limit = 50,
  }) =>
      _client.albums(query: query, artist: artist, offset: offset, limit: limit);

  @override
  Future<void> playSongs(List<int> songIds, {int? startSongId}) =>
      _client.sendCommand(RemoteActions.playSong, {
        'songIds': songIds,
        'songId': startSongId ?? songIds.first,
      });

  @override
  Future<void> queueSongs(List<int> songIds, {bool playNext = false}) =>
      _client.sendCommand(
          RemoteActions.queueSong, {'songIds': songIds, 'playNext': playNext});

  @override
  Future<QueueSnapshot> loadQueue() => _client.getQueue();

  @override
  Future<void> removeQueueItem(int id) =>
      _client.sendCommand(RemoteActions.removeQueueItem, {'queueItemId': id});

  @override
  Future<void> moveQueueItem(int id, int newIndex) => _client.sendCommand(
      RemoteActions.moveQueueItem, {'queueItemId': id, 'newIndex': newIndex});

  @override
  Future<void> clearQueue() => _client.sendCommand(RemoteActions.clearQueue);

  @override
  Future<void> playQueueItem(int id) =>
      _client.sendCommand(RemoteActions.playQueueItem, {'queueItemId': id});

  @override
  Future<void> setShuffle(bool enabled) =>
      _client.sendCommand(RemoteActions.setShuffle, {'enabled': enabled});

  @override
  Future<void> setRepeat(RepeatMode mode) =>
      _client.sendCommand(RemoteActions.setRepeatMode, {'mode': mode.name});
}

/// Plain-language text for any error the screens may catch.
String friendlyError(Object error) {
  if (error is ControllerException) return error.message;
  if (error is PlaybackException) return error.message;
  if (error is ImportException) return error.message;
  return 'Something went wrong. Please try again.';
}
