import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/accent.dart';
import 'core/constants.dart';
import 'core/haptics.dart';
import 'core/router/app_router.dart';
import 'core/song_list_style.dart';
import 'core/theme/app_theme.dart';
import 'providers/providers.dart';

class RemoteTunesApp extends ConsumerStatefulWidget {
  const RemoteTunesApp({super.key});

  @override
  ConsumerState<RemoteTunesApp> createState() => _RemoteTunesAppState();
}

class _RemoteTunesAppState extends ConsumerState<RemoteTunesApp> {
  late final GoRouter _router = createRouter();

  @override
  Widget build(BuildContext context) {
    // Song list text size follows the saved setting.
    ref.listen(settingsProvider, (_, next) {
      final settings = next.valueOrNull;
      if (settings == null) return;
      ref.read(songListSizeProvider.notifier).state = settings.songListSize;
      Haptics.enabled = settings.hapticsEnabled;
      ref.read(accentFromArtProvider.notifier).state = settings.accentFromArt;
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
