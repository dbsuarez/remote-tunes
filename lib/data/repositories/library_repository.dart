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
    String? albumArtist,
    String? genre,
    int? year,
    double? replayGainDb,
    double? albumGainDb,
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
            albumArtist: Value(albumArtist),
            genre: Value(genre),
            year: Value(year),
            replayGainDb: Value(replayGainDb),
            albumGainDb: Value(albumGainDb),
            source: SongSource.localFile.name,
          ),
        );
  }

  /// Local songs with the file they play (to read their tags again).
  Future<List<({int id, String path})>> localSongFiles() async {
    final rows = await _db
        .customSelect('SELECT id, file_path FROM songs WHERE file_path IS NOT NULL ORDER BY id')
        .get();
    return [for (final r in rows) (id: r.read<int>('id'), path: r.read<String>('file_path'))];
  }

  /// Saves the album artist, genre and year read from a file's tags. A tag the
  /// file does not have leaves what is saved as it is.
  Future<void> updateSongTags(
    int id, {
    String? albumArtist,
    String? genre,
    int? year,
    double? replayGainDb,
    double? albumGainDb,
  }) =>
      (_db.update(_db.songs)..where((t) => t.id.equals(id))).write(SongsCompanion(
        albumArtist: albumArtist == null ? const Value.absent() : Value(albumArtist),
        genre: genre == null ? const Value.absent() : Value(genre),
        year: year == null ? const Value.absent() : Value(year),
        replayGainDb: replayGainDb == null ? const Value.absent() : Value(replayGainDb),
        albumGainDb: albumGainDb == null ? const Value.absent() : Value(albumGainDb),
      ));

  static String? _groupColumn(String? kind) => switch (kind) {
        GroupKind.genre => 'genre',
        GroupKind.year => 'year',
        GroupKind.albumArtist => 'album_artist',
        _ => null,
      };

  /// Genres, years or album artists with their song counts.
  Future<LibraryPage<RemoteGroup>> groups({
    required String kind,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final col = _groupColumn(kind);
    if (col == null) return LibraryPage(items: const [], total: 0, offset: offset);
    final q = query.trim();
    final where = StringBuffer("WHERE $col IS NOT NULL AND CAST($col AS TEXT) != ''");
    final vars = <Variable<Object>>[];
    if (q.isNotEmpty) {
      where.write(" AND CAST($col AS TEXT) LIKE ? ESCAPE '\\'");
      vars.add(Variable<String>(_like(q)));
    }
    final order = kind == GroupKind.year ? 'ORDER BY $col DESC' : 'ORDER BY $col COLLATE NOCASE';
    final total = (await _db
            .customSelect('SELECT COUNT(*) AS c FROM (SELECT 1 FROM songs $where GROUP BY $col)',
                variables: vars)
            .getSingle())
        .read<int>('c');
    final rows = await _db.customSelect(
      'SELECT CAST($col AS TEXT) AS name, COUNT(*) AS song_count FROM songs $where '
      'GROUP BY $col $order LIMIT ? OFFSET ?',
      variables: [...vars, Variable<int>(limit), Variable<int>(offset)],
    ).get();
    return LibraryPage(
      items: [
        for (final r in rows)
          RemoteGroup(name: r.read<String>('name'), songCount: r.read<int>('song_count')),
      ],
      total: total,
      offset: offset,
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

  static const maxTagLength = 200;

  /// Changes how a song is listed (title, artist, album, track number) in this
  /// library. The music file itself is not touched. Returns false if the song is
  /// gone or the title is empty.
  Future<bool> updateSongInfo(
    int songId, {
    required String title,
    required String artist,
    required String album,
    int? trackNumber,
  }) async {
    String clip(String s) {
      final t = s.trim();
      return t.length > maxTagLength ? t.substring(0, maxTagLength) : t;
    }

    final t = clip(title);
    if (t.isEmpty) return false;
    final n = (trackNumber != null && trackNumber > 0 && trackNumber < 10000) ? trackNumber : null;
    final rows = await (_db.update(_db.songs)..where((x) => x.id.equals(songId))).write(
      SongsCompanion(
        title: Value(t),
        artist: Value(clip(artist).isEmpty ? 'Unknown artist' : clip(artist)),
        album: Value(clip(album).isEmpty ? 'Unknown album' : clip(album)),
        trackNumber: Value(n),
      ),
    );
    return rows > 0;
  }

  /// Remembers that [songId] just started playing.
  Future<void> markPlayed(int songId) => _db.customUpdate(
        'UPDATE songs SET last_played_at = ?, play_count = play_count + 1 WHERE id = ?',
        variables: [Variable<DateTime>(DateTime.now()), Variable<int>(songId)],
        updates: {_db.songs},
      );

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
    List<int>? onlyIds,
    String? groupKind,
    String? groupValue,
  }) {
    final clauses = <String>[];
    final vars = <Variable<Object>>[];
    final groupCol = _groupColumn(groupKind);
    if (groupCol != null && groupValue != null) {
      clauses.add('CAST($groupCol AS TEXT) = ?');
      vars.add(Variable<String>(groupValue));
    }
    if (view == LibraryView.favorites) clauses.add('favorite = 1');
    if (view == LibraryView.recent) clauses.add('last_played_at IS NOT NULL');
    if (view == LibraryView.top) {
      clauses.add('id IN (SELECT id FROM songs WHERE play_count > 0 '
          'ORDER BY play_count DESC, last_played_at DESC, id LIMIT $autoListSize)');
    }
    if (view == LibraryView.newest) {
      clauses.add('id IN (SELECT id FROM songs ORDER BY added_at DESC, id DESC '
          'LIMIT $autoListSize)');
    }
    if (onlyIds != null) {
      // Ids are integers we made ourselves, so they are safe to write in.
      clauses.add('id IN (${onlyIds.isEmpty ? '0' : onlyIds.join(',')})');
    }
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
    if (view == LibraryView.top) return 'ORDER BY play_count DESC, last_played_at DESC, id';
    if (view == LibraryView.newest) return 'ORDER BY added_at DESC, id DESC';
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
    int? folderId,
    String? groupKind,
    String? groupValue,
    int offset = 0,
    int limit = 50,
  }) async {
    final f = _songFilter(
        groupKind: groupKind,
        groupValue: groupValue,
        query: query,
        artist: artist,
        album: album,
        view: view,
        playlistId: playlistId,
        onlyIds: folderId == null ? null : (await _folderSongIds())[folderId] ?? const []);
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

  /// How many songs the "Top" and "New" lists hold at most.
  static const autoListSize = 100;

  /// A number for a folder, the same every time for the same path.
  static int folderIdOf(String dir) {
    var h = 0x811c9dc5;
    for (final u in dir.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  static String _dirOf(String path) {
    final i = path.replaceAll(r'\', '/').lastIndexOf('/');
    return i <= 0 ? '/' : path.replaceAll(r'\', '/').substring(0, i);
  }

  static String _lastPart(String dir) {
    final parts = dir.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? '/' : parts.last;
  }

  /// Song ids per folder id (library songs with a file only).
  Future<Map<int, List<int>>> _folderSongIds() async {
    final rows = await _db
        .customSelect('SELECT id, file_path FROM songs WHERE file_path IS NOT NULL')
        .get();
    final byDir = <String, List<int>>{};
    for (final r in rows) {
      byDir.putIfAbsent(_dirOf(r.read<String>('file_path')), () => []).add(r.read<int>('id'));
    }
    return {for (final e in byDir.entries) folderIdOf(e.key): e.value};
  }

  /// The folders the music is in, with how many songs each holds.
  Future<LibraryPage<RemoteFolder>> folders({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final rows = await _db
        .customSelect('SELECT file_path FROM songs WHERE file_path IS NOT NULL')
        .get();
    final counts = <String, int>{};
    for (final r in rows) {
      final d = _dirOf(r.read<String>('file_path'));
      counts[d] = (counts[d] ?? 0) + 1;
    }
    final q = query.trim().toLowerCase();
    final all = [
      for (final e in counts.entries)
        if (q.isEmpty || _lastPart(e.key).toLowerCase().contains(q))
          RemoteFolder(
            id: folderIdOf(e.key),
            name: _lastPart(e.key),
            parent: e.key == '/' ? '' : _lastPart(_dirOf(e.key)),
            songCount: e.value,
          ),
    ]..sort((a, b) {
        final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return c != 0 ? c : a.parent.toLowerCase().compareTo(b.parent.toLowerCase());
      });
    final end = (offset + limit) > all.length ? all.length : offset + limit;
    return LibraryPage(
      items: offset >= all.length ? const [] : all.sublist(offset, end),
      total: all.length,
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
      replayGainDb: replayGainDb,
      albumGainDb: albumGainDb,
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
