import 'dart:convert';

import '../../data/repositories/settings_repository.dart';
import 'import_service.dart';

/// Keeps the left-out folders and files in the app's settings.
class SettingsExclusionStore implements ExclusionStore {
  SettingsExclusionStore(this._repo);

  final SettingsRepository _repo;
  static const key = 'excluded_paths';

  @override
  Future<Set<String>> load() async {
    try {
      final text = await _repo.readValue(key);
      if (text == null || text.isEmpty) return {};
      final v = jsonDecode(text);
      return v is List ? {for (final e in v) if (e is String && e.isNotEmpty) e} : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Set<String> paths) =>
      _repo.writeValue(key, jsonEncode(paths.toList()..sort()));
}
