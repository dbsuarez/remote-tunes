import 'package:drift/drift.dart';

import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../../features/player/playback_engine.dart';
import '../../features/player/queue/playable_song.dart';
import '../database/app_database.dart';

const String unknownArtist = 'Unknown artist';
const String unknownAlbum = 'Unknown album';

/// The Player's music library (Drift `songs` table).
///
/// Missing artist/album are stored as [unknownArtist]/[unknownAlbum] so that
/// grouping and filtering stay simple. "Unavailable" (file missing) is worked
/// out at read time by checking the file, so no schema migration is needed.
class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  // ----------------------------------------------------------------- writing

  Future<int> addSong({
    required String title,
    required String artist,
    required String album,
    required String filePath,
    int? durationSeconds,
    int? trackNumber,
    String? albumArtPath,
    int? fileSizeBytes,
    String? mimeType,
  }) {
    return _db.into(_db.songs).insert(
          SongsCompanion.insert(
            title: title,
            artist: Value(artist),
            album: Value(album),
            durationSeconds: Value(durationSeconds),
            trackNumber: Value(trackNumber),
            filePath: Value(filePath),
            albumArtPath: Value(albumArtPath),
            fileSizeBytes: Value(fileSizeBytes),
            mimeType: Value(mimeType),
            source: SongSource.localFile.name,
          ),
        );
  }

  /// Deletes a song and returns it (so callers can remove its files).
  Future<Song?> removeSong(int id) async {
    final song = await songById(id);
    if (song == null) return null;
    await (_db.delete(_db.songs)..where((t) => t.id.equals(id))).go();
    return song;
  }

  // ------------------------------------------------- favorites / recently played

  Future<void> setFavorite(int songId, bool favorite) =>
      (_db.update(_db.songs)..where((t) => t.id.equals(songId)))
          .write(SongsCompanion(favorite: Value(favorite)));

  Future<Set<int>> favoriteIds() async {
    final rows = await _db.customSelect('SELECT id FROM songs WHERE favorite = 1').get();
    return {for (final r in rows) r.read<int>('id')};
  }

  /// Remembers that [songId] just started playing.
  Future<void> markPlayed(int songId) =>
      (_db.update(_db.songs)..where((t) => t.id.equals(songId)))
          .write(SongsCompanion(lastPlayedAt: Value(DateTime.now())));

  // ---------------------------------------------------------------- playlists

  static const maxPlaylistNameLength = 60;

  Future<LibraryPage<RemotePlaylist>> playlists({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final q = query.trim();
    final where = q.isEmpty ? '' : r"WHERE p.name LIKE ? ESCAPE '\'";
    final vars = q.isEmpty ? <Variable<Object>>[] : [Variable<String>(_like(q))];
    final total = (await _db
            .customSelect('SELECT COUNT(*) AS c FROM playlists p $where', variables: vars)
            .getSingle())
        .read<int>('c');
    final rows = await _db.customSelect(
      'SELECT p.id AS id, p.name AS name, '
      '(SELECT COUNT(*) FROM playlist_songs s WHERE s.playlist_id = p.id) AS c '
      'FROM playlists p $where '
      'ORDER BY p.name COLLATE NOCASE, p.id LIMIT ? OFFSET ?',
      variables: [...vars, Variable<int>(limit), Variable<int>(offset)],
    ).get();
    return LibraryPage(
      items: [
        for (final r in rows)
          RemotePlaylist(
              id: r.read<int>('id'),
              name: r.read<String>('name'),
              songCount: r.read<int>('c')),
      ],
      total: total,
      offset: offset,
    );
  }

  /// Trims and checks a playlist name; throws a [PlaybackException] with a
  /// plain-language message when it can't be used.
  static String cleanPlaylistName(String raw) {
    final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw PlaybackException(ErrorCodes.invalidAction, 'Give the playlist a name.');
    if (name.length > maxPlaylistNameLength) {
      throw PlaybackException(ErrorCodes.invalidAction,
          'Playlist names can be up to $maxPlaylistNameLength letters.');
    }
    return name;
  }

  Future<int> createPlaylist(String name) => _db
      .into(_db.playlists)
      .insert(PlaylistsCompanion.insert(name: cleanPlaylistName(name)));

  Future<bool> renamePlaylist(int id, String name) async {
    final n = await (_db.update(_db.playlists)..where((t) => t.id.equals(id)))
        .write(PlaylistsCompanion(name: Value(cleanPlaylistName(name))));
    return n > 0;
  }

  Future<bool> deletePlaylist(int id) async =>
      await (_db.delete(_db.playlists)..where((t) => t.id.equals(id))).go() > 0;

  /// Adds songs to the end of a playlist, skipping ones already in it and ids
  /// that are not in the library. Returns how many were added; null if the
  /// playlist does not exist.
  Future<int?> addToPlaylist(int playlistId, List<int> songIds) async {
    final exists = await _db
        .customSelect('SELECT 1 FROM playlists WHERE id = ?',
            variables: [Variable<int>(playlistId)])
        .get();
    if (exists.isEmpty) return null;
    final songs = await songsByIds(songIds);
    final inList = {
      for (final r in await _db.customSelect(
          'SELECT song_id FROM playlist_songs WHERE playlist_id = ?',
          variables: [Variable<int>(playlistId)]).get())
        r.read<int>('song_id'),
    };
    final posRow = await _db.customSelect(
        'SELECT IFNULL(MAX(position), -1) AS m FROM playlist_songs WHERE playlist_id = ?',
        variables: [Variable<int>(playlistId)]).getSingle();
    var pos = posRow.read<int>('m');
    var added = 0;
    await _db.transaction(() async {
      for (final s in songs) {
        if (!inList.add(s.id)) continue;
        pos++;
        added++;
        await _db.into(_db.playlistSongs).insert(PlaylistSongsCompanion.insert(
            playlistId: playlistId, songId: s.id, position: pos));
      }
    });
    return added;
  }

  Future<void> removeFromPlaylist(int playlistId, int songId) =>
      (_db.delete(_db.playlistSongs)
            ..where((t) => t.playlistId.equals(playlistId) & t.songId.equals(songId)))
          .go();

  // ----------------------------------------------------------------- lookups

  Future<Song?> songById(int id) =>
      (_db.select(_db.songs)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Song?> findByPath(String path) =>
      (_db.select(_db.songs)..where((t) => t.filePath.equals(path)))
          .getSingleOrNull();

  /// Songs for [ids] in the same order, skipping unknown ids.
  Future<List<Song>> songsByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows =
        await (_db.select(_db.songs)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final s in rows) s.id: s};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// True if an equivalent song is already in the library (used to skip
  /// duplicates when importing copied files, whose paths always differ).
  Future<bool> hasDuplicate({
    required String title,
    required String artist,
    required String album,
    int? durationSeconds,
    int? fileSizeBytes,
  }) async {
    final rows = await _db.customSelect(
      'SELECT 1 FROM songs WHERE title = ? AND artist = ? AND album = ? '
      'AND IFNULL(duration_seconds, -1) = ? AND IFNULL(file_size_bytes, -1) = ? '
      'LIMIT 1',
      variables: [
        Variable<String>(title),
        Variable<String>(artist),
        Variable<String>(album),
        Variable<int>(durationSeconds ?? -1),
        Variable<int>(fileSizeBytes ?? -1),
      ],
    ).get();
    return rows.isNotEmpty;
  }

  /// Album art already stored for this artist+album, so songs of one album
  /// share a single image file.
  Future<String?> albumArtFor(String artist, String album) async {
    final rows = await _db.customSelect(
      'SELECT album_art_path AS p FROM songs WHERE artist = ? AND album = ? '
      'AND album_art_path IS NOT NULL LIMIT 1',
      variables: [Variable<String>(artist), Variable<String>(album)],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('p');
  }

  /// How many songs use this album-art file.
  Future<int> songsUsingArt(String path) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM songs WHERE album_art_path = ?',
      variables: [Variable<String>(path)],
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> count() async {
    final row =
        await _db.customSelect('SELECT COUNT(*) AS c FROM songs').getSingle();
    return row.read<int>('c');
  }

  // ----------------------------------------------------------------- queries

  /// Escapes LIKE wildcards so user text is matched literally.
  static String _like(String q) => '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  ({String where, List<Variable<Object>> vars}) _songFilter({
    String query = '',
    String? artist,
    String? album,
    String? view,
    int? playlistId,
  }) {
    final clauses = <String>[];
    final vars = <Variable<Object>>[];
    if (view == LibraryView.favorites) clauses.add('favorite = 1');
    if (view == LibraryView.recent) clauses.add('last_played_at IS NOT NULL');
    if (playlistId != null) {
      clauses.add('id IN (SELECT song_id FROM playlist_songs WHERE playlist_id = ?)');
      vars.add(Variable<int>(playlistId));
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      clauses.add(r"(title LIKE ? ESCAPE '\' OR artist LIKE ? ESCAPE '\' OR album LIKE ? ESCAPE '\')");
      final p = _like(q);
      vars.addAll([Variable<String>(p), Variable<String>(p), Variable<String>(p)]);
    }
    if (artist != null) {
      clauses.add('artist = ?');
      vars.add(Variable<String>(artist));
    }
    if (album != null) {
      clauses.add('album = ?');
      vars.add(Variable<String>(album));
    }
    return (
      where: clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}',
      vars: vars,
    );
  }

  String _songOrder({String? artist, String? album, String? view, int? playlistId}) {
    if (view == LibraryView.recent) return 'ORDER BY last_played_at DESC, id';
    if (playlistId != null) {
      return 'ORDER BY (SELECT position FROM playlist_songs ps '
          'WHERE ps.playlist_id = $playlistId AND ps.song_id = songs.id), id';
    }
    if (album != null) {
      return 'ORDER BY COALESCE(track_number, 9999), title COLLATE NOCASE, id';
    }
    if (artist != null) {
      return 'ORDER BY album COLLATE NOCASE, COALESCE(track_number, 9999), title COLLATE NOCASE, id';
    }
    return 'ORDER BY title COLLATE NOCASE, artist COLLATE NOCASE, id';
  }

  /// Live list of songs (Player library screen).
  Stream<List<Song>> watchSongs({String query = ''}) {
    final f = _songFilter(query: query);
    return _db
        .customSelect(
          'SELECT * FROM songs ${f.where} ${_songOrder()}',
          variables: f.vars,
          readsFrom: {_db.songs},
        )
        .watch()
        .map((rows) => [for (final r in rows) _db.songs.map(r.data)]);
  }

  Future<LibraryPage<Song>> songs({
    String query = '',
    String? artist,
    String? album,
    String? view,
    int? playlistId,
    int offset = 0,
    int limit = 50,
  }) async {
    final f = _songFilter(
        query: query, artist: artist, album: album, view: view, playlistId: playlistId);
    final total = (await _db
            .customSelect('SELECT COUNT(*) AS c FROM songs ${f.where}',
                variables: f.vars)
            .getSingle())
        .read<int>('c');
    final rows = await _db.customSelect(
      'SELECT * FROM songs ${f.where} ${_songOrder(artist: artist, album: album, view: view, playlistId: playlistId)} '
      'LIMIT ? OFFSET ?',
      variables: [...f.vars, Variable<int>(limit), Variable<int>(offset)],
    ).get();
    return LibraryPage(
      items: [for (final r in rows) _db.songs.map(r.data)],
      total: total,
      offset: offset,
    );
  }

  Future<LibraryPage<RemoteArtist>> artists({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final q = query.trim();
    final where = q.isEmpty ? '' : r"WHERE artist LIKE ? ESCAPE '\'";
    final vars = q.isEmpty ? <Variable<Object>>[] : [Variable<String>(_like(q))];
    final total = (await _db
            .customSelect(
                'SELECT COUNT(*) AS c FROM (SELECT 1 FROM songs $where GROUP BY artist)',
                variables: vars)
            .getSingle())
        .read<int>('c');
    final rows = await _db.customSelect(
      'SELECT artist AS name, COUNT(*) AS song_count, '
      'COUNT(DISTINCT album) AS album_count FROM songs $where '
      'GROUP BY artist ORDER BY artist COLLATE NOCASE LIMIT ? OFFSET ?',
      variables: [...vars, Variable<int>(limit), Variable<int>(offset)],
    ).get();
    return LibraryPage(
      items: [
        for (final r in rows)
          RemoteArtist(
            name: r.read<String>('name'),
            songCount: r.read<int>('song_count'),
            albumCount: r.read<int>('album_count'),
          ),
      ],
      total: total,
      offset: offset,
    );
  }

  Future<LibraryPage<RemoteAlbum>> albums({
    String query = '',
    String? artist,
    int offset = 0,
    int limit = 50,
  }) async {
    final clauses = <String>[];
    final vars = <Variable<Object>>[];
    final q = query.trim();
    if (q.isNotEmpty) {
      clauses.add(r"(album LIKE ? ESCAPE '\' OR artist LIKE ? ESCAPE '\')");
      vars.addAll([Variable<String>(_like(q)), Variable<String>(_like(q))]);
    }
    if (artist != null) {
      clauses.add('artist = ?');
      vars.add(Variable<String>(artist));
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final total = (await _db
            .customSelect(
                'SELECT COUNT(*) AS c FROM (SELECT 1 FROM songs $where GROUP BY album, artist)',
                variables: vars)
            .getSingle())
        .read<int>('c');
    final rows = await _db.customSelect(
      'SELECT album AS name, artist, COUNT(*) AS song_count FROM songs $where '
      'GROUP BY album, artist ORDER BY album COLLATE NOCASE, artist COLLATE NOCASE '
      'LIMIT ? OFFSET ?',
      variables: [...vars, Variable<int>(limit), Variable<int>(offset)],
    ).get();
    return LibraryPage(
      items: [
        for (final r in rows)
          RemoteAlbum(
            name: r.read<String>('name'),
            artist: r.read<String>('artist'),
            songCount: r.read<int>('song_count'),
          ),
      ],
      total: total,
      offset: offset,
    );
  }
}

extension SongMapping on Song {
  /// Null for songs without a local file (URL songs arrive in Phase 3).
  PlayableSong? toPlayable() {
    final path = filePath;
    if (path == null) return null;
    return PlayableSong(
      id: id,
      title: title,
      artist: artist ?? unknownArtist,
      album: album ?? unknownAlbum,
      filePath: path,
      durationSeconds: durationSeconds ?? 0,
      trackNumber: trackNumber,
      albumArtPath: albumArtPath,
    );
  }

  RemoteSong toRemote({required bool available}) => RemoteSong(
        id: id,
        title: title,
        artist: artist ?? unknownArtist,
        album: album ?? unknownAlbum,
        durationSeconds: durationSeconds ?? 0,
        trackNumber: trackNumber,
        available: available,
        favorite: favorite,
      );
}
