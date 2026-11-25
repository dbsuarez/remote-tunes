import 'package:go_router/go_router.dart';

import '../../features/controller/controller_screen.dart';
import '../../features/player/eq/equalizer_screen.dart';
import '../../features/player/player_screen.dart' show RemotePlaybackScreen;
import '../../features/shell/app_shell.dart';
import '../../features/settings/diagnostics_screen.dart';
import '../../features/settings/settings_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const settings = '/settings';
  static const diagnostics = '/settings/diagnostics';
  static const connect = '/connect';
  static const equalizer = '/equalizer';
  static const remotePlayback = '/remote-playback';
}

GoRouter createRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        // The music player (what "When the app opens" in Settings then does:
        // this phone's music, or reconnecting to the last Player).
        builder: (context, state) => const AppShell(),
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
        path: AppRoutes.equalizer,
        builder: (context, state) => const EqualizerScreen(),
      ),
      // From the music player: find a Player and use this phone as its remote.
      GoRoute(
        path: AppRoutes.connect,
        builder: (context, state) => const ControllerScreen(),
      ),
      // Start / stop remote playback and see who is connected.
      GoRoute(
        path: AppRoutes.remotePlayback,
        builder: (context, state) => const RemotePlaybackScreen(),
      ),
    ],
  );
}
