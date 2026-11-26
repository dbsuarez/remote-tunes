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
    String? composer,
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
            composer: Value(composer),
            source: SongSource.localFile.name,
          ),
        );
  }

  /// Local songs with what is needed to name them and find their file (for the rescan).
  Future<List<({int id, String title, String artist, String path})>> localSongsDetail() async {
    final rows = await _db
        .customSelect(
            'SELECT id, title, artist, file_path FROM songs WHERE file_path IS NOT NULL ORDER BY id')
        .get();
    return [
      for (final r in rows)
        (
          id: r.read<int>('id'),
          title: r.read<String>('title'),
          artist: r.readNullable<String>('artist') ?? '',
          path: r.read<String>('file_path'),
        ),
    ];
  }

  /// Local songs with the file they play (to read their tags again).
  Future<List<({int id, String path})>> localSongFiles() async {
    final rows = await _db
        .customSelect('SELECT id, file_path FROM songs WHERE file_path IS NOT NULL ORDER BY id')
        .get();
    return [for (final r in rows) (id: r.read<int>('id'), path: r.read<String>('file_path'))];
  }

  /// Songs with a file whose edits are not flagged yet: what the library says now, to be compared
  /// with the file's own tags.
  Future<List<({int id, String title, String artist, String album, int? track, String path})>> songsToCheckForEdits() async {
    final rows = await _db
        .customSelect('SELECT id, title, artist, album, track_number, file_path FROM songs '
            'WHERE file_path IS NOT NULL AND info_edited = 0 ORDER BY id')
        .get();
    return [
      for (final r in rows)
        (
          id: r.read<int>('id'),
          title: r.read<String>('title'),
          artist: r.readNullable<String>('artist') ?? '',
          album: r.readNullable<String>('album') ?? '',
          track: r.readNullable<int>('track_number'),
          path: r.read<String>('file_path'),
        ),
    ];
  }

  /// Flags songs as edited by hand (so a backup carries their info).
  Future<int> markInfoEdited(List<int> ids) async {
    if (ids.isEmpty) return 0;
    return _db.customUpdate('UPDATE songs SET info_edited = 1 WHERE id IN (${ids.join(',')})', updates: {_db.songs});
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
    String? composer,
  }) =>
      (_db.update(_db.songs)..where((t) => t.id.equals(id))).write(SongsCompanion(
        albumArtist: albumArtist == null ? const Value.absent() : Value(albumArtist),
        genre: genre == null ? const Value.absent() : Value(genre),
        year: year == null ? const Value.absent() : Value(year),
        replayGainDb: replayGainDb == null ? const Value.absent() : Value(replayGainDb),
        albumGainDb: albumGainDb == null ? const Value.absent() : Value(albumGainDb),
        composer: composer == null ? const Value.absent() : Value(composer),
      ));

  static String? _groupColumn(String? kind) => switch (kind) {
        GroupKind.genre => 'genre',
        GroupKind.year => 'year',
        GroupKind.albumArtist => 'album_artist',
        GroupKind.composer => 'composer',
        GroupKind.audiobook => 'album',
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
    // Books have their own list; the others leave them out.
    where.write(kind == GroupKind.audiobook ? ' AND $_isBook' : ' AND $_notBook');
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
    final progress = kind == GroupKind.audiobook
        ? await bookProgress([for (final r in rows) r.read<String>('name')])
        : const <String, int>{};
    return LibraryPage(
      items: [
        for (final r in rows)
          RemoteGroup(
            name: r.read<String>('name'),
            songCount: r.read<int>('song_count'),
            percent: progress[r.read<String>('name')] ?? 0,
          ),
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
        infoEdited: const Value(true),
      ),
    );
    return rows > 0;
  }

  /// Changes the fields songs can share on every song of [ids]: the keys of [changes] are
  /// `artist`, `album`, `albumArtist`, `genre`, `year` (an int) and `composer`; a null value
  /// clears the field (an artist or album then reads "Unknown ..."). Title and track number are
  /// not here on purpose. Returns how many songs were changed.
  Future<int> updateGroupInfo(List<int> ids, Map<String, Object?> changes) async {
    if (ids.isEmpty || changes.isEmpty) return 0;
    String clip(String s) {
      final t = s.trim();
      return t.length > maxTagLength ? t.substring(0, maxTagLength) : t;
    }

    final sets = <String>[];
    final vars = <Variable<Object>>[];
    void put(String column, Object? v, {String? whenEmpty}) {
      sets.add('$column = ?');
      if (v is int) {
        vars.add(Variable<int>(v));
      } else if (v is String && clip(v).isNotEmpty) {
        vars.add(Variable<String>(clip(v)));
      } else if (whenEmpty != null) {
        vars.add(Variable<String>(whenEmpty));
      } else {
        vars.add(const Variable<String>(null));
      }
    }

    for (final e in changes.entries) {
      switch (e.key) {
        case 'artist':
          put('artist', e.value, whenEmpty: 'Unknown artist');
        case 'album':
          put('album', e.value, whenEmpty: 'Unknown album');
        case 'albumArtist':
          put('album_artist', e.value);
        case 'genre':
          put('genre', e.value);
        case 'composer':
          put('composer', e.value);
        case 'year':
          final y = e.value;
          put('year', y is int && y > 0 && y < 10000 ? y : null);
      }
    }
    if (sets.isEmpty) return 0;
    // The ids are integers we read from the database, so they are safe to write in.
    return _db.customUpdate(
      'UPDATE songs SET ${sets.join(', ')}, info_edited = 1 WHERE id IN (${ids.join(',')})',
      variables: vars,
      updates: {_db.songs},
    );
  }

  /// Remembers that [songId] just started playing.
  /// Remembers that [songId] was skipped.
  Future<void> markSkipped(int songId) => _db.customUpdate(
        'UPDATE songs SET skip_count = skip_count + 1 WHERE id = ?',
        variables: [Variable<int>(songId)],
        updates: {_db.songs},
      );

  // --------------------------------------------------------------- audiobooks

  /// The songs marked as audiobooks.
  Future<Set<int>> audiobookIds() async => {
        for (final r in await _db.customSelect('SELECT song_id FROM audiobooks').get()) r.read<int>('song_id'),
      };

  /// Which of [ids] are audiobooks.
  Future<Set<int>> audiobookIdsAmong(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    // The ids are integers from the database, so they are safe to write in.
    return {
      for (final r in await _db
          .customSelect('SELECT song_id FROM audiobooks WHERE song_id IN (${list.join(',')})')
          .get())
        r.read<int>('song_id'),
    };
  }

  /// Marks songs as audiobooks, or as music again (which forgets where they were left). Returns
  /// how many changed.
  Future<int> setAudiobook(List<int> ids, bool audiobook) async {
    if (ids.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (!audiobook) {
      return _db.customUpdate('DELETE FROM audiobooks WHERE song_id IN (${ids.join(',')})');
    }
    var changed = 0;
    for (final id in ids) {
      changed += await _db.customUpdate(
        'INSERT OR IGNORE INTO audiobooks (song_id, position_seconds, updated_at) VALUES (?, 0, ?)',
        variables: [Variable<int>(id), Variable<int>(now)],
      );
    }
    return changed;
  }

  /// Genres that mean "this is a spoken book".
  static const audiobookGenres = ['audiobook', 'audio book', 'audiobooks', 'audio books', 'spoken', 'podcast'];

  /// Marks every song whose genre says audiobook (or spoken word, podcast), or that lives in a folder
  /// whose name has "audiobook" in it. Never un-marks anything. Returns how many were marked.
  Future<int> markAudiobooksByTags() async {
    final genres = audiobookGenres.map((g) => "'$g'").join(',');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return _db.customUpdate(
      'INSERT OR IGNORE INTO audiobooks (song_id, position_seconds, updated_at) '
      'SELECT id, 0, ? FROM songs WHERE '
      "lower(IFNULL(genre, '')) IN ($genres) OR lower(IFNULL(genre, '')) LIKE '%audiobook%' "
      "OR lower(IFNULL(file_path, '')) LIKE '%audiobook%' OR lower(IFNULL(file_path, '')) LIKE '%audio book%'",
      variables: [Variable<int>(now)],
    );
  }

  /// Where an audiobook was left (seconds; 0 if never started).
  Future<int> audiobookPosition(int songId) async {
    final r = await _db
        .customSelect('SELECT position_seconds AS p FROM audiobooks WHERE song_id = ?',
            variables: [Variable<int>(songId)])
        .getSingleOrNull();
    return r?.read<int>('p') ?? 0;
  }

  /// Remembers where an audiobook was left (a song that is not an audiobook is not touched). A
  /// place after the start means it is not finished; [finished] marks it played to its end (and
  /// the next play starts from the beginning).
  Future<void> saveAudiobookPosition(int songId, int seconds, {bool finished = false}) => _db.customUpdate(
        'UPDATE audiobooks SET position_seconds = ?, finished = ?, updated_at = ? WHERE song_id = ?',
        variables: [
          Variable<int>(seconds < 0 ? 0 : seconds),
          Variable<int>(finished ? 1 : 0),
          Variable<int>(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          Variable<int>(songId),
        ],
      );

  /// How far each of [ids] is listened to, in percent (100: finished). Only audiobooks that were
  /// started appear.
  Future<Map<int, int>> audiobookProgress(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    final rows = await _db
        .customSelect('SELECT a.song_id AS id, a.position_seconds AS p, a.finished AS f, s.duration_seconds AS d '
            'FROM audiobooks a JOIN songs s ON s.id = a.song_id WHERE a.song_id IN (${list.join(',')})')
        .get();
    final out = <int, int>{};
    for (final r in rows) {
      final d = r.readNullable<int>('d') ?? 0;
      final pct = r.read<int>('f') == 1 ? 100 : (d > 0 ? (100 * r.read<int>('p') / d).round().clamp(0, 99) : 0);
      if (pct > 0) out[r.read<int>('id')] = pct;
    }
    return out;
  }

  /// How far each book (an album of audiobooks) is listened to, in percent, by book name.
  Future<Map<String, int>> bookProgress(Iterable<String> names) async {
    final list = names.toList();
    if (list.isEmpty) return {};
    final marks = List.filled(list.length, '?').join(',');
    final rows = await _db
        .customSelect(
          'SELECT s.album AS name, SUM(CASE WHEN a.finished = 1 THEN IFNULL(s.duration_seconds, 0) ELSE a.position_seconds END) AS done, '
          'SUM(IFNULL(s.duration_seconds, 0)) AS total FROM audiobooks a JOIN songs s ON s.id = a.song_id '
          'WHERE s.album IN ($marks) GROUP BY s.album',
          variables: [for (final n in list) Variable<String>(n)],
        )
        .get();
    return {
      for (final r in rows)
        if (r.read<int>('total') > 0)
          r.read<String>('name'): (100 * r.read<int>('done') / r.read<int>('total')).round().clamp(0, 100),
    };
  }

  /// The playback speed kept for the book this song belongs to (null: none was set).
  Future<double?> bookSpeed(int songId) async {
    final r = await _db
        .customSelect(
          'SELECT a.speed AS v FROM audiobooks a WHERE a.song_id IN (SELECT id FROM songs WHERE '
          "lower(IFNULL(artist, '')) = (SELECT lower(IFNULL(artist, '')) FROM songs WHERE id = ?) AND "
          "lower(IFNULL(album, '')) = (SELECT lower(IFNULL(album, '')) FROM songs WHERE id = ?)) "
          'AND a.speed IS NOT NULL ORDER BY a.updated_at DESC LIMIT 1',
          variables: [Variable<int>(songId), Variable<int>(songId)],
        )
        .getSingleOrNull();
    return r?.read<double>('v');
  }

  /// Keeps a playback speed for the whole book (every chapter with the same artist and album).
  Future<void> setBookSpeed(int songId, double speed) => _db.customUpdate(
        'UPDATE audiobooks SET speed = ? WHERE song_id IN (SELECT id FROM songs WHERE '
        "lower(IFNULL(artist, '')) = (SELECT lower(IFNULL(artist, '')) FROM songs WHERE id = ?) AND "
        "lower(IFNULL(album, '')) = (SELECT lower(IFNULL(album, '')) FROM songs WHERE id = ?))",
        variables: [Variable<double>(speed), Variable<int>(songId), Variable<int>(songId)],
      );

  /// Remembers which song of a list was playing last.
  Future<void> saveListPosition(String key, int songId) => _db.customInsert(
        'INSERT OR REPLACE INTO list_positions (list_key, song_id, updated_at) VALUES (?, ?, ?)',
        variables: [
          Variable<String>(key),
          Variable<int>(songId),
          Variable<int>(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        ],
      );

  /// The song a list was left at (null: never played).
  Future<int?> listPosition(String key) async {
    final r = await _db
        .customSelect('SELECT song_id FROM list_positions WHERE list_key = ?', variables: [Variable<String>(key)])
        .getSingleOrNull();
    return r?.read<int>('song_id');
  }

  /// Writes one row of the play log: [songId] started at [startedAt], was heard for
  /// [heardSeconds], and ended as [outcome] (`finished`, `skipped` or `stopped`).
  Future<void> recordPlayEvent(int songId, DateTime startedAt, int heardSeconds, String outcome) =>
      _db.customInsert(
        'INSERT INTO play_events (song_id, started_at, heard_seconds, outcome) VALUES (?, ?, ?, ?)',
        variables: [
          Variable<int>(songId),
          Variable<int>(startedAt.millisecondsSinceEpoch ~/ 1000),
          Variable<int>(heardSeconds < 0 ? 0 : heardSeconds),
          Variable<String>(outcome),
        ],
      );

  /// How many plays are in the log.
  Future<int> playEventCount() async =>
      (await _db.customSelect('SELECT COUNT(*) AS c FROM play_events').getSingle()).read<int>('c');

  /// Empties the play log. Returns how many rows went.
  Future<int> clearPlayEvents() => _db.customUpdate('DELETE FROM play_events');

  /// Sets every play and skip count back to zero (and forgets when songs were
  /// last played). Returns how many songs had something.
  Future<int> resetListeningStats() => _db.customUpdate(
        'UPDATE songs SET play_count = 0, skip_count = 0, last_played_at = NULL '
        'WHERE play_count > 0 OR skip_count > 0 OR last_played_at IS NOT NULL',
        updates: {_db.songs},
      );

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

  /// Songs that are the same as this one (same tags, length and file size), with where
  /// each one's file is, so a moved file can be told from a real second copy.
  Future<List<({int id, String? path})>> duplicatesOf({
    required String title,
    required String artist,
    required String album,
    int? durationSeconds,
    int? fileSizeBytes,
  }) async {
    final rows = await _db.customSelect(
      'SELECT id, file_path FROM songs WHERE title = ? AND artist = ? AND album = ? '
      'AND IFNULL(duration_seconds, -1) = ? AND IFNULL(file_size_bytes, -1) = ? ORDER BY id',
      variables: [
        Variable<String>(title),
        Variable<String>(artist),
        Variable<String>(album),
        Variable<int>(durationSeconds ?? -1),
        Variable<int>(fileSizeBytes ?? -1),
      ],
    ).get();
    return [for (final r in rows) (id: r.read<int>('id'), path: r.readNullable<String>('file_path'))];
  }

  /// Points a song at its file's new place (it was moved). Its playlists, hearts and
  /// counts stay, because it is the same song record.
  Future<void> relinkSong(int songId, String newPath) => _db.customUpdate(
        'UPDATE songs SET file_path = ? WHERE id = ?',
        variables: [Variable<String>(newPath), Variable<int>(songId)],
        updates: {_db.songs},
      );

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

  /// Every song with a file and a picture.
  Future<List<({int id, String path, String album, String art})>> songsWithArt() async {
    final rows = await _db.customSelect(
      'SELECT id, file_path AS f, album, album_art_path AS p FROM songs '
      "WHERE file_path IS NOT NULL AND album_art_path IS NOT NULL AND album_art_path != ''",
    ).get();
    return [
      for (final r in rows)
        (id: r.read<int>('id'), path: r.read<String>('f'), album: r.readNullable<String>('album') ?? '', art: r.read<String>('p')),
    ];
  }

  /// Sets (or, with null, takes away) one song's picture.
  Future<void> setSongArt(int songId, String? path) => _db.customUpdate(
        'UPDATE songs SET album_art_path = ? WHERE id = ?',
        variables: [Variable<String>(path), Variable<int>(songId)],
        updates: {_db.songs},
      );

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

  static const _isBook = 'id IN (SELECT song_id FROM audiobooks)';
  static const _notBook = 'id NOT IN (SELECT song_id FROM audiobooks)';

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
    // Audiobooks are apart from the music: only their own list and a playlist or folder show them.
    if (groupKind == GroupKind.audiobook) {
      clauses.add(_isBook);
    } else if (playlistId == null && onlyIds == null) {
      clauses.add(_notBook);
    }
    if (groupCol != null && groupValue != null) {
      clauses.add('CAST($groupCol AS TEXT) = ?');
      vars.add(Variable<String>(groupValue));
    }
    if (view == LibraryView.favorites) clauses.add('favorite = 1');
    if (view == LibraryView.recent) clauses.add('last_played_at IS NOT NULL');
    if (view == LibraryView.skipped) {
      clauses.add('id IN (SELECT id FROM songs WHERE skip_count > 0 '
          'ORDER BY skip_count DESC, id LIMIT $autoListSize)');
    }
    if (view == LibraryView.never) {
      clauses.add('play_count = 0 AND last_played_at IS NULL');
    }
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

  String _songOrder({String? artist, String? album, String? view, int? playlistId, String? groupKind}) {
    if (groupKind == GroupKind.audiobook) {
      return 'ORDER BY COALESCE(track_number, 9999), title COLLATE NOCASE, id';
    }
    if (view == LibraryView.recent) return 'ORDER BY last_played_at DESC, id';
    if (view == LibraryView.top) return 'ORDER BY play_count DESC, last_played_at DESC, id';
    if (view == LibraryView.skipped) return 'ORDER BY skip_count DESC, play_count DESC, id';
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
    final totals = await _db
        .customSelect('SELECT COUNT(*) AS c, IFNULL(SUM(duration_seconds), 0) AS d FROM songs ${f.where}',
            variables: f.vars)
        .getSingle();
    final total = totals.read<int>('c');
    final rows = await _db.customSelect(
      'SELECT * FROM songs ${f.where} ${_songOrder(artist: artist, album: album, view: view, playlistId: playlistId, groupKind: groupKind)} '
      'LIMIT ? OFFSET ?',
      variables: [...f.vars, Variable<int>(limit), Variable<int>(offset)],
    ).get();
    return LibraryPage(
      items: [for (final r in rows) _db.songs.map(r.data)],
      total: total,
      offset: offset,
      totalSeconds: totals.read<int>('d'),
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

  /// Every folder that holds music or is above one, as a tree: the songs under
  /// each, and which folder is the top (where the paths first branch).
  Future<({String root, Map<String, int> total, Map<int, String> byId})> _tree() async {
    final rows = await _db
        .customSelect('SELECT file_path FROM songs WHERE file_path IS NOT NULL')
        .get();
    final direct = <String, int>{};
    for (final r in rows) {
      final d = _dirOf(r.read<String>('file_path'));
      direct[d] = (direct[d] ?? 0) + 1;
    }
    final total = <String, int>{};
    final byId = <int, String>{};
    List<String>? common;
    for (final e in direct.entries) {
      final parts = e.key.split('/').where((p) => p.isNotEmpty).toList();
      common = common == null
          ? [...parts]
          : [
              for (var i = 0; i < common.length && i < parts.length && common[i] == parts[i]; i++)
                common[i]
            ];
      var path = '';
      total['/'] = (total['/'] ?? 0) + e.value;
      byId[folderIdOf('/')] = '/';
      for (final p in parts) {
        path = '$path/$p';
        total[path] = (total[path] ?? 0) + e.value;
        byId[folderIdOf(path)] = path;
      }
    }
    final root = (common == null || common.isEmpty) ? '/' : '/${common.join('/')}';
    return (root: root, total: total, byId: byId);
  }

  static String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  /// The top folder of the tree (null when there is no music from files).
  Future<RemoteFolder?> folderRoot() async {
    final t = await _tree();
    final n = t.total[t.root];
    if (n == null) return null;
    return RemoteFolder(
      id: folderIdOf(t.root),
      name: _lastPart(t.root),
      parent: t.root == '/' ? '' : _lastPart(_parentOf(t.root)),
      songCount: n,
      hasChildren: t.total.keys.any((p) => p != t.root && _parentOf(p) == t.root),
    );
  }

  /// The folders inside one folder ([parentId]; null: the top folder), each with
  /// the songs under it.
  Future<LibraryPage<RemoteFolder>> folderChildren({
    int? parentId,
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final t = await _tree();
    final parentPath = parentId == null ? t.root : t.byId[parentId];
    if (parentPath == null) return LibraryPage(items: const [], total: 0, offset: offset);
    final q = query.trim().toLowerCase();
    final children = [
      for (final p in t.total.keys)
        if (p != parentPath && p != '/' && _parentOf(p) == parentPath)
          if (q.isEmpty || _lastPart(p).toLowerCase().contains(q))
            RemoteFolder(
              id: folderIdOf(p),
              name: _lastPart(p),
              parent: _lastPart(parentPath),
              songCount: t.total[p]!,
              hasChildren: t.total.keys.any((c) => c != p && _parentOf(c) == p),
            ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final end = (offset + limit) > children.length ? children.length : offset + limit;
    return LibraryPage(
      items: offset >= children.length ? const [] : children.sublist(offset, end),
      total: children.length,
      offset: offset,
    );
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
    final where = q.isEmpty ? 'WHERE $_notBook' : "WHERE $_notBook AND artist LIKE ? ESCAPE '\\'";
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
    final clauses = <String>[_notBook];
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

  RemoteSong toRemote({required bool available, bool audiobook = false, int progress = 0}) => RemoteSong(
        audiobook: audiobook,
        progress: progress,
        id: id,
        title: title,
        artist: artist ?? unknownArtist,
        album: album ?? unknownAlbum,
        durationSeconds: durationSeconds ?? 0,
        trackNumber: trackNumber,
        available: available,
        favorite: favorite,
        plays: playCount,
        skips: skipCount,
      );
}
