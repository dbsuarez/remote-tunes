import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../data/database/app_database.dart';
import '../../data/repositories/library_repository.dart';
import '../library/lookup_models.dart';
import '../library/tag_writer.dart';
import 'tag_cleanup.dart';

/// What applying a batch of changes did.
class ApplyResult {
  const ApplyResult({
    this.batchId = 0,
    this.applied = 0,
    this.written = 0,
    this.notAllowed = 0,
    this.failed = 0,
  });

  /// The number to undo it by (0: nothing was changed).
  final int batchId;
  final int applied;

  /// Songs whose music file was changed too, refused by Android, or not writable.
  final int written;
  final int notAllowed;
  final int failed;
}

typedef TagProgress = void Function(int done, int total, String? current);

/// Tag cleanup: finds what is missing, proposes fixes (from file names, and from MusicBrainz by
/// title and artist), applies the ones the user approves (in the library and, if wanted, in the
/// files) and can undo the last batch. It only ever fills empty fields; it never replaces a tag
/// that is there, and never does anything without being asked.
class TagCleanupService {
  TagCleanupService({
    required this.db,
    required this.library,
    this.writer = const TagWriter(),
  });

  final AppDatabase db;
  final LibraryRepository library;
  final TagWriter writer;

  /// Music only: audiobooks are not part of the cleanup.
  static const _music = 'file_path IS NOT NULL AND id NOT IN (SELECT song_id FROM audiobooks)';
  static const _artistUnknown = "(artist IS NULL OR artist = '' OR lower(artist) LIKE 'unknown%')";
  static const _albumUnknown = "(album IS NULL OR album = '' OR lower(album) LIKE 'unknown%')";

  static bool _isUnknown(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    return t.isEmpty || t.startsWith('unknown');
  }

  Future<int> _count(String where, [String from = 'songs']) async =>
      (await db.customSelect('SELECT COUNT(*) AS c FROM $from WHERE $where').getSingle()).read<int>('c');

  // ------------------------------------------------------------------- report

  Future<TagCleanupReport> report() async {
    final songs = await _count(_music);
    final batch = await db
        .customSelect('SELECT batch, COUNT(*) AS n, MAX(applied_at) AS at FROM tag_changes '
            'GROUP BY batch ORDER BY batch DESC LIMIT 1')
        .getSingleOrNull();
    return TagCleanupReport(
      songs: songs,
      complete: await _count('$_music AND NOT $_artistUnknown AND NOT $_albumUnknown'),
      noArtist: await _count('$_music AND $_artistUnknown'),
      noAlbum: await _count('$_music AND $_albumUnknown'),
      noGenre: await _count("$_music AND (genre IS NULL OR genre = '')"),
      noYear: await _count('$_music AND year IS NULL'),
      noCover: await _count("$_music AND (album_art_path IS NULL OR album_art_path = '')"),
      fromFileNames: (await fileNameChanges()).length,
      pendingSuggestions: (await suggestionChanges()).length,
      noMatch: await _count("status = 'nomatch'", 'tag_suggestions'),
      lastBatch: batch == null
          ? null
          : (
              id: batch.read<int>('batch'),
              songs: batch.read<int>('n'),
              at: DateTime.fromMillisecondsSinceEpoch(batch.read<int>('at') * 1000),
            ),
    );
  }

  // ---------------------------------------------------------------- file names

  /// What the file names can fill in: a title that is only the file name, an unknown artist, a
  /// missing track number.
  Future<List<TagChange>> fileNameChanges() async {
    final rows = await db
        .customSelect('SELECT id, title, artist, album, track_number, year, file_path FROM songs WHERE $_music ORDER BY id')
        .get();
    final out = <TagChange>[];
    for (final r in rows) {
      final title = r.read<String>('title');
      final artist = r.readNullable<String>('artist');
      final track = r.readNullable<int>('track_number');
      final guess = parseFileName(p.basenameWithoutExtension(r.read<String>('file_path')));
      if (guess == null) continue;

      final titleIsFileName = sameName(title, p.basenameWithoutExtension(r.read<String>('file_path')));
      final newTitle = titleIsFileName && guess.title != title ? guess.title : null;
      // The artist only when the title agrees with the file name (so a tagged title that says
      // something else is not trusted to belong to this file name).
      final newArtist = _isUnknown(artist) &&
              guess.artist != null &&
              guess.artist!.isNotEmpty &&
              (titleIsFileName || sameName(title, guess.title))
          ? guess.artist
          : null;
      final newTrack = track == null && guess.track != null && guess.track! > 0 ? guess.track : null;
      if (newTitle == null && newArtist == null && newTrack == null) continue;
      out.add(TagChange(
        songId: r.read<int>('id'),
        label: _label(title, artist),
        source: 'filename',
        title: newTitle,
        artist: newArtist,
        track: newTrack,
        was: {'title': title, 'artist': artist, 'track': track},
      ));
    }
    return out;
  }

