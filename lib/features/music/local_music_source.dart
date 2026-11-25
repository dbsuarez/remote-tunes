import 'dart:typed_data';

import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../player/playback_engine.dart';
import '../player/queue/playable_song.dart';
import '../player/queue_aware_engine.dart';
import '../player/server/player_library.dart';
import '../player/save_queue.dart' as save_queue;
import 'music_source.dart';

/// Player side: direct calls into the library and the engine.
class LocalMusicSource implements MusicSource {
  LocalMusicSource(this._library, this._engine);

  final PlayerLibrary _library;
  final QueueAwareEngine _engine;

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
      _library.songs(
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
  Future<LibraryPage<RemotePlaylist>> playlists(
          {String query = '', int offset = 0, int limit = 50}) =>
      _library.playlists(query: query, offset: offset, limit: limit);

  @override
  Future<void> setFavorite(int songId, bool favorite) =>
      _library.setFavorite(songId, favorite);

  @override
  Future<Uint8List?> artFor(int songId, {int size = 96}) =>
      _library.artThumbnail(songId, size: size);

  @override
  Future<int> createPlaylist(String name) => _library.createPlaylist(name);

  @override
  Future<void> renamePlaylist(int playlistId, String name) async {
    if (!await _library.renamePlaylist(playlistId, name)) throw _gone();
  }

  @override
  Future<void> deletePlaylist(int playlistId) async {
    if (!await _library.deletePlaylist(playlistId)) throw _gone();
  }

  @override
  Future<int> addToPlaylist(int playlistId, List<int> songIds) async {
    final n = await _library.addToPlaylist(playlistId, songIds);
    if (n == null) throw _gone();
    return n;
  }

  @override
  Future<void> removeFromPlaylist(int playlistId, int songId) =>
      _library.removeFromPlaylist(playlistId, songId);

  PlaybackException _gone() =>
      PlaybackException(ErrorCodes.invalidAction, 'That playlist no longer exists.');

  @override
  Future<LibraryPage<RemoteGroup>> groups({
    required String kind,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) =>
      _library.groups(kind: kind, query: query, offset: offset, limit: limit);

  @override
  Future<RemoteLyrics> lyrics(int songId) => _library.lyrics(songId);

  @override
  Future<LibraryPage<RemoteFolder>> folders({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) =>
      _library.folders(query: query, offset: offset, limit: limit);

  @override
  Future<LibraryPage<RemoteArtist>> artists({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) =>
      _library.artists(query: query, offset: offset, limit: limit);

  @override
  Future<LibraryPage<RemoteAlbum>> albums({
    String query = '',
    String? artist,
    int offset = 0,
    int limit = 50,
  }) =>
      _library.albums(query: query, artist: artist, offset: offset, limit: limit);

  Future<List<PlayableSong>> _resolve(List<int> ids) async {
    final songs = await _library.playableByIds(ids);
    if (songs.isEmpty) {
      throw PlaybackException(
        ErrorCodes.fileNotFound,
        'Those songs are no longer in the library.',
      );
    }
    return songs;
  }

  @override
  Future<void> playSongs(List<int> songIds,
      {int? startSongId, bool keepQueue = false}) async {
    final songs = await _resolve(songIds);
    if (keepQueue) {
      await _engine.playNow(songs);
      return;
    }
    final start = startSongId == null
        ? 0
        : songs.indexWhere((s) => s.id == startSongId).clamp(0, songs.length - 1);
    await _engine.playSongs(songs, startIndex: start);
  }

  @override
  Future<void> queueSongs(List<int> songIds, {bool playNext = false}) async {
    await _engine.enqueue(await _resolve(songIds), playNext: playNext);
  }

  @override
  Future<QueueSnapshot> loadQueue() async => _engine.queueSnapshot();

  @override
  Future<void> removeQueueItem(int id) => _engine.removeQueueItem(id);

  @override
  Future<void> moveQueueItem(int id, int newIndex) =>
      _engine.moveQueueItem(id, newIndex);

  @override
  Future<({int added, int skipped})> saveQueueAsPlaylist(String name) async {
    final saved = await save_queue.saveQueueAsPlaylist(
      queue: _engine.queueSnapshot(),
      name: name,
      createPlaylist: _library.createPlaylist,
      addToPlaylist: _library.addToPlaylist,
      deletePlaylist: _library.deletePlaylist,
    );
    return (added: saved.added, skipped: saved.skipped);
  }

  @override
  Future<void> clearQueue() => _engine.clearQueue();

  @override
  Future<void> playQueueItem(int id) => _engine.playQueueItem(id);

  @override
  Future<void> setShuffle(bool enabled) => _engine.setShuffle(enabled);

  @override
  Future<void> setRepeat(RepeatMode mode) => _engine.setRepeatMode(mode);
}
