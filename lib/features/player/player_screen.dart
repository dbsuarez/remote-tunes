import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/pairing_qr.dart';
import '../../providers/library_providers.dart';
import 'local_now_playing.dart';

import '../../core/models/enums.dart';
import '../../core/online/room_code.dart';
import '../../core/router/app_router.dart';
import '../online/online_status.dart';
import '../../providers/providers.dart';
import '../../providers/shell_providers.dart';
import '../external/external_limits.dart';
import '../library/import_actions.dart';
import 'playback_engine.dart';
import '../../core/protocol/protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/playback_widgets.dart';
import '../../core/widgets/status_pill.dart';
import '../../providers/connection_providers.dart';
import 'server/player_server.dart';

/// Player dashboard: runs the local server while this screen is open.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    // Android 13+ needs permission to show the media notification. Playback
    // works without it, so a "no" is fine.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(permissionsProvider).ensureNotifications();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(playerServerStateProvider);
    final playback = ref.watch(playerPlaybackProvider);
    final host = ref.watch(playerHostProvider).valueOrNull;
    // Set when online was wanted (Online only) but isn't set up yet.
    final onlineProblem = host?.onlineProblem;
    // Only offered if the user turned External App Control on in Settings.
    final showExternal = host?.controlEngine?.externalAvailable ?? false;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Player'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Player'),
              Tab(text: 'Connect'),
              Tab(text: 'Music'),
            ],
          ),
        ),
        body: SafeArea(
          child: server.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const _Message(
              'The Player could not start. Go back and try again.',
            ),
            data: (s) => Column(
              children: [
                // Always visible, whatever tab is open: who is connected, any
                // problem, and a pairing request that needs an answer.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _StatusPill(state: s),
                        ),
                        if (s.error != null) ...[
                          const SizedBox(height: 12),
                          _ErrorCard(s.error!),
                        ],
                        if (s.pending != null) ...[
                          const SizedBox(height: 12),
                          _PairingCard(info: s.pending!),
                        ],
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Player: what is playing, and its controls (the same
                      // screen as on the Controller).
                      if (host?.queueEngine != null && host?.server.library != null)
                        LocalNowPlaying(
                          engine: host!.queueEngine!,
                          library: host.server.library!,
                          sleepTimer: host.server.sleepTimer,
                          header: showExternal ? const _ExternalCard() : null,
                        )
                      else
                        ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          children: [
                            playback.when(
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                              data: (p) => _LocalPlayer(state: p),
                            ),
                            if (showExternal) ...[
                              const SizedBox(height: 16),
                              const _ExternalCard(),
                            ],
                          ],
                        ),
                      // Connect: everything about how Controllers reach this phone.
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          if (onlineProblem != null) ...[
                            _ErrorCard(onlineProblem),
                            const SizedBox(height: 16),
                          ],
                          if (s.pending == null &&
                              s.running &&
                              s.pairingTicket != null &&
                              !(s.controller?.connected ?? false)) ...[
                            _QrCard(state: s),
                            const SizedBox(height: 16),
                          ],
                          if (s.controller != null) ...[
                            _ControllerCard(info: s.controller!),
                            const SizedBox(height: 16),
                          ],
                          if (s.online != null) ...[
                            _OnlineCard(info: s.online!),
                            const SizedBox(height: 16),
                          ],
                          if (s.running && s.port != null) ...[
                            _ConnectCard(state: s),
                            const SizedBox(height: 16),
                          ],
                          if (s.trusted.isNotEmpty) _TrustedCard(devices: s.trusted),
                        ],
                      ),
                      // Music: add songs, open the library and queue.
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: const [
                          _MusicActions(),
                          SizedBox(height: 16),
                          _InfoNote(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});
  final PlayerServerState state;

  @override
  Widget build(BuildContext context) {
    if (!state.running) {
      return StatusPill(
        label: state.error != null ? 'Not running' : 'Starting…',
        color: RtColors.warning,
        icon: Icons.error_outline_rounded,
      );
    }
    final c = state.controller;
    if (c != null && c.connected) {
      final online = c.connectionType == ConnectionType.online;
      return StatusPill(
        label: 'Controller connected: ${c.name} · ${online ? 'Online' : 'Local'}',
        color: online ? RtColors.violet : RtColors.teal,
        icon: online ? Icons.public_rounded : Icons.link_rounded,
      );
    }
    if (c != null) {
      return StatusPill(
        label: '${c.name} offline · waiting to reconnect',
        color: RtColors.warning,
        icon: Icons.sync_problem_rounded,
      );
    }
    // Online only: the local network is not open.
    if (state.port == null) {
      final connected = state.online?.isConnected ?? false;
      return StatusPill(
        label: connected
            ? 'Online · waiting for a Controller'
            : 'Getting online…',
        color: connected ? RtColors.violet : RtColors.warning,
        icon: connected ? Icons.public_rounded : Icons.sync_rounded,
      );
    }
    return const StatusPill(
      label: 'Ready · waiting for a Controller',
      color: RtColors.teal,
      icon: Icons.wifi_tethering_rounded,
    );
  }
}

