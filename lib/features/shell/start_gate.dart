import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/enums.dart';
import '../../providers/providers.dart';
import '../home/home_screen.dart';
import 'app_shell.dart';

/// Chooses what the app shows first, from "When the app opens" in Settings: the
/// music player (this phone's music, or reconnecting to the last Player), or the
/// classic start screen.
class StartGate extends ConsumerWidget {
  const StartGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return settings.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      // If the settings cannot be read, the music player is still the right start.
      error: (_, __) => const AppShell(),
      data: (s) => s.startMode == StartMode.classic ? const HomeScreen() : const AppShell(),
    );
  }
}
