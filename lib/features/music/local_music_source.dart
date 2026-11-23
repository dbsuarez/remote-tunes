import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../player/playback_engine.dart';
import '../player/queue/playable_song.dart';
import '../player/queue_aware_engine.dart';
import '../player/server/player_library.dart';
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
    int offset = 0,
    int limit = 50,
  }) =>
      _library.songs(
          query: query, artist: artist, album: album, offset: offset, limit: limit);

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
  Future<void> playSongs(List<int> songIds, {int? startSongId}) async {
    final songs = await _resolve(songIds);
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
  Future<void> clearQueue() => _engine.clearQueue();

  @override
  Future<void> playQueueItem(int id) => _engine.playQueueItem(id);

  @override
  Future<void> setShuffle(bool enabled) => _engine.setShuffle(enabled);

  @override
  Future<void> setRepeat(RepeatMode mode) => _engine.setRepeatMode(mode);
}
