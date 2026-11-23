import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/connection_providers.dart';
import '../../providers/providers.dart';

/// Everything the Diagnostics screen shows. Holds no secrets: no keys, no
/// session tokens, no room codes, no file names.
class DiagnosticsInfo {
  const DiagnosticsInfo({
    required this.appVersion,
    required this.protocolVersion,
    required this.platform,
    required this.schemaVersion,
    required this.connectionMode,
    required this.onlineRelayEnabled,
    required this.onlineKeysSet,
    required this.externalControlEnabled,
    required this.notificationAccess,
    required this.port,
    required this.addresses,
    required this.songs,
    required this.favorites,
    required this.playlists,
    required this.trustedControllers,
  });

  final String appVersion;
  final int protocolVersion;
  final String platform;
  final int schemaVersion;
  final String connectionMode;
  final bool onlineRelayEnabled;
  final bool onlineKeysSet;
  final bool externalControlEnabled;

  /// Null when it was not checked (External App Control is off).
  final bool? notificationAccess;
  final int port;
  final List<String> addresses;
  final int songs;
  final int favorites;
  final int playlists;
  final int trustedControllers;

  /// Plain text for pasting into a bug report.
  String toReport() {
    String yn(bool v) => v ? 'yes' : 'no';
    final lines = <String>[
      '${AppConstants.appName} diagnostics',
      '',
      'App',
      '  Version: $appVersion',
      '  Protocol: $protocolVersion',
      '  Database schema: $schemaVersion',
      '  Phone: $platform',
      '',
      'Connection',
      '  Mode: $connectionMode',
      '  Online relay enabled: ${yn(onlineRelayEnabled)}',
      '  Relay keys set: ${yn(onlineKeysSet)}',
      '  Player port: $port',
      '  Network addresses: ${addresses.isEmpty ? 'none found' : addresses.join(', ')}',
      '  Trusted Controllers: $trustedControllers',
      '',
      'Other apps',
      '  External app control: ${yn(externalControlEnabled)}',
      '  Notification access: '
          '${notificationAccess == null ? 'not checked' : yn(notificationAccess!)}',
      '',
      'Library',
      '  Songs: $songs',
      '  Favorites: $favorites',
      '  Playlists: $playlists',
    ];
    return lines.join('\n');
  }
}

Future<List<String>> _localAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLinkLocal) a.address,
    ];
  } catch (_) {
    return const [];
  }
}

final diagnosticsProvider = FutureProvider.autoDispose<DiagnosticsInfo>((ref) async {
  final db = ref.watch(databaseProvider);
  final settings = await ref.watch(settingsRepositoryProvider).load();
  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('c');

  bool? access;
  if (settings.externalAppControlEnabled) {
    try {
      access = await ref.read(externalMediaBridgeProvider).isAccessGranted();
    } catch (_) {
      access = null;
    }
  }
  final trusted =
      await count('SELECT COUNT(*) AS c FROM paired_controllers WHERE trusted = 1');

  return DiagnosticsInfo(
    appVersion: AppConstants.appVersion,
    protocolVersion: AppConstants.protocolVersion,
    platform: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    schemaVersion: db.schemaVersion,
    connectionMode: settings.connectionMode.name,
    onlineRelayEnabled: settings.onlineRelayEnabled,
    onlineKeysSet: (settings.supabaseUrl ?? '').trim().isNotEmpty &&
        (settings.supabaseAnonKey ?? '').trim().isNotEmpty,
    externalControlEnabled: settings.externalAppControlEnabled,
    notificationAccess: access,
    port: settings.lastPlayerPort,
    addresses: await _localAddresses(),
    songs: await count('SELECT COUNT(*) AS c FROM songs'),
    favorites: await count('SELECT COUNT(*) AS c FROM songs WHERE favorite = 1'),
    playlists: await count('SELECT COUNT(*) AS c FROM playlists'),
    trustedControllers: trusted,
  );
});

/// A read-only status page with a Copy button, for when something does not
/// work and you need to tell someone what this phone looks like.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(diagnosticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(diagnosticsProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text("Couldn't read the diagnostics.", textAlign: TextAlign.center),
            ),
          ),
          data: (info) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'This has no passwords, keys, room codes or file names. '
                'Copy it to share when you ask for help.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    info.toReport(),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFamily: 'monospace', height: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: info.toReport()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('Copied')));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
