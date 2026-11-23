import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/repositories/drift_recent_links_store.dart';
import 'providers/library_providers.dart';
import 'providers/recent_links.dart';

/// Nothing network-related (Supabase, discovery, audio) starts here: Local mode
/// must work with no internet (docs/00_PROJECT_OVERVIEW.md). Those start only
/// when the user opens Player or Controller mode.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Phones stay upright (the manifest locks it too).
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  runApp(
    ProviderScope(
      overrides: [
        // Recent links live in the phone's database.
        recentLinksStoreProvider.overrideWith(
          (ref) => DriftRecentLinksStore(ref.watch(recentUrlsRepositoryProvider)),
        ),
      ],
      child: const RemoteTunesApp(),
    ),
  );
}
