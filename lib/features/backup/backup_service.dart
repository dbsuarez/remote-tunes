import 'package:drift/drift.dart';
import 'package:path/path.dart' as pp;

import '../../data/database/app_database.dart';
import '../../data/repositories/settings_repository.dart';
import '../library/import_service.dart' show ExclusionStore;
import 'backup_models.dart';

/// How a song of the backup was found in this phone's library.
enum SongMatch { path, tags, loose, notFound }

/// What a restore did.
class RestoreReport {
  int songsInBackup = 0;
  int byPath = 0;
  int byTags = 0;
  int looseMatches = 0;
  final List<String> notFound = [];

  int playlistsCreated = 0;
  int playlistsMerged = 0;
  int playlistSongsAdded = 0;
  int favoritesSet = 0;
  int countsRestored = 0;
  int leftOutAdded = 0;
  int lyricsAdded = 0;
  int settingsApplied = 0;

  int get found => byPath + byTags + looseMatches;
}

/// Makes a backup of what is in the library besides the music itself, and puts one
/// back, possibly on another phone.
///
/// A song is not found by its database number (that differs on every phone) but by
/// where it was below the music root, and failing that by its title, artist,
/// album and length.
class BackupService {
  BackupService({
    required this.db,
    required this.settings,
    required this.exclusions,
    required this.copiedSongsDir,
  });

  final AppDatabase db;
  final SettingsRepository settings;
  final ExclusionStore exclusions;

  /// Songs added with "Add songs" are copies kept here: they have no usable path.
  final String copiedSongsDir;

  static final _p = pp.posix;

  /// The settings that make sense on another phone. Secrets, pairing, the device
  /// name and the like are not here and are never read back.
  static const _settingKeys = {
    SettingKeys.defaultVolume,
    SettingKeys.repeatMode,
    SettingKeys.shuffleEnabled,
    SettingKeys.songListSize,
    SettingKeys.hapticsEnabled,
    SettingKeys.accentFromArt,
    SettingKeys.lyricsEnabled,
    SettingKeys.startMode,
    SettingKeys.replayGainMode,
    SettingKeys.crossfadeSeconds,
    SettingKeys.skinId,
    SettingKeys.customSkins,
    SettingKeys.queueScrollToCurrent,
    SettingKeys.visualizer,
    SettingKeys.visualizerStyle,
    SettingKeys.onlineSuggestions,
  };

  static bool isBackedUpSetting(String key) => _settingKeys.contains(key) || key.startsWith('eq_');

  // ------------------------------------------------------------------ backup

  /// The folder that holds every song file (the deepest one that does).
  static String commonDir(List<String> paths) {
    if (paths.isEmpty) return '';
    var common = _p.split(_p.dirname(paths.first));
    for (final path in paths.skip(1)) {
      final parts = _p.split(_p.dirname(path));
      var i = 0;
      while (i < common.length && i < parts.length && common[i] == parts[i]) {
        i++;
      }
      common = common.sublist(0, i);
    }
    return common.isEmpty ? '/' : _p.joinAll(common);
  }

  bool _isCopy(String path) => copiedSongsDir.isNotEmpty && _p.isWithin(copiedSongsDir, path);

