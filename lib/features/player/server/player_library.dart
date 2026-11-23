import 'dart:io';
import 'dart:typed_data';

import '../../../core/protocol/library_models.dart';
import '../../../data/repositories/library_repository.dart';
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
  Future<Uint8List?> artThumbnail(int songId);

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
  RepositoryPlayerLibrary(this._repo, {bool Function(String path)? fileExists})
      : _fileExists = fileExists ?? ((p) => File(p).existsSync());

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
  Future<Uint8List?> artThumbnail(int songId) async {
    final song = await _repo.songById(songId);
    final path = song?.albumArtPath;
    if (path == null) return null;
    if (_thumbs.containsKey(path)) return _thumbs[path];
    final thumb = await loadArtThumbnail(path);
    if (_thumbs.length > 40) _thumbs.remove(_thumbs.keys.first);
    return _thumbs[path] = thumb;
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