/// Controllers that may reconnect without pairing. Forget one to make it pair
/// again (for example a lost phone).
class _TrustedCard extends ConsumerWidget {
  const _TrustedCard({required this.devices});
  final List<TrustedDeviceInfo> devices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final server = ref.read(playerHostProvider).valueOrNull?.server;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trusted Controllers', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'These phones can reconnect without pairing. Forget a phone to '
              'make it pair again.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            for (final d in devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 56,
                leading: const Icon(Icons.verified_user_rounded, color: RtColors.teal),
                title: Text(d.name),
                trailing: TextButton(
                  onPressed: () => server?.forgetTrusted(d.sessionId),
                  child: const Text('Forget'),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await server?.forgetAllTrusted();
                  // A new room code too, in case the old one was shared.
                  await ref.read(settingsRepositoryProvider).clearPlayerRoomCode();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Forgot all. A new room code is made next time the Player starts.')));
                  }
                },
                child: const Text('Forget all'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// QR code a Controller scans to connect without typing.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.state});
  final PlayerServerState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final port = state.port;
    final room = state.online?.roomCode;
    final hasLocal = port != null && state.addresses.isNotEmpty;
    if (!hasLocal && room == null) return const SizedBox.shrink();
    final data = PairingQr(
      ticket: state.pairingTicket!,
      host: hasLocal ? state.addresses.first : null,
      port: hasLocal ? port : null,
      roomCode: room,
    ).encode();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Scan to connect', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Semantics(
              label: 'Pairing QR code. Scan it with the RemoteTunes app or a phone camera.',
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: data,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'In the RemoteTunes app choose Scan QR code. Or point any phone '
              'camera at it to open the web Controller (needs online mode). '
              'Then tap Accept here. It works once and refreshes itself.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// The online room: code to share, and whether the relay is connected.
class _OnlineCard extends StatelessWidget {
  const _OnlineCard({required this.info});

  final OnlineRelayInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (info.phase) {
      OnlinePhase.connected => ('Online relay connected', RtColors.violet, Icons.cloud_done_rounded),
      OnlinePhase.connecting => ('Connecting to the online relay…', RtColors.warning, Icons.cloud_sync_rounded),
      OnlinePhase.reconnecting => ('Reconnecting to the online relay…', RtColors.warning, Icons.cloud_sync_rounded),
      OnlinePhase.failed => ('Not connected to the online relay', theme.colorScheme.error, Icons.cloud_off_rounded),
    };

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: RtColors.violet.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: theme.textTheme.titleSmall?.copyWith(color: color))),
              ],
            ),
            if (info.error != null) ...[
              const SizedBox(height: 4),
              Text(
                info.phase == OnlinePhase.failed
                    ? '${info.error} Trying again automatically.'
                    : info.error!,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Text('Room code', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Room code ${info.roomCode.split('').join(' ')}',
                    child: SelectableText(
                      RoomCode.format(info.roomCode),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        letterSpacing: 4,
                        fontWeight: FontWeight.w600,
                        color: RtColors.violet,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy room code',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: info.roomCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Room code copied')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'On the Controller, choose Online (or Auto) and enter this code. '
              'It changes every time the Player starts. Only playback '
              'commands and status pass through the online relay: your music '
              'never leaves this phone.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _PairingCard extends ConsumerWidget {
  const _PairingCard({required this.info});
  final PendingPairingInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final server = ref.read(playerHostProvider).valueOrNull?.server;
    final remaining = info.expiresAt.difference(DateTime.now());
    final minutes = remaining.inMinutes.clamp(0, 99);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pairing request', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${info.controllerName} wants to control this Player.'),
            Text(
              '${info.address} · ${info.connectionType == ConnectionType.local ? 'Local' : 'Online'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (info.replacesController != null) ...[
              const SizedBox(height: 8),
              Text(
                'Accepting will disconnect ${info.replacesController}.',
                style: const TextStyle(color: RtColors.warning),
              ),
            ],
            const SizedBox(height: 16),
            Center(
              child: Semantics(
                label: 'Pairing code ${info.code.split('').join(' ')}',
                child: Text(
                  info.code,
                  style: theme.textTheme.displayMedium?.copyWith(
                    letterSpacing: 8,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                'Enter this code on the Controller. Valid for about $minutes min.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
            if (info.codeVerified) ...[
              const SizedBox(height: 8),
              const Center(child: Text('The Controller entered the right code.')),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: server?.rejectPairing,
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: server?.acceptPairing,
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.state});
  final PlayerServerState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final port = state.port;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect from the Controller',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (state.addresses.isEmpty)
              Text(
                'No network address found. Connect to Wi‑Fi or turn on the '
                'hotspot, then reopen this screen.',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else ...[
              Text(
                'On the Controller, choose this phone from the list, or enter '
                'one of these addresses manually:',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              for (final a in state.addresses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 48,
                  title: SelectableText('$a : $port',
                      style: theme.textTheme.titleMedium),
                  trailing: IconButton(
                    tooltip: 'Copy address',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '$a:$port'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Address copied')),
                      );
                    },
                  ),
                ),
            ],
            if (state.advertisingWarning != null) ...[
              const SizedBox(height: 8),
              Text(
                state.advertisingWarning!,
                style: const TextStyle(color: RtColors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ControllerCard extends ConsumerWidget {
  const _ControllerCard({required this.info});
  final ControllerInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.read(playerHostProvider).valueOrNull?.server;
    return Card(
      child: ListTile(
        minTileHeight: 64,
        leading: Icon(
          info.connected ? Icons.link_rounded : Icons.link_off_rounded,
          color: info.connected ? RtColors.teal : RtColors.warning,
        ),
        title: Text(info.name),
        subtitle: Text(
          '${info.address} · ${info.connected ? 'Connected' : 'Offline, may reconnect'}',
        ),
        trailing: TextButton(
          onPressed: server?.disconnectController,
          child: const Text('Disconnect'),
        ),
      ),
    );
  }
}

class _LocalPlayer extends ConsumerWidget {
  const _LocalPlayer({required this.state});
  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(playerHostProvider).valueOrNull?.engine;
    return Column(
      children: [
        NowPlayingCard(
          state: state,
          onSeek: engine == null ? null : (s) => engine.seek(s),
        ),
        const SizedBox(height: 8),
        TransportControls(
          canSkip: state.canSkip,
          isPlaying: state.isPlaying,
          enabled: engine != null,
          onPrevious: () => engine?.previous(),
          onToggle: () => engine?.toggle(),
          onNext: () => engine?.next(),
        ),
        const SizedBox(height: 8),
        VolumeSlider(
          volume: state.volume,
          enabled: engine != null,
          onChanged: (v) => engine?.setVolume(v),
        ),
      ],
    );
  }
}

/// Add music, and open the Library and Queue.
class _MusicActions extends ConsumerWidget {
  const _MusicActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your music', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => pickAndImportFiles(context, ref),
                    icon: const Icon(Icons.library_add_rounded),
                    label: const Text('Add songs'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => pickAndImportFolder(context, ref),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Add folder'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => context.push(AppRoutes.playerLibrary),
                    icon: const Icon(Icons.library_music_rounded),
                    label: const Text('Library'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => context.push(AppRoutes.playerQueue),
                    icon: const Icon(Icons.queue_music_rounded),
                    label: const Text('Queue'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => context.push(AppRoutes.playerUrl),
                icon: const Icon(Icons.public_rounded),
                label: const Text('Play URL'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Music keeps playing, and Controllers keep working, with the screen '
          'off or another app open, as long as you stay in Player mode. '
          'Leaving this screen or closing the app stops the Player.',
          style: style,
        ),
        const SizedBox(height: 8),
        Text(
          'If playback stops or Controllers disconnect on Infinix/XOS phones: '
          'open Settings → Battery (or App management) → RemoteTunes and allow '
          'background activity / turn off battery optimization for this app.',
          style: style,
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text)));
}

/// Player: choose between RemoteTunes' own player and another music app, and
/// set up the Notification access that needs.
class _ExternalCard extends ConsumerStatefulWidget {
  const _ExternalCard();

  @override
  ConsumerState<_ExternalCard> createState() => _ExternalCardState();
}

class _ExternalCardState extends ConsumerState<_ExternalCard>
    with WidgetsBindingObserver {
  bool? _granted;
  int _sdk = 0;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's settings: check whether access was granted.
    if (state == AppLifecycleState.resumed) _refreshAccess();
  }

  Future<void> _refreshAccess() async {
    try {
      final bridge = ref.read(externalMediaBridgeProvider);
      final granted = await bridge.isAccessGranted();
      final sdk = await bridge.sdkInt();
      if (mounted) {
        setState(() {
          _granted = granted;
          _sdk = sdk;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _granted = false);
    }
  }

  Future<void> _switch(ControlMode mode) async {
    final engine = ref.read(playerHostProvider).valueOrNull?.controlEngine;
    if (engine == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await engine.setControlMode(mode);
    } on PlaybackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      await _refreshAccess();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't open Android's settings. Open them "
            'yourself: Settings → Notifications → Notification access.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bridge = ref.read(externalMediaBridgeProvider);
    final engine = ref.watch(playerHostProvider).valueOrNull?.controlEngine;
    // Rebuild when the playback state (including the mode) changes.
    final playback = ref.watch(playerPlaybackProvider).valueOrNull;
    final mode = engine?.controlMode ?? ControlMode.local;
    final external = mode == ControlMode.external;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: external ? RtColors.violet : theme.colorScheme.outline,
          width: external ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.open_in_new_rounded, color: RtColors.violet),
                const SizedBox(width: 8),
                Text('External App Control', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Control Spotify, YouTube Music or another music app on this '
              'phone from a Controller.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ControlMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ControlMode.local, label: Text('RemoteTunes')),
                  ButtonSegment(value: ControlMode.external, label: Text('Other music app')),
                ],
                selected: {mode},
                onSelectionChanged: _busy ? null : (s) => _switch(s.first),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_granted == false) ...[
              const SizedBox(height: 12),
              _AccessSteps(
                showRestrictedHint: _sdk >= 33,
                onOpenAccess: () => _open(bridge.openAccessSettings),
                onOpenAppInfo: () => _open(bridge.openAppInfo),
                onRecheck: _refreshAccess,
              ),
            ],
            if (external && _granted == true) ...[
              const SizedBox(height: 12),
              Text(
                playback != null && playback.externalApp.isNotEmpty
                    ? 'Controlling ${playback.externalApp}.'
                    : 'Waiting for a music app. Start playing something in '
                        'Spotify or YouTube Music on this phone.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              externalLimitsText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// How to give RemoteTunes Notification access, in plain steps.
class _AccessSteps extends StatelessWidget {
  const _AccessSteps({
    required this.showRestrictedHint,
    required this.onOpenAccess,
    required this.onOpenAppInfo,
    required this.onRecheck,
  });

  final bool showRestrictedHint;
  final VoidCallback onOpenAccess;
  final VoidCallback onOpenAppInfo;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RtColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RtColors.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Allow Notification access', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'Android only lets an app control other music apps if you allow '
            '"Notification access". RemoteTunes uses it only to see which '
            'music app is playing and to press play, pause, next and previous. '
            'It never reads your notifications or messages.',
            style: theme.textTheme.bodySmall,
          ),
          if (showRestrictedHint) ...[
            const SizedBox(height: 8),
            Text(
              'On Android 13 and newer, an app installed outside the Play Store '
              'has this switch greyed out. First open App info, tap the ⋮ menu '
              'at the top right, and choose "Allow restricted settings".',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (showRestrictedHint)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onOpenAppInfo,
                  child: const Text('Open App info'),
                ),
              FilledButton(
                onPressed: onOpenAccess,
                child: const Text('Allow notification access'),
              ),
              TextButton(
                onPressed: onRecheck,
                child: const Text("I've allowed it"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Everything about letting other phones control this one: start and stop it,
/// who is connected, the QR code and pairing requests, and the online room.
class RemotePlaybackScreen extends ConsumerWidget {
  const RemotePlaybackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(remotePlaybackProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Remote playback')),
      body: SafeArea(child: on ? const _RemoteOn() : const _RemoteOff()),
    );
  }
}

class _RemoteOff extends ConsumerWidget {
  const _RemoteOff();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remote playback is off', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'While it is off this phone only plays its own music and nothing '
                  'listens on the network. Start it to let another phone (or the '
                  'web page) control what plays here.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.read(remotePlaybackProvider.notifier).state = true,
                  icon: const Icon(Icons.cast_connected_rounded),
                  label: const Text('Start remote playback'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RemoteOn extends ConsumerWidget {
  const _RemoteOn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(playerServerStateProvider);
    final host = ref.watch(playerHostProvider).valueOrNull;
    final onlineProblem = host?.onlineProblem;
    final showExternal = host?.controlEngine?.externalAvailable ?? false;
    return server.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const _Message('Remote playback could not start. Try again.'),
      data: (s) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(alignment: Alignment.centerLeft, child: _StatusPill(state: s)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => ref.read(remotePlaybackProvider.notifier).state = false,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop remote playback'),
          ),
          const SizedBox(height: 16),
          if (s.error != null) ...[
            _ErrorCard(s.error!),
            const SizedBox(height: 16),
          ],
          if (s.pending != null) ...[
            _PairingCard(info: s.pending!),
            const SizedBox(height: 16),
          ],
          if (onlineProblem != null) ...[
            _ErrorCard(onlineProblem),
            const SizedBox(height: 16),
          ],
          if (s.pending == null &&
              s.running &&
              s.pairingTicket != null &&
              !(s.controller?.connected ?? false)) ...[
            _QrCard(state: s),
            const SizedBox(height: 16),
          ],
          if (s.controller != null) ...[
            _ControllerCard(info: s.controller!),
            const SizedBox(height: 16),
          ],
          if (s.online != null) ...[
            _OnlineCard(info: s.online!),
            const SizedBox(height: 16),
          ],
          if (s.running && s.port != null) ...[
            _ConnectCard(state: s),
            const SizedBox(height: 16),
          ],
          if (s.trusted.isNotEmpty) ...[
            _TrustedCard(devices: s.trusted),
            const SizedBox(height: 16),
          ],
          if (showExternal) const _ExternalCard(),
        ],
      ),
    );
  }
}