  Future<BackupData> create({bool lyrics = true, bool settings = true}) async {
    final rows = await db.customSelect(
      'SELECT id, title, artist, album, duration_seconds, file_path, file_size_bytes, favorite, '
      'play_count, skip_count, last_played_at FROM songs ORDER BY id',
    ).get();
    final inPlaylist = {
      for (final r in await db.customSelect('SELECT DISTINCT song_id FROM playlist_songs').get())
        r.read<int>('song_id'),
    };

    // Only songs that have something worth keeping: a playlist, a heart, plays or skips.
    final chosen = <QueryRow>[];
    for (final r in rows) {
      if (inPlaylist.contains(r.read<int>('id')) ||
          r.read<bool>('favorite') ||
          r.read<int>('play_count') > 0 ||
          r.read<int>('skip_count') > 0 ||
          r.readNullable<DateTime>('last_played_at') != null) {
        chosen.add(r);
      }
    }

    // The music root: the folder every referenced file is in (copies are not).
    final referenced = [
      for (final r in rows)
        if (r.readNullable<String>('file_path') != null && !_isCopy(r.read<String>('file_path')))
          r.read<String>('file_path'),
    ];
    final root = commonDir(referenced);

    String? relative(String? path) {
      if (path == null || _isCopy(path) || root.isEmpty) return null;
      return _p.isWithin(root, path) ? _p.relative(path, from: root) : null;
    }

    final songs = <BackupSong>[];
    final indexOfDbId = <int, int>{};
    for (final r in chosen) {
      indexOfDbId[r.read<int>('id')] = songs.length;
      songs.add(BackupSong(
        title: r.read<String>('title'),
        artist: r.readNullable<String>('artist') ?? '',
        album: r.readNullable<String>('album') ?? '',
        durationSeconds: r.readNullable<int>('duration_seconds') ?? 0,
        relativePath: relative(r.readNullable<String>('file_path')),
        sizeBytes: r.readNullable<int>('file_size_bytes'),
        favorite: r.read<bool>('favorite'),
        plays: r.read<int>('play_count'),
        skips: r.read<int>('skip_count'),
        lastPlayed: r.readNullable<DateTime>('last_played_at'),
      ));
    }

    final playlists = <BackupPlaylist>[];
    for (final pl in await db.customSelect('SELECT id, name FROM playlists ORDER BY id').get()) {
      final members = await db.customSelect(
        'SELECT song_id FROM playlist_songs WHERE playlist_id = ? ORDER BY position, id',
        variables: [Variable<int>(pl.read<int>('id'))],
      ).get();
      playlists.add(BackupPlaylist(pl.read<String>('name'), [
        for (final m in members)
          if (indexOfDbId[m.read<int>('song_id')] != null) indexOfDbId[m.read<int>('song_id')]!,
      ]));
    }

    final leftRel = <String>[];
    final leftAbs = <String>[];
    for (final path in await exclusions.load()) {
      if (root.isNotEmpty && (path == root || _p.isWithin(root, path))) {
        leftRel.add(path == root ? '' : _p.relative(path, from: root));
      } else {
        leftAbs.add(path);
      }
    }
    leftRel.removeWhere((e) => e.isEmpty); // the whole root left out makes no sense elsewhere

    final lyricRows = lyrics
        ? await db.customSelect(
            'SELECT track_key, plain_lyrics, synced_lyrics, instrumental, source '
            'FROM lyrics_cache WHERE found = 1',
          ).get()
        : const <QueryRow>[];

    final values = <String, String>{};
    if (settings) {
      for (final s in await db.select(db.settings).get()) {
        if (isBackedUpSetting(s.key)) values[s.key] = s.value;
      }
    }

    return BackupData(
      created: DateTime.now(),
      root: root,
      songs: songs,
      playlists: playlists,
      leftOutRelative: leftRel..sort(),
      leftOutAbsolute: leftAbs..sort(),
      lyrics: [
        for (final l in lyricRows)
          BackupLyric(
            trackKey: l.read<String>('track_key'),
            plain: l.readNullable<String>('plain_lyrics') ?? '',
            synced: l.readNullable<String>('synced_lyrics') ?? '',
            instrumental: l.read<bool>('instrumental'),
            source: l.read<String>('source'),
          ),
      ],
      settings: values,
    );
  }

  // ----------------------------------------------------------------- restore

  /// Finds each song of [data] in this library. [newRoot] is where the music root
  /// is on this phone (null: it is where it was).
  Future<List<({int? id, SongMatch how})>> match(BackupData data, {String? newRoot}) async {
    final rows = await db.customSelect(
      'SELECT id, title, artist, album, duration_seconds, file_path FROM songs',
    ).get();
    final byPath = <String, int>{};
    final byTags = <String, List<int>>{};
    final byTitleArtist = <String, List<int>>{};
    for (final r in rows) {
      final id = r.read<int>('id');
      final path = r.readNullable<String>('file_path');
      if (path != null) byPath[path] = id;
      final song = BackupSong(
        title: r.read<String>('title'),
        artist: r.readNullable<String>('artist') ?? '',
        album: r.readNullable<String>('album') ?? '',
        durationSeconds: r.readNullable<int>('duration_seconds') ?? 0,
      );
      byTags.putIfAbsent(song.keyFor(song.durationSeconds), () => []).add(id);
      byTitleArtist.putIfAbsent(song.titleArtistKey, () => []).add(id);
    }

    final out = <({int? id, SongMatch how})>[];
    for (final s in data.songs) {
      final rel = s.relativePath;
      int? id;
      if (rel != null) {
        if (newRoot != null && newRoot.isNotEmpty) id = byPath[_p.join(newRoot, rel)];
        if (id == null && data.root.isNotEmpty) id = byPath[_p.join(data.root, rel)];
      }
      if (id != null) {
        out.add((id: id, how: SongMatch.path));
        continue;
      }
      // The same song under another name or folder: tags, allowing a second either way.
      for (final d in [s.durationSeconds, s.durationSeconds - 1, s.durationSeconds + 1]) {
        final hit = byTags[s.keyFor(d)];
        if (hit != null && hit.isNotEmpty) {
          id = hit.first;
          break;
        }
      }
      if (id != null) {
        out.add((id: id, how: SongMatch.tags));
        continue;
      }
      // Last: the title and artist, only when exactly one song has them.
      final loose = byTitleArtist[s.titleArtistKey];
      if (loose != null && loose.length == 1) {
        out.add((id: loose.first, how: SongMatch.loose));
        continue;
      }
      out.add((id: null, how: SongMatch.notFound));
    }
    return out;
  }

