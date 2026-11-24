import 'package:drift/drift.dart';

import '../../core/jamendo_url.dart';
import '../../core/protocol/library_models.dart';
import '../../features/player/queue/playable_song.dart';
import '../database/app_database.dart';

/// What was played from the Online Library. Text and links only (never audio),
/// kept on the Player, never uploaded. The user can turn it off, remove single
/// entries, or clear it.
class OnlineHistoryRepository {
  OnlineHistoryRepository(this._db);

  final AppDatabase _db;

  /// The oldest entries are dropped past this many.
  static const maxEntries = 200;
  static const _enabledKey = 'online_history_enabled';

  Future<bool> isEnabled() async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(_enabledKey)))
        .getSingleOrNull();
    return row?.value != 'false'; // on by default
  }

  Future<void> setEnabled(bool enabled) =>
      _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(
            key: _enabledKey,
            value: enabled.toString(),
            updatedAt: Value(DateTime.now()),
          ));

  /// Remembers that [song] started playing. Playing a track again moves it to
  /// the top instead of adding a second entry. Does nothing while history is
  /// turned off, or for anything that is not an Online Library track.
  Future<void> record(PlayableSong song) async {
    final url = song.url;
    if (url == null || jamendoHttpsUrl(url) == null) return;
    if (!await isEnabled()) return;
    final entry = OnlineHistoryCompanion.insert(
      url: url,
      title: song.title,
      artist: song.artist,
      album: song.album,
      licenseUrl: Value(creativeCommonsUrl(song.licenseUrl)),
      imageUrl: Value(jamendoHttpsUrl(song.imageUrl)),
      playedAt: Value(DateTime.now()),
    );
    // The same link played again updates its entry (the link is the key).
    await _db.into(_db.onlineHistory).insert(
          entry,
          onConflict: DoUpdate((_) => entry, target: [_db.onlineHistory.url]),
        );
    // Keep only the newest entries.
    await _db.customStatement(
      'DELETE FROM online_history WHERE id NOT IN '
      '(SELECT id FROM online_history ORDER BY played_at DESC, id DESC LIMIT $maxEntries)',
    );
  }

  /// Newest first.
  Future<LibraryPage<RemoteHistoryItem>> list({int offset = 0, int limit = 50}) async {
    final total = (await _db
            .customSelect('SELECT COUNT(*) AS c FROM online_history')
            .getSingle())
        .read<int>('c');
    final rows = await (_db.select(_db.onlineHistory)
          ..orderBy([
            (t) => OrderingTerm.desc(t.playedAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit, offset: offset))
        .get();
    return LibraryPage(
      items: [
        for (final r in rows)
          RemoteHistoryItem(
            id: r.id,
            title: r.title,
            artist: r.artist,
            album: r.album,
            licenseUrl: r.licenseUrl,
            imageUrl: r.imageUrl,
            playedAtSeconds: r.playedAt.millisecondsSinceEpoch ~/ 1000,
          ),
      ],
      total: total,
      offset: offset,
    );
  }

  /// The track behind a history entry, to play it again (the link stays on the
  /// Player). Null if it was removed.
  Future<PlayableSong?> song(int id) async {
    final r = await (_db.select(_db.onlineHistory)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return PlayableSong.stream(
      url: r.url,
      title: r.title,
      artist: r.artist,
      album: r.album,
      licenseUrl: creativeCommonsUrl(r.licenseUrl),
      imageUrl: jamendoHttpsUrl(r.imageUrl),
    );
  }

  Future<void> remove(int id) =>
      (_db.delete(_db.onlineHistory)..where((t) => t.id.equals(id))).go();

  Future<void> clear() => _db.delete(_db.onlineHistory).go();
}
