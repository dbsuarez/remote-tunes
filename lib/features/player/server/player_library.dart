import 'dart:io';

import '../../../core/protocol/library_models.dart';
import '../../../data/repositories/library_repository.dart';
import '../queue/playable_song.dart';

/// What the Player server needs from the library. Results never include file
/// paths (FR-46); [playableByIds] is for the Player's own engine only.
abstract class PlayerLibrary {
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

  /// Playable songs for [ids], in the same order, skipping unknown ids.
  Future<List<PlayableSong>> playableByIds(List<int> ids);
}

class RepositoryPlayerLibrary implements PlayerLibrary {
  RepositoryPlayerLibrary(this._repo, {bool Function(String path)? fileExists})
      : _fileExists = fileExists ?? ((p) => File(p).existsSync());

  final LibraryRepository _repo;
  final bool Function(String path) _fileExists;

  @override
  Future<LibraryPage<RemoteSong>> songs({
    String query = '',
    String? artist,
    String? album,
    int offset = 0,
    int limit = 50,
  }) async {
    final page = await _repo.songs(
      query: query,
      artist: artist,
      album: album,
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
