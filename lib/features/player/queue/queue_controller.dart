import 'dart:math';

import '../../../core/models/enums.dart';
import 'playable_song.dart';

class QueueEntry {
  const QueueEntry(this.id, this.song);

  /// Unique per queue entry (the same song can be queued twice).
  final int id;
  final PlayableSong song;
}

class RemoveResult {
  const RemoveResult({required this.removed, required this.wasCurrent});

  final bool removed;

  /// The removed entry was the current one; [QueueController.current] now
  /// points at the entry that should play next (or null).
  final bool wasCurrent;
}

/// The Player's queue: entries, current position, shuffle and repeat.
/// Pure Dart (no plugins) so the logic is unit-testable.
///
/// `entries` is the display order. `_order` is the play order: the same as the
/// display order, or a shuffled permutation when shuffle is on.
class QueueController {
  QueueController({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<QueueEntry> _entries = [];
  List<int> _order = [];
  int? _currentId;
  int _nextId = 1;
  int _revision = 0;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;

  List<QueueEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;
  bool get shuffle => _shuffle;
  RepeatMode get repeat => _repeat;

  /// Bumps whenever the entries change (not for position changes).
  int get revision => _revision;

  QueueEntry? get current => _entryById(_currentId);

  /// Index of the current entry in display order, or -1.
  int get currentIndex =>
      _currentId == null ? -1 : _entries.indexWhere((e) => e.id == _currentId);

  QueueEntry? _entryById(int? id) {
    if (id == null) return null;
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _bump() => _revision++;

  // ----------------------------------------------------------------- editing

  /// Replaces the whole queue; the entry at [startIndex] becomes current.
  void replace(List<PlayableSong> songs, {int startIndex = 0}) {
    _entries
      ..clear()
      ..addAll(songs.map((s) => QueueEntry(_nextId++, s)));
    _currentId = _entries.isEmpty
        ? null
        : _entries[startIndex.clamp(0, _entries.length - 1)].id;
    _rebuildOrder();
    _bump();
  }

  /// Appends songs, or inserts them right after the current entry when
  /// [playNext] is true. Returns the new entries.
  List<QueueEntry> add(List<PlayableSong> songs, {bool playNext = false}) {
    if (songs.isEmpty) return const [];
    final added = [for (final s in songs) QueueEntry(_nextId++, s)];
    final ci = currentIndex;

    if (playNext && ci >= 0) {
      _entries.insertAll(ci + 1, added);
      final oi = _order.indexOf(_currentId!);
      _order.insertAll(oi + 1, [for (final e in added) e.id]);
    } else {
      _entries.addAll(added);
      _order.addAll([for (final e in added) e.id]);
    }
    _bump();
    return added;
  }

  RemoveResult remove(int entryId) {
    final index = _entries.indexWhere((e) => e.id == entryId);
    if (index < 0) return const RemoveResult(removed: false, wasCurrent: false);

    final wasCurrent = entryId == _currentId;
    if (wasCurrent) {
      // Pick what plays next before the entry disappears from the order.
      final oi = _order.indexOf(entryId);
      if (oi + 1 < _order.length) {
        _currentId = _order[oi + 1];
      } else if (_repeat == RepeatMode.queue && _order.length > 1) {
        _currentId = _order.first;
      } else {
        _currentId = null;
      }
    }
    _entries.removeAt(index);
    _order.remove(entryId);
    _bump();
    return RemoveResult(removed: true, wasCurrent: wasCurrent);
  }

  /// Moves an entry to [newIndex] in display order.
  bool move(int entryId, int newIndex) {
    final from = _entries.indexWhere((e) => e.id == entryId);
    if (from < 0) return false;
    final to = newIndex.clamp(0, _entries.length - 1);
    if (from == to) return true;
    final entry = _entries.removeAt(from);
    _entries.insert(to, entry);
    // A shuffled play order is not affected by display moves.
    if (!_shuffle) _order = [for (final e in _entries) e.id];
    _bump();
    return true;
  }

  void clear() {
    _entries.clear();
    _order = [];
    _currentId = null;
    _bump();
  }

  // ---------------------------------------------------------------- position

  bool jumpTo(int entryId) {
    if (_entryById(entryId) == null) return false;
    _currentId = entryId;
    return true;
  }

  /// The entry that would play after the current one (without moving), or null
  /// at the end. With shuffle and repeat-queue the next round is not known yet.
  QueueEntry? peekNext() {
    if (_entries.isEmpty || _currentId == null) return null;
    if (_repeat == RepeatMode.one) return current;
    final oi = _order.indexOf(_currentId!);
    if (oi + 1 < _order.length) return _entryById(_order[oi + 1]);
    if (_repeat == RepeatMode.queue && !_shuffle) return _entryById(_order.first);
    return null;
  }

  /// Moves to the next entry and returns it, or null at the end of the queue.
  /// [auto] is true when a track ended by itself (repeat-one replays it).
  QueueEntry? advance({required bool auto}) {
    if (_entries.isEmpty) return null;
    if (_currentId == null) {
      _currentId = _order.first;
      return current;
    }
    if (auto && _repeat == RepeatMode.one) return current;

    final oi = _order.indexOf(_currentId!);
    if (oi + 1 < _order.length) {
      _currentId = _order[oi + 1];
      return current;
    }
    if (_repeat == RepeatMode.queue) {
      if (_shuffle) _reshuffle(avoidFirst: _currentId);
      _currentId = _order.first;
      return current;
    }
    return null;
  }

  /// Moves to the previous entry and returns it. At the start of the queue it
  /// returns the current entry (the caller restarts it), or wraps with
  /// repeat-queue.
  QueueEntry? back() {
    if (_currentId == null) return null;
    final oi = _order.indexOf(_currentId!);
    if (oi > 0) {
      _currentId = _order[oi - 1];
    } else if (_repeat == RepeatMode.queue && _order.length > 1) {
      _currentId = _order.last;
    }
    return current;
  }

  // ------------------------------------------------------------ shuffle/repeat

  void setShuffle(bool on) {
    if (on == _shuffle) return;
    _shuffle = on;
    _rebuildOrder();
  }

  void setRepeat(RepeatMode mode) => _repeat = mode;

  void _rebuildOrder() {
    if (!_shuffle) {
      _order = [for (final e in _entries) e.id];
      return;
    }
    _reshuffle();
  }

  /// Current entry first, then the others in random order.
  void _reshuffle({int? avoidFirst}) {
    final ids = [for (final e in _entries) e.id];
    final head = _currentId != null && avoidFirst == null ? _currentId : null;
    final rest = ids.where((id) => id != head).toList()..shuffle(_random);
    if (avoidFirst != null && rest.length > 1 && rest.first == avoidFirst) {
      final swap = rest.removeAt(0);
      rest.add(swap);
    }
    _order = [if (head != null) head, ...rest];
  }
}
