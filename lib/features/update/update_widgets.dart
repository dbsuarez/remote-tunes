import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../providers/providers.dart';
import 'update_controller.dart';

/// On the Home screen: checks quietly now and then, and shows a card when a
/// newer version is out.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updateProvider.notifier).autoCheck().catchError((Object _) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(updateProvider);
    final info = u.info;
    final show = info != null &&
        (u.status == UpdateStatus.available ||
            u.status == UpdateStatus.downloading ||
            u.status == UpdateStatus.installing ||
            u.status == UpdateStatus.needsPermission ||
            u.status == UpdateStatus.failed);
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.system_update_rounded),
          title: Text('Version ${info.version} is available'),
          subtitle: u.status == UpdateStatus.downloading
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(value: u.progress == 0 ? null : u.progress),
                )
              : Text(u.message ?? 'You have ${u.installed ?? 'an older version'}.'),
          trailing: (u.status == UpdateStatus.downloading || u.status == UpdateStatus.installing)
              ? null
              : FilledButton(
                  onPressed: () => ref.read(updateProvider.notifier).install(),
                  child: const Text('Update'),
                ),
        ),
      ),
    );
  }
}

/// The "App updates" part of Settings.
class UpdateSettingsTiles extends ConsumerWidget {
  const UpdateSettingsTiles({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(updateProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final busy = u.status == UpdateStatus.checking ||
        u.status == UpdateStatus.downloading ||
        u.status == UpdateStatus.installing;

    String subtitle;
    switch (u.status) {
      case UpdateStatus.checking:
        subtitle = 'Looking for a newer version...';
      case UpdateStatus.upToDate:
        subtitle = 'You have the newest version${u.installed == null ? '' : ' (${u.installed})'}.';
      case UpdateStatus.available:
        subtitle = 'Version ${u.info?.version} is ready to install.';
      case UpdateStatus.downloading:
        subtitle = 'Downloading... ${(u.progress * 100).round()}%';
      case UpdateStatus.installing:
        subtitle = u.message ?? 'Confirm the install on the screen Android opened.';
      case UpdateStatus.needsPermission:
      case UpdateStatus.failed:
        subtitle = u.message ?? 'Something went wrong.';
      case UpdateStatus.idle:
        subtitle = u.installed == null ? 'Updates come from GitHub.' : 'Installed: ${u.installed}';
    }

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.system_update_rounded),
          title: Text(u.status == UpdateStatus.available || u.status == UpdateStatus.downloading
              ? 'Update to ${u.info?.version}'
              : 'Check for updates'),
          subtitle: Text(subtitle),
          trailing: busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          onTap: busy
              ? null
              : () {
                  final n = ref.read(updateProvider.notifier);
                  if (u.status == UpdateStatus.available ||
                      u.status == UpdateStatus.needsPermission) {
                    n.install();
                  } else {
                    n.check();
                  }
                },
        ),
        if ((u.info?.notes ?? '').isNotEmpty && u.status == UpdateStatus.available)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(u.info!.notes,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Check automatically'),
          subtitle: const Text(
              'About once a day, when the app opens. Only asks GitHub; sends nothing about you.'),
          value: settings.autoUpdateCheck,
          onChanged: repo.setAutoUpdateCheck,
        ),
      ],
    );
  }
}
