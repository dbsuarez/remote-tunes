import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What was searched for lately, newest first. Kept in memory here; the phone
/// app saves and restores it (see `app.dart`), the web Controller just keeps it
/// until the page is closed.
final searchHistoryProvider =
    StateNotifierProvider<SearchHistory, List<String>>((ref) => SearchHistory());

class SearchHistory extends StateNotifier<List<String>> {
  SearchHistory() : super(const []);

  static const maxEntries = 20;
  static const minLength = 2;
  static const maxLength = 80;

  bool _loaded = false;

  /// The list that came from storage, so it is not written straight back.
  List<String>? fromStorage;

  /// Takes the saved list once, at start-up. Later calls are ignored so saving
  /// and loading never chase each other.
  void load(List<String> saved) {
    if (_loaded) return;
    _loaded = true;
    if (state.isEmpty) {
      final cleaned = _clean(saved);
      fromStorage = cleaned;
      state = cleaned;
    }
  }

  static List<String> _clean(List<String> items) {
    final out = <String>[];
    for (final raw in items) {
      final t = raw.trim();
      if (t.length < minLength) continue;
      final clipped = t.length > maxLength ? t.substring(0, maxLength) : t;
      if (out.any((e) => e.toLowerCase() == clipped.toLowerCase())) continue;
      out.add(clipped);
      if (out.length >= maxEntries) break;
    }
    return out;
  }

  /// Remembers a search (moved to the top if it was already there).
  void add(String query) {
    final t = query.trim();
    if (t.length < minLength) return;
    state = _clean([t, ...state]);
  }

  void remove(String query) {
    state = [for (final e in state) if (e != query) e];
  }

  void clear() => state = const [];
}
