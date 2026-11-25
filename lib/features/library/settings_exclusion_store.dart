import 'dart:convert';

import '../../data/repositories/settings_repository.dart';
import 'import_service.dart';

/// Keeps the folders that were added (for the one-tap rescan) in the app's settings.
class SettingsMusicFoldersStore implements MusicFoldersStore {
  SettingsMusicFoldersStore(this._repo);

  final SettingsRepository _repo;
  static const key = 'music_folders';

  @override
  Future<List<MusicFolder>> load() async {
    try {
      final text = await _repo.readValue(key);
      if (text == null || text.isEmpty) return [];
      final v = jsonDecode(text);
      if (v is! List) return [];
      return [for (final e in v) if (MusicFolder.fromJson(e) != null) MusicFolder.fromJson(e)!];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<MusicFolder> folders) =>
      _repo.writeValue(key, jsonEncode([for (final f in folders) f.toJson()]));
}

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
