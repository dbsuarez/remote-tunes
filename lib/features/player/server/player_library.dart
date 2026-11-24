import 'dart:io';
import 'dart:typed_data';

import '../../../core/protocol/library_models.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../data/repositories/online_history_repository.dart';
import '../queue/playable_song.dart';
import 'art_thumbnail.dart';

/// What the Player server needs from the library. Results never include file
/// paths (FR-46); [playableByIds] is for the Player's own engine only.
abstract class PlayerLibrary {
  Future<LibraryPage<RemoteSong>> songs({
    String query,
    String? artist,
    String? album,
    String? view,
    int? playlistId,
    int offset,
    int limit,
  });

  Future<LibraryPage<RemotePlaylist>> playlists({
    String query,
    int offset,
    int limit,
  });

  /// Favorites and recently played. [isFavorite] answers from memory so the
  /// Player can add it to every state message.
  bool isFavorite(int songId);
  Future<void> setFavorite(int songId, bool favorite);
  Future<void> markPlayed(int songId);

  /// Returns the new playlist's id. Throws a PlaybackException for bad names.
  Future<int> createPlaylist(String name);
  Future<bool> renamePlaylist(int id, String name);
  Future<bool> deletePlaylist(int id);

  /// How many were added (already-listed songs are skipped); null if the
  /// playlist does not exist.
  Future<int?> addToPlaylist(int playlistId, List<int> songIds);
  Future<void> removeFromPlaylist(int playlistId, int songId);

  /// A small JPEG of the song's album art, or null if it has none.
  Future<Uint8List?> artThumbnail(int songId, {int size});

  // Online Library history (text and links only, on this phone).
  Future<LibraryPage<RemoteHistoryItem>> onlineHistory({int offset, int limit});
  Future<bool> historyEnabled();
  Future<void> setHistoryEnabled(bool enabled);

  /// Remembers an internet track that started playing (only Online Library
  /// tracks are kept, and only while history is on).
  Future<void> recordStream(PlayableSong song);

  /// The track behind a history entry, or null if it was removed.
  Future<PlayableSong?> historySong(int id);
  Future<void> removeHistory(int id);
  Future<void> clearHistory();

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

  /// Playable songs for [ids], in the same order, skipping unknown ids.
  Future<List<PlayableSong>> playableByIds(List<int> ids);
}

class RepositoryPlayerLibrary implements PlayerLibrary {
  RepositoryPlayerLibrary(this._repo,
      {bool Function(String path)? fileExists, OnlineHistoryRepository? history})
      : _fileExists = fileExists ?? ((p) => File(p).existsSync()),
        _history = history;

  final OnlineHistoryRepository? _history;

  final LibraryRepository _repo;
  final bool Function(String path) _fileExists;
  Set<int> _favorites = {};
  bool _favoritesLoaded = false;
  final Map<String, Uint8List?> _thumbs = {};

  Future<void> _loadFavorites() async {
    if (_favoritesLoaded) return;
    _favorites = await _repo.favoriteIds();
    _favoritesLoaded = true;
  }

  @override
  Future<LibraryPage<RemoteHistoryItem>> onlineHistory({int offset = 0, int limit = 50}) async =>
      _history?.list(offset: offset, limit: limit) ??
      const LibraryPage(items: [], total: 0, offset: 0);

  @override
  Future<bool> historyEnabled() async => await _history?.isEnabled() ?? false;

  @override
  Future<void> setHistoryEnabled(bool enabled) async =>
      _history?.setEnabled(enabled);

  @override
  Future<void> recordStream(PlayableSong song) async => _history?.record(song);

  @override
  Future<PlayableSong?> historySong(int id) async => _history?.song(id);

  @override
  Future<void> removeHistory(int id) async => _history?.remove(id);

  @override
  Future<void> clearHistory() async => _history?.clear();

  @override
  bool isFavorite(int songId) => _favorites.contains(songId);

  @override
  Future<void> setFavorite(int songId, bool favorite) async {
    await _loadFavorites();
    await _repo.setFavorite(songId, favorite);
    favorite ? _favorites.add(songId) : _favorites.remove(songId);
  }

  @override
  Future<void> markPlayed(int songId) => _repo.markPlayed(songId);

  @override
  Future<LibraryPage<RemotePlaylist>> playlists(
          {String query = '', int offset = 0, int limit = 50}) =>
      _repo.playlists(query: query, offset: offset, limit: limit);

  @override
  Future<int> createPlaylist(String name) => _repo.createPlaylist(name);

  @override
  Future<bool> renamePlaylist(int id, String name) => _repo.renamePlaylist(id, name);

  @override
  Future<bool> deletePlaylist(int id) => _repo.deletePlaylist(id);

  @override
  Future<int?> addToPlaylist(int playlistId, List<int> songIds) =>
      _repo.addToPlaylist(playlistId, songIds);

  @override
  Future<void> removeFromPlaylist(int playlistId, int songId) =>
      _repo.removeFromPlaylist(playlistId, songId);

  @override
  Future<Uint8List?> artThumbnail(int songId, {int size = artThumbnailSize}) async {
    final song = await _repo.songById(songId);
    final path = song?.albumArtPath;
    if (path == null) return null;
    // Songs of one album share a picture, so this is made once per album.
    final key = '$path|$size';
    if (_thumbs.containsKey(key)) return _thumbs[key];
    final thumb = await loadArtThumbnail(path, size: size);
    if (_thumbs.length > 300) _thumbs.remove(_thumbs.keys.first);
    return _thumbs[key] = thumb;
  }

  @override
  Future<LibraryPage<RemoteSong>> songs({
    String query = '',
    String? artist,
    String? album,
    String? view,
    int? playlistId,
    int offset = 0,
    int limit = 50,
  }) async {
    await _loadFavorites();
    final page = await _repo.songs(
      query: query,
      artist: artist,
      album: album,
      view: view,
      playlistId: playlistId,
      offset: offset,
      limit: limit,
    );
    return LibraryPage(
      items: [
        for (final s in page.items)
          s.toRemote(
            available: s.filePath != null && _fileExists(s.filePath!),
          ),
      ],
      total: page.total,
      offset: page.offset,
    );
  }

  @override
  Future<LibraryPage<RemoteArtist>> artists({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) =>
      _repo.artists(query: query, offset: offset, limit: limit);

  @override
  Future<LibraryPage<RemoteAlbum>> albums({
    String query = '',
    String? artist,
    int offset = 0,
    int limit = 50,
  }) =>
      _repo.albums(query: query, artist: artist, offset: offset, limit: limit);

  @override
  Future<List<PlayableSong>> playableByIds(List<int> ids) async {
    final songs = await _repo.songsByIds(ids);
    return [
      for (final s in songs)
        if (s.toPlayable() != null) s.toPlayable()!,
    ];
  }
}
