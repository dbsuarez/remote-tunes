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
/// `entries` is the display order. `_order` is the play order when shuffle is off
/// (the same as the display order).
///
/// With shuffle on, a **round** plays every song once: `_upcoming` are the songs
/// not played yet (in the random order they will come), `_history` is what has
/// played in this round and `_cursor` where we are in it, so Back and Next walk the
/// same path. A song that has played is never picked again until every other song
/// has (then, with repeat on, a new round starts).
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

  // Shuffle: the songs still to come this round, and the ones already played.
  List<int> _upcoming = [];
  final List<int> _history = [];
  int _cursor = -1;
  static const _historyLimit = 1000;

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
    } else {
      _entries.addAll(added);
    }
    if (_shuffle) {
      final ids = [for (final e in added) e.id];
      if (playNext && ci >= 0) {
        // Right after the one playing.
        _upcoming.insertAll(0, ids);
      } else {
        // Anywhere in what is still to come (it is a shuffle).
        for (final id in ids) {
          _upcoming.insert(_random.nextInt(_upcoming.length + 1), id);
        }
      }
    } else if (playNext && ci >= 0) {
      final oi = _order.indexOf(_currentId!);
      _order.insertAll(oi + 1, [for (final e in added) e.id]);
    } else {
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
      if (_shuffle) {
        // What plays next in the round (or in a new round, with repeat on).
        if (_upcoming.isNotEmpty) {
          _currentId = _upcoming.removeAt(0);
        } else if (_repeat == RepeatMode.queue && _entries.length > 1) {
          final others = [for (final e in _entries) if (e.id != entryId) e.id]..shuffle(_random);
          _currentId = others.first;
          _upcoming = others.sublist(1);
          _history.clear();
          _cursor = -1;
        } else {
          _currentId = null;
        }
      } else {
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
    }
    _entries.removeAt(index);
    _order.remove(entryId);
    _upcoming.remove(entryId);
    final h = _history.indexOf(entryId);
    if (h >= 0) {
      _history.removeAt(h);
      if (h <= _cursor) _cursor--;
    }
    if (wasCurrent && _shuffle && _currentId != null) _enterHistory(_currentId!);
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
    _upcoming = [];
    _history.clear();
    _cursor = -1;
    _currentId = null;
    _bump();
  }

  // ---------------------------------------------------------------- position

  bool jumpTo(int entryId) {
    if (_entryById(entryId) == null) return false;
    _currentId = entryId;
    // Choosing a song counts as having played it this round, and what came before
    // and what is still to come are untouched.
    if (_shuffle) {
      _upcoming.remove(entryId);
      _enterHistory(entryId);
    }
    return true;
  }

  /// Notes in the round that [id] is playing now (after whatever played before it).
  void _enterHistory(int id) {
    if (_cursor < _history.length - 1) _history.removeRange(_cursor + 1, _history.length);
    _history.add(id);
    if (_history.length > _historyLimit) _history.removeAt(0);
    _cursor = _history.length - 1;
  }

  /// The entry that would play after the current one (without moving), or null
  /// at the end. With shuffle and repeat-queue the next round is not known yet.
  QueueEntry? peekNext() {
    if (_entries.isEmpty || _currentId == null) return null;
    if (_repeat == RepeatMode.one) return current;
    if (_shuffle) {
      // Back, then Next again, goes the same way: the song that followed.
      if (_cursor >= 0 && _cursor < _history.length - 1) {
        return _entryById(_history[_cursor + 1]);
      }
      return _upcoming.isEmpty ? null : _entryById(_upcoming.first);
    }
    final oi = _order.indexOf(_currentId!);
    if (oi + 1 < _order.length) return _entryById(_order[oi + 1]);
    if (_repeat == RepeatMode.queue) return _entryById(_order.first);
    return null;
  }

  /// Moves to the next entry and returns it, or null at the end of the queue.
  /// [auto] is true when a track ended by itself (repeat-one replays it).
  QueueEntry? advance({required bool auto}) {
    if (_entries.isEmpty) return null;
    if (_currentId == null) {
      if (_shuffle) {
        _newRound();
        _currentId = _upcoming.removeAt(0);
        _enterHistory(_currentId!);
      } else {
        _currentId = _order.first;
      }
      return current;
    }
    if (auto && _repeat == RepeatMode.one) return current;

    if (_shuffle) {
      // After Back, Next retraces the same song.
      if (_cursor >= 0 && _cursor < _history.length - 1) {
        _cursor++;
        _currentId = _history[_cursor];
        return current;
      }
      if (_upcoming.isEmpty) {
        if (_repeat != RepeatMode.queue) return null;
        _newRound(avoid: _currentId);
      }
      _currentId = _upcoming.removeAt(0);
      _enterHistory(_currentId!);
      return current;
    }

    final oi = _order.indexOf(_currentId!);
    if (oi + 1 < _order.length) {
      _currentId = _order[oi + 1];
      return current;
    }
    if (_repeat == RepeatMode.queue) {
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
    if (_shuffle) {
      // Back along the songs that really played.
      if (_cursor > 0) {
        _cursor--;
        _currentId = _history[_cursor];
      }
      return current;
    }
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
    _order = [for (final e in _entries) e.id];
    _upcoming = [];
    _history.clear();
    _cursor = -1;
    if (_shuffle && _entries.isNotEmpty) {
      // The song playing now is the first of the round; everything else is still to come.
      final cur = _currentId;
      _upcoming = [for (final e in _entries) if (e.id != cur) e.id]..shuffle(_random);
      if (cur != null) _enterHistory(cur);
    }
  }

  /// Starts a round: every song, in random order (a song [avoid] does not come first,
  /// so the last song of one round is not the first of the next).
  void _newRound({int? avoid}) {
    final ids = [for (final e in _entries) e.id]..shuffle(_random);
    if (avoid != null && ids.length > 1 && ids.first == avoid) {
      ids.add(ids.removeAt(0));
    }
    _upcoming = ids;
    _history.clear();
    _cursor = -1;
  }
}
