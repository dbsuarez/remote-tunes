import 'package:drift/drift.dart';

/// Schema v1 — all five tables from docs/03_DATA_MODEL.md.
/// Only `settings` and `paired_controllers` (read-only) are used in Phase 0.
/// Enum-like columns are stored as text using the Dart enum `name`
/// (songs.source, queue_items.source, paired_controllers.connection_type).

class Songs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  TextColumn get filePath => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get albumArtPath => text().nullable()();
  IntColumn get fileSizeBytes => integer().nullable()();
  TextColumn get mimeType => text().nullable()();

  /// `localFile` | `url` (SongSource.name)
  TextColumn get source => text()();
  DateTimeColumn get addedAt => dateTime().clientDefault(DateTime.now)();

  /// Favorite songs (schema v3).
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();

  /// When the song last started playing; null if never (schema v3).
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  /// A song has file_path or url, never both and never neither.
  @override
  List<String> get customConstraints => [
        'CHECK ((file_path IS NULL) <> (url IS NULL))',
      ];
}

class QueueItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get songId =>
      integer().references(Songs, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get source => text()();
  DateTimeColumn get addedAt => dateTime().clientDefault(DateTime.now)();

  /// `player` | `controller`
  TextColumn get addedBy => text().withDefault(const Constant('player'))();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column> get primaryKey => {key};
}

class PairedControllers extends Table {
  TextColumn get sessionId => text()();
  TextColumn get controllerName => text()();
  TextColumn get controllerAddress => text().nullable()();

  /// `local` | `online` (ConnectionType.name)
  TextColumn get connectionType => text()();
  DateTimeColumn get pairedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get lastSeenAt => dateTime().clientDefault(DateTime.now)();
  BoolColumn get active => boolean().withDefault(const Constant(false))();

  /// SHA-256 of the session token, set when the Controller is trusted so it can
  /// reconnect later without pairing again. The token itself is never stored
  /// on the Player (docs/03_DATA_MODEL.md).
  TextColumn get tokenHash => text().nullable()();

  /// True while this Controller is a trusted device (until forgotten).
  BoolColumn get trusted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {sessionId};
}

class RecentUrls extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get url => text().unique()();
  TextColumn get title => text().nullable()();
  DateTimeColumn get lastUsedAt => dateTime().clientDefault(DateTime.now)();
}

/// A named list of library songs (schema v3).
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
}

/// Songs in a playlist, in order. Deleting a playlist or a song removes the rows.
class PlaylistSongs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get songId =>
      integer().references(Songs, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
}

/// Internet tracks (Online Library) in the saved queue (schema v4). `position`
/// is the track's place in the WHOLE queue, shared with `queue_items`, so
/// library songs and internet tracks keep their mixed order.
class QueueStreams extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get position => integer()();
  TextColumn get url => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get licenseUrl => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
}

/// What was played from the Online Library (schema v4): text and links only,
/// never audio. Kept on the Player, never uploaded.
class OnlineHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get url => text().unique()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get licenseUrl => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  DateTimeColumn get playedAt => dateTime().clientDefault(DateTime.now)();
}
