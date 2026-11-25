import '../features/library/settings_exclusion_store.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/permissions.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/recent_urls_repository.dart';
import '../features/library/import_service.dart';
import '../features/library/metadata_extractor.dart';
import '../features/player/lyrics_service.dart';
import 'providers.dart';

/// Looks up and remembers lyrics (Player side). Honors the Settings switch.
final lyricsServiceProvider = Provider<LyricsService>((ref) {
  final db = ref.watch(databaseProvider);
  return LyricsService(
    library: ref.watch(libraryRepositoryProvider),
    db: db,
    isEnabled: () async => (await ref.read(settingsRepositoryProvider).load()).lyricsEnabled,
  );
});

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.watch(databaseProvider));
});

final recentUrlsRepositoryProvider = Provider<RecentUrlsRepository>((ref) {
  return RecentUrlsRepository(ref.watch(databaseProvider));
});

/// Imports into `<app documents>/library` (copies) and `<app documents>/art`.
final importServiceProvider = FutureProvider<LibraryImportService>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return LibraryImportService(
    library: ref.watch(libraryRepositoryProvider),
    extractor: AudioMetadataExtractor(),
    libraryDir: Directory(p.join(docs.path, 'library')),
    artDir: Directory(p.join(docs.path, 'art')),
    exclusions: SettingsExclusionStore(ref.watch(settingsRepositoryProvider)),
    folders: SettingsMusicFoldersStore(ref.watch(settingsRepositoryProvider)),
  );
});

/// Overridable in tests (the real one needs the Android plugin).
final permissionsProvider =
    Provider<AppPermissions>((ref) => PermissionHandlerPermissions());
