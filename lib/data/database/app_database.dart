import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Songs, QueueItems, Settings, PairedControllers, RecentUrls],
)
class AppDatabase extends _$AppDatabase {
  /// Opens `remote_tunes.db` in the app documents directory (lazily).
  AppDatabase() : super(_openConnection());

  /// For tests: pass `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Trusted devices: keeps every existing row (and the library).
            await m.addColumn(pairedControllers, pairedControllers.tokenHash);
            await m.addColumn(pairedControllers, pairedControllers.trusted);
          }
        },
        // Future migrations MUST preserve the library (docs/03_DATA_MODEL.md).
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, AppConstants.databaseFileName));
    return NativeDatabase.createInBackground(file);
  });
}
