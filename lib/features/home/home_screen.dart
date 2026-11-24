import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../providers/providers.dart';
import '../update/update_widgets.dart';
import 'widgets/connection_mode_selector.dart';
import 'widgets/connection_pill.dart';
import 'widgets/history_section.dart';
import 'widgets/role_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull ?? const AppSettings();
    final repo = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const UpdateBanner(),
            Align(
              alignment: Alignment.centerLeft,
              child: ConnectionPill(mode: settings.connectionMode),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                minTileHeight: 64,
                leading: const Icon(Icons.smartphone_rounded),
                title: const Text('This device'),
                subtitle: Text(settings.deviceName),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final name = await _editName(context, settings.deviceName);
                  if (name != null) await repo.setDeviceName(name);
                },
              ),
            ),
            const SizedBox(height: 24),
            Text('Connection mode', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ConnectionModeSelector(
              value: settings.connectionMode,
              onChanged: repo.setConnectionMode,
            ),
            const SizedBox(height: 24),
            Text('Start as', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            RoleCard(
              icon: Icons.speaker_rounded,
              title: 'Start as PLAYER',
              subtitle: 'This phone plays the music',
              onTap: () => context.push(AppRoutes.player),
            ),
            const SizedBox(height: 12),
            RoleCard(
              icon: Icons.settings_remote_rounded,
              title: 'Start as CONTROLLER',
              subtitle: 'This phone controls another phone',
              accent: RtColors.violet,
              onTap: () => context.push(AppRoutes.controller),
            ),
            const SizedBox(height: 24),
            const HistorySection(),
          ],
        ),
      ),
    );
  }

  Future<String?> _editName(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Device name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
