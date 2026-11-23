import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Links the user has played recently (stored on this phone only, FR-61).
class RecentUrlsRepository {
  RecentUrlsRepository(this._db);

  final AppDatabase _db;

  /// Most links kept; older ones are dropped.
  static const int maxEntries = 20;

  Stream<List<RecentUrl>> watch() {
    final q = _db.select(_db.recentUrls)
      ..orderBy([
        (t) => OrderingTerm.desc(t.lastUsedAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(maxEntries);
    return q.watch();
  }

  Future<List<RecentUrl>> all() => (_db.select(_db.recentUrls)
        ..orderBy([
          (t) => OrderingTerm.desc(t.lastUsedAt),
          (t) => OrderingTerm.desc(t.id),
        ])
        ..limit(maxEntries))
      .get();

  /// Saves [url] (or bumps it to the top if already saved).
  Future<void> remember(String url, {String? title}) {
    // Drift stores timestamps to the nearest second, so "newest" is decided by
    // the row id as well. Re-saving a link therefore deletes and re-inserts it,
    // which gives it the highest id, and keeps an earlier title if none given.
    return _db.transaction(() async {
      final existing = await (_db.select(_db.recentUrls)
            ..where((t) => t.url.equals(url)))
          .getSingleOrNull();
      if (existing != null) {
        await (_db.delete(_db.recentUrls)..where((t) => t.id.equals(existing.id)))
            .go();
      }
      await _db.into(_db.recentUrls).insert(
            RecentUrlsCompanion.insert(
              url: url,
              title: Value(title ?? existing?.title),
              lastUsedAt: Value(DateTime.now()),
            ),
          );
      await _db.customStatement(
        'DELETE FROM recent_urls WHERE id NOT IN '
        '(SELECT id FROM recent_urls ORDER BY last_used_at DESC, id DESC LIMIT $maxEntries)',
      );
    });
  }

  Future<void> remove(int id) =>
      (_db.delete(_db.recentUrls)..where((t) => t.id.equals(id))).go();

  Future<void> clear() => _db.delete(_db.recentUrls).go();
}
