import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Songs,
    QueueItems,
    Settings,
    PairedControllers,
    RecentUrls,
    Playlists,
    PlaylistSongs,
    QueueStreams,
    OnlineHistory,
    LyricsCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens `remote_tunes.db` in the app documents directory (lazily).
  AppDatabase() : super(_openConnection());

  /// For tests: pass `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createPlayEvents();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Trusted devices: keeps every existing row (and the library).
            await m.addColumn(pairedControllers, pairedControllers.tokenHash);
            await m.addColumn(pairedControllers, pairedControllers.trusted);
          }
          if (from < 3) {
            // Favorites, recently played and playlists: the library is kept.
            await m.addColumn(songs, songs.favorite);
            await m.addColumn(songs, songs.lastPlayedAt);
            await m.createTable(playlists);
            await m.createTable(playlistSongs);
          }
          if (from < 4) {
            // Internet tracks in the saved queue, and the Online Library history.
            await m.createTable(queueStreams);
            await m.createTable(onlineHistory);
          }
          if (from < 5) {
            // Play counts, for the "Top" list. Existing songs start at 0.
            await m.addColumn(songs, songs.playCount);
          }
          if (from < 6) {
            // Lyrics found on the internet, kept per song.
            await m.createTable(lyricsCache);
          }
          if (from < 7) {
            // Album artist, genre and year, filled by re-reading the tags.
            await m.addColumn(songs, songs.albumArtist);
            await m.addColumn(songs, songs.genre);
            await m.addColumn(songs, songs.year);
          }
          if (from < 8) {
            // Replay Gain values, filled by re-reading the tags.
            await m.addColumn(songs, songs.replayGainDb);
            await m.addColumn(songs, songs.albumGainDb);
          }
          if (from < 9) {
            await m.addColumn(songs, songs.composer);
          }
          if (from < 10) {
            // Skips are counted from now on; every song starts at 0.
            await m.addColumn(songs, songs.skipCount);
          }
          if (from < 11) {
            // Which songs were edited by hand (from now on).
            await m.addColumn(songs, songs.infoEdited);
          }
        },
        // Future migrations MUST preserve the library (docs/03_DATA_MODEL.md).
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // The play log (one row per song played); made here so every older database gets it too.
          await _createPlayEvents();
        },
      );
}

extension PlayEventsTable on AppDatabase {
  /// One row per song played: when it started, how many seconds were really heard, and how it
  /// ended (`finished`, `skipped` or `stopped`). Kept on the phone; Settings can switch it off and
  /// clear it. No foreign key: the history stays when a song is removed from the library.
  Future<void> _createPlayEvents() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS play_events ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'song_id INTEGER NOT NULL, '
      'started_at INTEGER NOT NULL, '
      'heard_seconds INTEGER NOT NULL DEFAULT 0, '
      "outcome TEXT NOT NULL DEFAULT 'stopped')",
    );
    await customStatement('CREATE INDEX IF NOT EXISTS play_events_started ON play_events (started_at)');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, AppConstants.databaseFileName));
    return NativeDatabase.createInBackground(file);
  });
}
