import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/settings_repository.dart';

/// The app database. Opened lazily on first query. Overridden in tests.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

/// Live settings from Drift (the single source of truth).
final settingsProvider = StreamProvider<AppSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watch();
});

/// Paired-controller history. Empty in Phase 0 (no pairing yet).
final connectionHistoryProvider = StreamProvider<List<PairedController>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchConnectionHistory();
});
