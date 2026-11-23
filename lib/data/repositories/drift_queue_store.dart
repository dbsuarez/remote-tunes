import 'package:drift/drift.dart';

import '../../features/player/queue/playable_song.dart';
import '../../features/player/queue/queue_store.dart';
import '../database/app_database.dart';
import 'library_repository.dart';

/// Keeps the queue in the `queue_items` table (song ids only) and the current
/// position in `settings`. Songs deleted from the library drop out by
/// themselves (foreign key cascade).
class DriftQueueStore implements QueueStore {
  DriftQueueStore(this._db);

  final AppDatabase _db;
  static const _currentKey = 'queue_current_index';

  @override
  Future<void> save(List<PlayableSong> songs, int currentIndex) async {
    await _db.transaction(() async {
      await _db.delete(_db.queueItems).go();
      var pos = 0;
      for (final s in songs) {
        if (s.isUrl) continue;
        await _db.into(_db.queueItems).insert(QueueItemsCompanion.insert(
              songId: s.id,
              position: pos++,
              source: 'localFile',
            ));
      }
      await _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(
            key: _currentKey,
            value: currentIndex.toString(),
            updatedAt: Value(DateTime.now()),
          ));
    });
  }

  @override
  Future<({List<PlayableSong> songs, int currentIndex})> load() async {
    final rows = await _db.customSelect(
      'SELECT s.* FROM queue_items q JOIN songs s ON s.id = q.song_id '
      'ORDER BY q.position, q.id',
      readsFrom: {_db.queueItems, _db.songs},
    ).get();
    final songs = <PlayableSong>[
      for (final r in rows)
        if (_db.songs.map(r.data).toPlayable() != null)
          _db.songs.map(r.data).toPlayable()!,
    ];
    final saved = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(_currentKey)))
        .getSingleOrNull();
    final index = int.tryParse(saved?.value ?? '') ?? 0;
    return (
      songs: songs,
      currentIndex: songs.isEmpty ? 0 : index.clamp(0, songs.length - 1),
    );
  }
}
