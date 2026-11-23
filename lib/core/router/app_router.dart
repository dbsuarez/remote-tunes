import 'package:go_router/go_router.dart';

import '../../features/controller/controller_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/player/player_library_screens.dart';
import '../../features/player/player_screen.dart';
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
}

GoRouter createRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
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
    ],
  );
}
