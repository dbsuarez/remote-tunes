import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/permissions.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/recent_urls_repository.dart';
import '../features/library/import_service.dart';
import '../features/library/metadata_extractor.dart';
import 'providers.dart';

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
  );
});

/// Overridable in tests (the real one needs the Android plugin).
final permissionsProvider =
    Provider<AppPermissions>((ref) => PermissionHandlerPermissions());
