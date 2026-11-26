import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_models.dart';

/// What the Cloud Library remembers on this device only: the songs started here (for *Recently played*)
/// and how the list is sorted.
abstract class CloudHistoryStore {
  /// The ids of the songs started here, the latest first.
  Future<List<String>> recent();
  Future<CloudSort> sort();
  Future<void> saveRecent(List<String> ids);
  Future<void> saveSort(CloudSort sort);

  /// How many songs are remembered.
  static const keep = 50;

  /// [ids] with [id] moved (or put) to the front.
  static List<String> played(List<String> ids, String id) => [id, ...ids.where((x) => x != id)].take(keep).toList();
}

class PrefsCloudHistoryStore implements CloudHistoryStore {
  static const _recent = 'rt.cloud_recent';
  static const _sort = 'rt.cloud_sort';

  @override
  Future<List<String>> recent() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(_recent) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<CloudSort> sort() async {
    try {
      final name = (await SharedPreferences.getInstance()).getString(_sort);
      return CloudSort.values.firstWhere((s) => s.name == name, orElse: () => CloudSort.title);
    } catch (_) {
      return CloudSort.title;
    }
  }

  @override
  Future<void> saveRecent(List<String> ids) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(_recent, ids);
    } catch (_) {}
  }

  @override
  Future<void> saveSort(CloudSort sort) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_sort, sort.name);
    } catch (_) {}
  }
}

final cloudHistoryStoreProvider = Provider<CloudHistoryStore>((ref) => PrefsCloudHistoryStore());
