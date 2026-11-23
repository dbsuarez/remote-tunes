import '../../providers/recent_links.dart';
import 'recent_urls_repository.dart';

/// Phone storage for recent links: the `recent_urls` table.
class DriftRecentLinksStore implements RecentLinksStore {
  DriftRecentLinksStore(this._repo);

  final RecentUrlsRepository _repo;

  @override
  Stream<List<RecentLink>> watch() => _repo.watch().map(
        (rows) => [
          for (final r in rows) RecentLink(id: r.id, url: r.url, title: r.title),
        ],
      );

  @override
  Future<void> remember(String url, {String? title}) =>
      _repo.remember(url, title: title);

  @override
  Future<void> remove(int id) => _repo.remove(id);

  @override
  Future<void> clear() => _repo.clear();
}
