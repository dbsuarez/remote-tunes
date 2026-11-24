import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/accent.dart';
import 'core/constants.dart';
import 'core/haptics.dart';
import 'core/router/app_router.dart';
import 'core/search_history.dart';
import 'features/update/update_controller.dart';
import 'core/song_list_style.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';

class RemoteTunesApp extends ConsumerStatefulWidget {
  const RemoteTunesApp({super.key});

  @override
  ConsumerState<RemoteTunesApp> createState() => _RemoteTunesAppState();
}

class _RemoteTunesAppState extends ConsumerState<RemoteTunesApp> with WidgetsBindingObserver {
  late final GoRouter _router = createRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's install screen or its "allow installs" switch.
    if (state == AppLifecycleState.resumed) {
      ref.read(updateProvider.notifier).onResumed().catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Song list text size follows the saved setting.
    ref.listen(settingsProvider, (_, next) {
      final settings = next.valueOrNull;
      if (settings == null) return;
      ref.read(songListSizeProvider.notifier).state = settings.songListSize;
      Haptics.enabled = settings.hapticsEnabled;
      ref.read(accentFromArtProvider.notifier).state = settings.accentFromArt;
      // The saved searches are picked up once; after that the list is saved
      // whenever it changes (below).
      ref.read(searchHistoryProvider.notifier).load(settings.searchHistory);
    });
    ref.listen(searchHistoryProvider, (prev, next) {
      if (prev == null || identical(prev, next)) return;
      // What was just read from storage is not written back.
      if (identical(next, ref.read(searchHistoryProvider.notifier).fromStorage)) return;
      ref.read(settingsRepositoryProvider).setSearchHistory(next).catchError((Object _) {});
    });
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
