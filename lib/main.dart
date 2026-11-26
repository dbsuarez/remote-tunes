import 'features/cloud/cloud_pickers.dart';
import 'features/cloud/cloud_pickers_phone.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/repositories/drift_recent_links_store.dart';
import 'features/group/group_follower_service.dart';
import 'features/group/group_providers.dart';
import 'providers/connection_providers.dart';
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
        // The Cloud Library settings can be filled from a notes file picked on the phone.
        cloudNotesPickerProvider.overrideWithValue(pickNotesFile),
        cloudCoverPickerProvider.overrideWithValue(pickCoverFile),
        // Recent links live in the phone's database.
        recentLinksStoreProvider.overrideWith(
          (ref) => DriftRecentLinksStore(ref.watch(recentUrlsRepositoryProvider)),
        ),
        // Group play (this phone plays along with the Player) needs audio, so
        // only the phone app has it.
        groupFollowerProvider.overrideWith((ref) {
          final f = GroupFollowerService(client: ref.watch(controllerClientProvider));
          ref.onDispose(() => unawaited(f.dispose()));
          return f;
        }),
      ],
      child: const RemoteTunesApp(),
    ),
  );
}
