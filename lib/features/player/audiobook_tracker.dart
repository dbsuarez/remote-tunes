import '../../core/list_memory.dart';
import '../../data/repositories/library_repository.dart';

/// What the player needs to know about audiobooks: which songs are one, where each was left, and
/// which list was being played (so "Play" on that list carries on from the same chapter).
///
/// Only audiobooks are remembered this way; music always starts at the beginning. The set of
/// audiobook ids is kept in memory so the player can ask without waiting.
class AudiobookTracker implements ListMemory {
  AudiobookTracker(this._library, {bool Function()? enabled}) : _enabled = enabled ?? (() => true);

  final LibraryRepository _library;

  /// False when "Remember my place in audiobooks" is off in Settings.
  final bool Function() _enabled;

  final Set<int> _ids = {};
  bool _loaded = false;

  /// The list (see [listKeyFor]) the song playing was started from, if any.
  String? activeListKey;

  @override
  void setActive(String? key) => activeListKey = key;

  /// Reads which songs are audiobooks. Call once at start-up.
  Future<void> load() async {
    _ids
      ..clear()
      ..addAll(await _library.audiobookIds());
    _loaded = true;
  }

  bool get loaded => _loaded;
  bool get enabled => _enabled();

  bool isAudiobook(int songId) => _ids.contains(songId);

  /// Marks songs as audiobooks (or as music again). Returns how many changed.
  Future<int> mark(Iterable<int> songIds, bool audiobook) async {
    final list = songIds.toList();
    final changed = await _library.setAudiobook(list, audiobook);
    if (audiobook) {
      _ids.addAll(list);
    } else {
      _ids.removeAll(list);
    }
    return changed;
  }

  /// Marks the songs whose genre or folder says "audiobook" (never un-marks anything).
  Future<int> findByTags() async {
    final n = await _library.markAudiobooksByTags();
    _ids
      ..clear()
      ..addAll(await _library.audiobookIds());
    return n;
  }

  /// Where the audiobook was left, in seconds (0: from the start, or not an audiobook).
  Future<int> placeOf(int songId) async {
    if (!enabled || !_ids.contains(songId)) return 0;
    return _library.audiobookPosition(songId);
  }

  /// Remembers the place in an audiobook. [seconds] 0 means "finished; next time from the start".
  Future<void> save(int songId, int seconds) async {
    if (!enabled || !_ids.contains(songId)) return;
    await _library.saveAudiobookPosition(songId, seconds);
  }

  /// A song of the active list started playing: remember it, if it is an audiobook.
  Future<void> started(int songId) async {
    final key = activeListKey;
    if (!enabled || key == null || !_ids.contains(songId)) return;
    await _library.saveListPosition(key, songId);
  }

  /// The audiobook the list was left at, if there is one.
  @override
  Future<int?> positionFor(String key) async {
    if (!enabled) return null;
    final id = await _library.listPosition(key);
    return id != null && _ids.contains(id) ? id : null;
  }
}