  static String _label(String title, String? artist) => _isUnknown(artist) ? title : '$title - $artist';

  // -------------------------------------------------------------------- apply

  /// Applies [changes] to the library and, with [writeToFile], to the music files. Everything
  /// changed is logged so [undoLast] can put it back.
  Future<ApplyResult> apply(
    List<TagChange> changes, {
    bool writeToFile = false,
    TagProgress? onProgress,
  }) async {
    final todo = [for (final c in changes) if (!c.isEmpty) c];
    if (todo.isEmpty) return const ApplyResult();
    final last = await db.customSelect('SELECT IFNULL(MAX(batch), 0) AS b FROM tag_changes').getSingle();
    final batch = last.read<int>('b') + 1;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var applied = 0, written = 0, notAllowed = 0, failed = 0;
    for (var i = 0; i < todo.length; i++) {
      final c = todo[i];
      onProgress?.call(i, todo.length, c.label);
      final row = await db
          .customSelect('SELECT title, artist, album, track_number, year, file_path FROM songs WHERE id = ?',
              variables: [Variable<int>(c.songId)])
          .getSingleOrNull();
      if (row == null) continue;
      final old = <String, Object?>{
        'title': row.read<String>('title'),
        'artist': row.readNullable<String>('artist'),
        'album': row.readNullable<String>('album'),
        'track': row.readNullable<int>('track_number'),
        'year': row.readNullable<int>('year'),
      };
      final title = c.title ?? old['title'] as String;
      final artist = c.artist ?? (old['artist'] as String?) ?? unknownArtist;
      final album = c.album ?? (old['album'] as String?) ?? unknownAlbum;
      final track = c.track ?? old['track'] as int?;
      final ok = await library.updateSongInfo(c.songId, title: title, artist: artist, album: album, trackNumber: track);
      if (!ok) continue;
      if (c.year != null) await library.updateGroupInfo([c.songId], {'year': c.year});
      applied++;
      var wrote = false;
      final path = row.readNullable<String>('file_path');
      if (writeToFile && path != null) {
        var result = writer.write(path, title: title, artist: artist, album: album, trackNumber: track);
        if (result == TagWriteResult.written && c.year != null) {
          result = writer.writeGroup(path, {'year': c.year});
        }
        switch (result) {
          case TagWriteResult.written:
            written++;
            wrote = true;
          case TagWriteResult.notAllowed:
            notAllowed++;
          default:
            failed++;
        }
      }
      await db.customInsert(
        'INSERT INTO tag_changes (batch, song_id, old_json, wrote_file, applied_at) VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable<int>(batch),
          Variable<int>(c.songId),
          Variable<String>(jsonEncode(old)),
          Variable<int>(wrote ? 1 : 0),
          Variable<int>(now),
        ],
      );
      if (c.source == 'musicbrainz') await markSuggestions([c.songId], 'applied');
    }
    onProgress?.call(todo.length, todo.length, null);
    return ApplyResult(batchId: applied == 0 ? 0 : batch, applied: applied, written: written, notAllowed: notAllowed, failed: failed);
  }

  /// Puts the newest batch back as it was (in the library, and in the files that were changed).
  /// Null when there is nothing to undo.
  Future<ApplyResult?> undoLast() async {
    final b = await db.customSelect('SELECT MAX(batch) AS b FROM tag_changes').getSingle();
    final batch = b.readNullable<int>('b');
    if (batch == null) return null;
    final rows = await db
        .customSelect('SELECT song_id, old_json, wrote_file FROM tag_changes WHERE batch = ? ORDER BY id DESC',
            variables: [Variable<int>(batch)])
        .get();
    var restored = 0, written = 0, failed = 0, notAllowed = 0;
    for (final r in rows) {
      final id = r.read<int>('song_id');
      final Map<String, dynamic> old;
      try {
        old = jsonDecode(r.read<String>('old_json')) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final title = old['title'] as String? ?? '';
      if (title.isEmpty) continue;
      final artist = old['artist'] as String? ?? unknownArtist;
      final album = old['album'] as String? ?? unknownAlbum;
      final track = old['track'] as int?;
      if (!await library.updateSongInfo(id, title: title, artist: artist, album: album, trackNumber: track)) continue;
      await library.updateGroupInfo([id], {'year': old['year']});
      restored++;
      if (r.read<int>('wrote_file') == 1) {
        final path = (await library.songById(id))?.filePath;
        if (path != null) {
          var result = writer.write(path, title: title, artist: artist, album: album, trackNumber: track);
          if (result == TagWriteResult.written) result = writer.writeGroup(path, {'year': old['year']});
          switch (result) {
            case TagWriteResult.written:
              written++;
            case TagWriteResult.notAllowed:
              notAllowed++;
            default:
              failed++;
          }
        }
      }
      // A suggestion that was applied can be offered again.
      await db.customUpdate("UPDATE tag_suggestions SET status = 'new' WHERE song_id = ? AND status = 'applied'",
          variables: [Variable<int>(id)]);
    }
    await db.customUpdate('DELETE FROM tag_changes WHERE batch = ?', variables: [Variable<int>(batch)]);
    return ApplyResult(batchId: batch, applied: restored, written: written, notAllowed: notAllowed, failed: failed);
  }

  // -------------------------------------------------------------- suggestions

  /// Asks MusicBrainz (by title and artist, one song a second) about the songs that lack an album
  /// or a year, and keeps what it finds for review. Songs already asked about are skipped, so it
  /// can be stopped and carried on. Returns how many songs were asked about this time. A busy or
  /// unreachable MusicBrainz stops it with the [LookupException]; what was found is kept.
  Future<int> findSuggestions(
    SongLookupService lookup, {
    TagProgress? onProgress,
    bool Function()? cancelled,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT id, title, artist, album, year, track_number, duration_seconds FROM songs '
          'WHERE $_music AND ($_albumUnknown OR year IS NULL) '
          'AND id NOT IN (SELECT song_id FROM tag_suggestions) ORDER BY id',
        )
        .get();
    var asked = 0;
    for (var i = 0; i < rows.length; i++) {
      if (cancelled?.call() ?? false) break;
      final r = rows[i];
      final title = r.read<String>('title');
      final artist = r.readNullable<String>('artist');
      final album = r.readNullable<String>('album');
      onProgress?.call(i, rows.length, _label(title, artist));
      final duration = r.readNullable<int>('duration_seconds') ?? 0;
      final matches = await lookup.search(
        title: title,
        artist: artist ?? '',
        album: album ?? '',
        durationSeconds: duration,
      );
      asked++;
      final m = matches.isEmpty ? null : matches.first;
      final year = r.readNullable<int>('year');
      final track = r.readNullable<int>('track_number');
      final newAlbum = m != null && _isUnknown(album) && m.album.isNotEmpty ? m.album : null;
      final newYear = m != null && year == null ? m.year : null;
      final newTrack = m != null && track == null ? m.trackNumber : null;
      final newArtist = m != null && _isUnknown(artist) && m.artist.isNotEmpty ? m.artist : null;
      final nothing = newAlbum == null && newYear == null && newTrack == null && newArtist == null;
      // A sure match: the same title, the same artist (or none yet), about the same length.
      final high = m != null &&
          !nothing &&
          sameName(m.title, title) &&
          (_isUnknown(artist) || sameName(m.artist, artist!)) &&
          duration > 0 &&
          m.lengthSeconds != null &&
          (m.lengthSeconds! - duration).abs() <= 3 &&
          m.score >= 90;
      await db.customInsert(
        'INSERT OR REPLACE INTO tag_suggestions (song_id, artist, album, year, track, score, high, status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<int>(r.read<int>('id')),
          Variable<String>(newArtist),
          Variable<String>(newAlbum),
          Variable<int>(newYear),
          Variable<int>(newTrack),
          Variable<int>(m?.score ?? 0),
          Variable<int>(high ? 1 : 0),
          Variable<String>(nothing ? 'nomatch' : 'new'),
        ],
      );
    }
    onProgress?.call(rows.length, rows.length, null);
    return asked;
  }

  /// The suggestions waiting for a decision.
  Future<List<TagChange>> suggestionChanges() async {
    final rows = await db
        .customSelect(
          'SELECT g.song_id, g.artist AS n_artist, g.album AS n_album, g.year AS n_year, g.track AS n_track, '
          'g.high, s.title, s.artist, s.album, s.year, s.track_number FROM tag_suggestions g '
          "JOIN songs s ON s.id = g.song_id WHERE g.status = 'new' ORDER BY g.high DESC, s.title COLLATE NOCASE",
        )
        .get();
    return [
      for (final r in rows)
        TagChange(
          songId: r.read<int>('song_id'),
          label: _label(r.read<String>('title'), r.readNullable<String>('artist')),
          source: 'musicbrainz',
          artist: r.readNullable<String>('n_artist'),
          album: r.readNullable<String>('n_album'),
          year: r.readNullable<int>('n_year'),
          track: r.readNullable<int>('n_track'),
          high: r.read<int>('high') == 1,
          was: {
            'artist': r.readNullable<String>('artist'),
            'album': r.readNullable<String>('album'),
            'year': r.readNullable<int>('year'),
            'track': r.readNullable<int>('track_number'),
          },
        ),
    ];
  }

  /// Sets what became of suggestions: `applied`, `skipped` (not offered again) or `new`.
  Future<void> markSuggestions(Iterable<int> songIds, String status) async {
    final ids = songIds.toList();
    if (ids.isEmpty) return;
    await db.customUpdate('UPDATE tag_suggestions SET status = ? WHERE song_id IN (${ids.join(',')})',
        variables: [Variable<String>(status)]);
  }

  /// Forgets what was found, so the next search asks about every song again.
  Future<int> clearSuggestions() => db.customUpdate('DELETE FROM tag_suggestions');
}
