import 'package:drift/drift.dart';

import '../../core/jamendo_url.dart';
import '../../features/player/queue/playable_song.dart';
import '../../features/player/queue/queue_store.dart';
import '../database/app_database.dart';
import 'library_repository.dart';

/// Keeps the queue between runs: library songs in `queue_items` (song ids
/// only) and internet tracks in `queue_streams` (link and text only, never
/// audio). Both share one `position` numbering, so the mixed order is kept. The
/// current position is kept in `settings`.
///
/// Songs deleted from the library drop out by themselves (foreign key
/// cascade).
class DriftQueueStore implements QueueStore {
  DriftQueueStore(this._db);

  final AppDatabase _db;
  static const _currentKey = 'queue_current_index';

  @override
  Future<void> save(List<PlayableSong> songs, int currentIndex) async {
    await _db.transaction(() async {
      await _db.delete(_db.queueItems).go();
      await _db.delete(_db.queueStreams).go();
      for (var i = 0; i < songs.length; i++) {
        final s = songs[i];
        if (s.isUrl) {
          await _db.into(_db.queueStreams).insert(QueueStreamsCompanion.insert(
                position: i,
                url: s.url!,
                title: s.title,
                artist: s.artist,
                album: s.album,
                licenseUrl: Value(s.licenseUrl),
                imageUrl: Value(s.imageUrl),
              ));
        } else {
          await _db.into(_db.queueItems).insert(QueueItemsCompanion.insert(
                songId: s.id,
                position: i,
                source: 'localFile',
              ));
        }
      }
      // The position (not a count) of the current entry, so it still points at
      // the right song if a library song was deleted meanwhile.
      await _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(
            key: _currentKey,
            value: currentIndex.toString(),
            updatedAt: Value(DateTime.now()),
          ));
    });
  }

  @override
  Future<({List<PlayableSong> songs, int currentIndex})> load() async {
    final entries = <({int position, PlayableSong song})>[];

    final libraryRows = await _db.customSelect(
      'SELECT s.*, q.position AS q_position, q.id AS q_id FROM queue_items q '
      'JOIN songs s ON s.id = q.song_id',
      readsFrom: {_db.queueItems, _db.songs},
    ).get();
    for (final r in libraryRows) {
      final playable = _db.songs.map(r.data).toPlayable();
      if (playable != null) {
        entries.add((position: r.read<int>('q_position'), song: playable));
      }
    }

    for (final s in await _db.select(_db.queueStreams).get()) {
      // The links come from our own earlier writes, but the database is still
      // outside input: keep only artwork and licence links we would accept.
      entries.add((
        position: s.position,
        song: PlayableSong.stream(
          url: s.url,
          title: s.title,
          artist: s.artist,
          album: s.album,
          licenseUrl: creativeCommonsUrl(s.licenseUrl),
          imageUrl: jamendoHttpsUrl(s.imageUrl),
        ),
      ));
    }
    entries.sort((a, b) => a.position.compareTo(b.position));

    final saved = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(_currentKey)))
        .getSingleOrNull();
    final savedPosition = int.tryParse(saved?.value ?? '') ?? 0;
    // First entry at or after the saved position (the current song, or the
    // next one if it is gone).
    var index = entries.indexWhere((e) => e.position >= savedPosition);
    if (index < 0) index = entries.isEmpty ? 0 : entries.length - 1;
    return (songs: [for (final e in entries) e.song], currentIndex: index);
  }
}
