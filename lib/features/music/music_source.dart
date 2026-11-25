import 'dart:typed_data';

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
    String? view,
    int? playlistId,
    int? folderId,
    String? groupKind,
    String? groupValue,
    int offset,
    int limit,
  });

  /// Genres, years or album artists ([GroupKind]) with their song counts.
  Future<LibraryPage<RemoteGroup>> groups({
    required String kind,
    String query,
    int offset,
    int limit,
  });

  /// The folder tree: the top folder (null: nothing from files), and the
  /// folders inside one folder ([parentId]; null: the top).
  Future<RemoteFolder?> folderRoot();
  Future<LibraryPage<RemoteFolder>> folderChildren({
    int? parentId,
    String query,
    int offset,
    int limit,
  });

  /// Lyrics for a library song.
  Future<RemoteLyrics> lyrics(int songId);

  /// The folders the Player's music is in.
  Future<LibraryPage<RemoteFolder>> folders({
    String query,
    int offset,
    int limit,
  });

  Future<LibraryPage<RemotePlaylist>> playlists({
    String query,
    int offset,
    int limit,
  });

  Future<void> setFavorite(int songId, bool favorite);

  /// A small picture of the song's album art (longest side [size] pixels), or
  /// null if it has none.
  Future<Uint8List?> artFor(int songId, {int size});

  /// Returns the new playlist id.
  Future<int> createPlaylist(String name);
  Future<void> renamePlaylist(int playlistId, String name);
  Future<void> deletePlaylist(int playlistId);

  /// How many songs were added (songs already in the playlist are skipped).
  Future<int> addToPlaylist(int playlistId, List<int> songIds);
  Future<void> removeFromPlaylist(int playlistId, int songId);

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
  ///
  /// With [keepQueue] the songs are played right away but the queue is not
  /// cleared: they go in after the current song.
  Future<void> playSongs(List<int> songIds, {int? startSongId, bool keepQueue = false});

  Future<void> queueSongs(List<int> songIds, {bool playNext = false});

  Future<QueueSnapshot> loadQueue();
  Future<void> removeQueueItem(int queueItemId);
  Future<void> moveQueueItem(int queueItemId, int newIndex);
  Future<void> clearQueue();
  Future<void> playQueueItem(int queueItemId);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeat(RepeatMode mode);

  /// Saves the current queue as a new playlist (library songs only).
  Future<({int added, int skipped})> saveQueueAsPlaylist(String name);
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
    String? view,
    int? playlistId,
    int? folderId,
    String? groupKind,
    String? groupValue,
    int offset = 0,
    int limit = 50,
  }) =>
      _client.songs(
          query: query,
          artist: artist,
          album: album,
          view: view,
          playlistId: playlistId,
          folderId: folderId,
          groupKind: groupKind,
          groupValue: groupValue,
          offset: offset,
          limit: limit);

  @override
  Future<LibraryPage<RemoteGroup>> groups({
    required String kind,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) =>
      _client.groups(kind: kind, query: query, offset: offset, limit: limit);

  @override
  Future<RemoteFolder?> folderRoot() => _client.folderRoot();

  @override
  Future<LibraryPage<RemoteFolder>> folderChildren({
    int? parentId,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) =>
      _client.folderChildren(parentId: parentId, query: query, offset: offset, limit: limit);

  @override
  Future<RemoteLyrics> lyrics(int songId) => _client.lyrics(songId);

  @override
  Future<LibraryPage<RemoteFolder>> folders(
          {String query = '', int offset = 0, int limit = 50}) =>
      _client.folders(query: query, offset: offset, limit: limit);

  @override
  Future<LibraryPage<RemotePlaylist>> playlists(
          {String query = '', int offset = 0, int limit = 50}) =>
      _client.playlists(query: query, offset: offset, limit: limit);

  @override
  Future<void> setFavorite(int songId, bool favorite) =>
      _client.setFavorite(songId, favorite);

  @override
  Future<Uint8List?> artFor(int songId, {int size = 96}) =>
      _client.artFor(songId, size: size);

  @override
  Future<int> createPlaylist(String name) async {
    final r = await _client.sendCommandForResult(
        RemoteActions.createPlaylist, {'name': name});
    return r['playlistId'] is num ? (r['playlistId'] as num).toInt() : 0;
  }

  @override
  Future<void> renamePlaylist(int playlistId, String name) => _client.sendCommand(
      RemoteActions.renamePlaylist, {'playlistId': playlistId, 'name': name});

  @override
  Future<void> deletePlaylist(int playlistId) =>
      _client.sendCommand(RemoteActions.deletePlaylist, {'playlistId': playlistId});

  @override
  Future<int> addToPlaylist(int playlistId, List<int> songIds) async {
    final r = await _client.sendCommandForResult(RemoteActions.addToPlaylist,
        {'playlistId': playlistId, 'songIds': songIds});
    return r['added'] is num ? (r['added'] as num).toInt() : 0;
  }

  @override
  Future<void> removeFromPlaylist(int playlistId, int songId) =>
      _client.sendCommand(RemoteActions.removeFromPlaylist,
          {'playlistId': playlistId, 'songId': songId});

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
  Future<void> playSongs(List<int> songIds,
          {int? startSongId, bool keepQueue = false}) =>
      _client.sendCommand(RemoteActions.playSong, {
        'songIds': songIds,
        'songId': startSongId ?? songIds.first,
        if (keepQueue) 'keepQueue': true,
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
  Future<({int added, int skipped})> saveQueueAsPlaylist(String name) async {
    final r = await _client
        .sendCommandForResult(RemoteActions.saveQueueAsPlaylist, {'name': name});
    int n(Object? v) => v is num ? v.toInt() : 0;
    return (added: n(r['added']), skipped: n(r['skipped']));
  }

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