  /// Puts [data] into this library. It only adds and merges: nothing is removed, a
  /// playlist with the same name gets the missing songs, counts keep the larger number.
  Future<RestoreReport> restore(
    BackupData data, {
    String? newRoot,
    bool includeLyrics = true,
    bool includeSettings = true,
  }) async {
    final report = RestoreReport()..songsInBackup = data.songs.length;
    final matches = await match(data, newRoot: newRoot);
    final idOf = <int, int?>{};
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      idOf[i] = m.id;
      switch (m.how) {
        case SongMatch.path:
          report.byPath++;
        case SongMatch.tags:
          report.byTags++;
        case SongMatch.loose:
          report.looseMatches++;
        case SongMatch.notFound:
          final s = data.songs[i];
          report.notFound.add(s.artist.isEmpty ? s.title : '${s.title} (${s.artist})');
      }
    }

    // Hearts and counts.
    for (var i = 0; i < data.songs.length; i++) {
      final id = idOf[i];
      final s = data.songs[i];
      if (id == null) continue;
      if (s.favorite) {
        report.favoritesSet += await db.customUpdate(
          'UPDATE songs SET favorite = 1 WHERE id = ? AND favorite = 0',
          variables: [Variable<int>(id)],
          updates: {db.songs},
        );
      }
      if (s.plays > 0 || s.skips > 0 || s.lastPlayed != null) {
        final last = s.lastPlayed;
        await db.customUpdate(
          'UPDATE songs SET play_count = MAX(play_count, ?), skip_count = MAX(skip_count, ?), '
          'last_played_at = CASE WHEN ? IS NULL THEN last_played_at '
          'WHEN last_played_at IS NULL OR last_played_at < ? THEN ? ELSE last_played_at END '
          'WHERE id = ?',
          variables: [
            Variable<int>(s.plays),
            Variable<int>(s.skips),
            Variable<DateTime>(last),
            Variable<DateTime>(last),
            Variable<DateTime>(last),
            Variable<int>(id),
          ],
          updates: {db.songs},
        );
        report.countsRestored++;
      }
    }

    // Playlists: made, or merged into one of the same name.
    for (final pl in data.playlists) {
      final ids = <int>[
        for (final i in pl.songIndexes)
          if (idOf[i] != null) idOf[i]!,
      ];
      final existing = await db.customSelect(
        'SELECT id FROM playlists WHERE lower(name) = lower(?) LIMIT 1',
        variables: [Variable<String>(pl.name)],
      ).get();
      int listId;
      if (existing.isEmpty) {
        listId = await db.into(db.playlists).insert(PlaylistsCompanion.insert(name: pl.name));
        report.playlistsCreated++;
      } else {
        listId = existing.first.read<int>('id');
        report.playlistsMerged++;
      }
      final have = {
        for (final r in await db.customSelect(
          'SELECT song_id FROM playlist_songs WHERE playlist_id = ?',
          variables: [Variable<int>(listId)],
        ).get())
          r.read<int>('song_id'),
      };
      final maxRow = await db.customSelect(
        'SELECT COALESCE(MAX(position), -1) AS m FROM playlist_songs WHERE playlist_id = ?',
        variables: [Variable<int>(listId)],
      ).getSingle();
      var pos = maxRow.read<int>('m') + 1;
      for (final songId in ids) {
        if (!have.add(songId)) continue;
        await db.into(db.playlistSongs).insert(
            PlaylistSongsCompanion.insert(playlistId: listId, songId: songId, position: pos++));
        report.playlistSongsAdded++;
      }
    }

    // Left out of the library: put under the new root.
    if (data.leftOut > 0) {
      final all = await exclusions.load();
      final before = all.length;
      for (final rel in data.leftOutRelative) {
        final base = (newRoot != null && newRoot.isNotEmpty) ? newRoot : data.root;
        if (base.isEmpty) continue;
        all.add(_p.join(base, rel));
      }
      all.addAll(data.leftOutAbsolute);
      if (all.length != before) await exclusions.save(all);
      report.leftOutAdded = all.length - before;
    }

    if (includeLyrics) {
      for (final l in data.lyrics) {
        final before = await db.customSelect(
          'SELECT 1 FROM lyrics_cache WHERE track_key = ?',
          variables: [Variable<String>(l.trackKey)],
        ).get();
        if (before.isNotEmpty) continue; // what this phone found itself stays
        await db.into(db.lyricsCache).insert(LyricsCacheCompanion.insert(
              trackKey: l.trackKey,
              found: const Value(true),
              plainLyrics: Value(l.plain.isEmpty ? null : l.plain),
              syncedLyrics: Value(l.synced.isEmpty ? null : l.synced),
              instrumental: Value(l.instrumental),
              source: Value(l.source),
              fetchedAt: DateTime.now(),
            ));
        report.lyricsAdded++;
      }
    }

    if (includeSettings) {
      for (final e in data.settings.entries) {
        // Whatever the file says, only the safe ones are ever written.
        if (!isBackedUpSetting(e.key)) continue;
        await settings.writeValue(e.key, e.value);
        report.settingsApplied++;
      }
    }
    return report;
  }
}
