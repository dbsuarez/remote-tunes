import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A link the user played recently. Free of any storage details so the same
/// screen works on the phones (database) and the web Controller (browser
/// storage).
class RecentLink {
  const RecentLink({required this.id, required this.url, this.title});

  final int id;
  final String url;
  final String? title;
}

/// Where recent links are kept (FR-61: stored locally, on the device that
/// entered them).
abstract class RecentLinksStore {
  static const int maxEntries = 20;

  /// Newest first.
  Stream<List<RecentLink>> watch();

  /// Saves [url], or moves it to the top; keeps an earlier title if none given.
  Future<void> remember(String url, {String? title});
  Future<void> remove(int id);
  Future<void> clear();
}

/// Keeps links in memory only. The default, so screens work in tests; the apps
/// override it with a persistent store.
class MemoryRecentLinksStore implements RecentLinksStore {
  final List<RecentLink> _items = [];
  final StreamController<List<RecentLink>> _controller =
      StreamController<List<RecentLink>>.broadcast();
  int _nextId = 1;

  @override
  Stream<List<RecentLink>> watch() async* {
    yield List.unmodifiable(_items);
    yield* _controller.stream;
  }

  void _push() => _controller.add(List.unmodifiable(_items));

  @override
  Future<void> remember(String url, {String? title}) async {
    final i = _items.indexWhere((e) => e.url == url);
    final keptTitle = title ?? (i >= 0 ? _items[i].title : null);
    if (i >= 0) _items.removeAt(i);
    _items.insert(0, RecentLink(id: _nextId++, url: url, title: keptTitle));
    if (_items.length > RecentLinksStore.maxEntries) {
      _items.removeRange(RecentLinksStore.maxEntries, _items.length);
    }
    _push();
  }

  @override
  Future<void> remove(int id) async {
    _items.removeWhere((e) => e.id == id);
    _push();
  }

  @override
  Future<void> clear() async {
    _items.clear();
    _push();
  }
}

final recentLinksStoreProvider =
    Provider<RecentLinksStore>((ref) => MemoryRecentLinksStore());

final recentLinksProvider = StreamProvider.autoDispose<List<RecentLink>>((ref) {
  return ref.watch(recentLinksStoreProvider).watch();
});
