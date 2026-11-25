import '../player/playback_log.dart';
import '../update/update_controller.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:record/record.dart';

import '../../core/constants.dart';
import '../../data/repositories/online_history_repository.dart';
import '../../providers/connection_providers.dart';
import '../../providers/providers.dart';
import '../group/group_models.dart';
import '../group/group_native.dart';
import '../group/group_providers.dart';
import '../online_library/jamendo_key_store.dart';

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
    this.jamendoClientIdSet = false,
    this.onlineHistoryEnabled = true,
    this.onlineHistoryCount = 0,
    this.savedQueueSongs = 0,
    this.savedQueueStreams = 0,
    this.outputRoute = 'unknown',
    this.outputLatencyMs,
    this.microphonePermission,
    this.group,
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

  // Online Library and the queue (never the Jamendo ID itself).
  final bool jamendoClientIdSet;
  final bool onlineHistoryEnabled;
  final int onlineHistoryCount;
  final int savedQueueSongs;
  final int savedQueueStreams;

  // Group play.
  /// Where the sound goes right now: speaker, wired, bluetooth, unknown.
  final String outputRoute;

  /// The phone's own estimate of its audio delay, when it tells.
  final int? outputLatencyMs;

  /// Null if it could not be checked.
  final bool? microphonePermission;

  /// What group play is doing right now; null when this phone is not playing
  /// along (the normal state).
  final GroupStatus? group;

  List<String> _groupLines() {
    final g = group;
    if (g == null) return ['  Playing along: no'];
    String ms(double? v) => v == null ? 'n/a' : '${v.toStringAsFixed(1)} ms';
    return [
      '  Playing along: ${g.phase.name}${g.message.isEmpty ? '' : ' (${g.message})'}',
      '  Off by (this phone vs Player): ${ms(g.driftMs)}',
      '  Round trip: ${ms(g.rttMs)}',
      '  Clock spread: ${ms(g.spreadMs)}',
      '  Clock offset: ${ms(g.offsetMs)}',
      '  Fine-tune (${g.route}): ${g.nudgeMs} ms',
      if (g.warning.isNotEmpty) '  Warning: ${g.warning.replaceAll('\n', ' ')}',
      if (g.calibration.isNotEmpty) '  Last Auto-align: ${g.calibration}',
    ];
  }

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
      '  Saved queue: $savedQueueSongs songs, $savedQueueStreams internet tracks',
      '',
      'Online Library',
      '  Jamendo client ID set: ${yn(jamendoClientIdSet)}',
      '  History: ${onlineHistoryEnabled ? 'on' : 'off'}, $onlineHistoryCount entries',
      '',
      'Group play',
      '  Sound output: $outputRoute',
      '  Phone\'s own audio delay: ${outputLatencyMs == null ? 'not reported' : '$outputLatencyMs ms'}',
      '  Microphone permission (Auto-align): '
          '${microphonePermission == null ? 'unknown' : yn(microphonePermission!)}',
      ..._groupLines(),
      '',
      'Playback log (song changes, newest last)',
      if (PlaybackLog.lines.isEmpty) '  nothing yet' else ...[for (final l in PlaybackLog.lines) '  $l'],
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

  final native = MethodChannelGroupNative();
  bool? mic;
  try {
    mic = await AudioRecorder().hasPermission(request: false);
  } catch (_) {
    mic = null;
  }
  final jamendo = await PrefsJamendoKeyStore().load();
  final history = OnlineHistoryRepository(db);

  return DiagnosticsInfo(
    jamendoClientIdSet: jamendo != null,
    onlineHistoryEnabled: await history.isEnabled(),
    onlineHistoryCount: await count('SELECT COUNT(*) AS c FROM online_history'),
    savedQueueSongs: await count('SELECT COUNT(*) AS c FROM queue_items'),
    savedQueueStreams: await count('SELECT COUNT(*) AS c FROM queue_streams'),
    outputRoute: await native.outputRoute(),
    outputLatencyMs: await native.outputLatencyMs(),
    microphonePermission: mic,
    group: ref.read(groupFollowerProvider)?.status.isOn == true
        ? ref.read(groupFollowerProvider)!.status
        : null,
    // The installed app's own version (the constant only says what the source had).
    appVersion: (await ref.read(installedAppProvider.future).catchError((Object _) => null))
            ?.short ??
        AppConstants.appVersion,
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
