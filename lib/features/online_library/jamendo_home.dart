import 'package:flutter/foundation.dart';

import 'jamendo_api.dart';

/// The state of one shelf on the Online Library home screen.
class ShelfState {
  const ShelfState({this.tracks = const [], this.loading = false, this.error});

  final List<JamendoTrack> tracks;
  final bool loading;
  final JamendoException? error;

  bool get loaded => tracks.isNotEmpty;
}

/// The ready-made shelves shown before anything is searched: popular this week
/// and month, newest releases. Fetched one after another (Jamendo wants
/// requests spaced out), kept for a while so going back to the tab is instant.
class JamendoHome extends ChangeNotifier {
  JamendoHome({this.keepFor = const Duration(minutes: 15), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Duration keepFor;
  final DateTime Function() _now;

  final Map<JamendoShelf, ShelfState> _shelves = {
    for (final s in JamendoShelf.values) s: const ShelfState(),
  };
  DateTime? _loadedAt;
  String? _forClient;
  bool _running = false;

  ShelfState shelf(JamendoShelf s) => _shelves[s]!;

  bool get anyLoaded => _shelves.values.any((s) => s.loaded);

  bool get _fresh =>
      _loadedAt != null && _now().difference(_loadedAt!) < keepFor;

  /// Fills the shelves that are empty (or all of them when [refresh], or when
  /// they are old). Does nothing if it is already running.
  Future<void> load(JamendoApi api, String clientId, {bool refresh = false}) async {
    if (_running) return;
    if (_forClient != clientId) {
      for (final s in JamendoShelf.values) {
        _shelves[s] = const ShelfState();
      }
      _loadedAt = null;
    }
    _forClient = clientId;
    final all = refresh || !_fresh;
    _running = true;
    try {
      for (final s in JamendoShelf.values) {
        if (!all && _shelves[s]!.loaded) continue;
        _shelves[s] = ShelfState(tracks: _shelves[s]!.tracks, loading: true);
        notifyListeners();
        try {
          final page = await api.browse(clientId: clientId, shelf: s);
          _shelves[s] = ShelfState(tracks: page.tracks);
          _loadedAt = _now();
        } on JamendoException catch (e) {
          // Keep what was there; say what went wrong.
          _shelves[s] = ShelfState(tracks: _shelves[s]!.tracks, error: e);
          notifyListeners();
          // No internet or a refused ID: the other shelves would fail the same way.
          if (e.offline || e.badKey) break;
        } catch (_) {
          _shelves[s] = ShelfState(
              tracks: _shelves[s]!.tracks,
              error: JamendoException('Something went wrong. Please try again.'));
        }
        notifyListeners();
      }
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Forgets everything (the client ID was changed or removed).
  void clear() {
    for (final s in JamendoShelf.values) {
      _shelves[s] = const ShelfState();
    }
    _loadedAt = null;
    _forClient = null;
    notifyListeners();
  }
}
