import 'package:go_router/go_router.dart';

import '../../features/controller/controller_screen.dart';
import '../../features/player/player_library_screens.dart';
import '../../features/player/player_screen.dart';
import '../../features/shell/start_gate.dart';
import '../../features/settings/diagnostics_screen.dart';
import '../../features/settings/settings_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const settings = '/settings';
  static const diagnostics = '/settings/diagnostics';
  static const player = '/player';
  static const playerLibrary = '/player/library';
  static const playerQueue = '/player/queue';
  static const playerUrl = '/player/url';
  static const controller = '/controller';
  static const connect = '/connect';
  static const remotePlayback = '/remote-playback';
}

GoRouter createRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        // What opens first follows the setting "When the app opens".
        builder: (context, state) => const StartGate(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'diagnostics',
            builder: (context, state) => const DiagnosticsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.player,
        builder: (context, state) => const PlayerScreen(),
        routes: [
          GoRoute(
            path: 'library',
            builder: (context, state) => const PlayerLibraryScreen(),
          ),
          GoRoute(
            path: 'queue',
            builder: (context, state) => const PlayerQueueScreen(),
          ),
          GoRoute(
            path: 'url',
            builder: (context, state) => const PlayerUrlScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.controller,
        builder: (context, state) => const ControllerScreen(),
      ),
      // From the music player: find a Player and use this phone as its remote.
      GoRoute(
        path: AppRoutes.connect,
        builder: (context, state) => const ControllerScreen(popWhenConnected: true),
      ),
      // Start / stop remote playback and see who is connected.
      GoRoute(
        path: AppRoutes.remotePlayback,
        builder: (context, state) => const RemotePlaybackScreen(),
      ),
    ],
  );
}
