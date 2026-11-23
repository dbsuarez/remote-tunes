import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/models/enums.dart';
import '../../core/protocol/protocol.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/playback_widgets.dart';
import '../../core/widgets/status_pill.dart';
import '../external/external_limits.dart';
import '../music/music_browser.dart';
import '../music/music_source.dart';
import '../music/queue_view.dart';
import '../music/url_player_view.dart';
import 'controller_client.dart';

// Controller screens shared by the phone app and the web Controller. Nothing in
// this file may import phone-only code (database, audio, discovery, dart:ffi):
// test/web_safety_test.dart enforces that.

// ------------------------------------------------------------------- Code view

class CodeEntryView extends StatefulWidget {
  const CodeEntryView({super.key, required this.client, required this.state});

  final ControllerClient client;
  final ControllerClientState state;

  @override
  State<CodeEntryView> createState() => _CodeEntryViewState();
}

class _CodeEntryViewState extends State<CodeEntryView> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.submitCode(_code.text);
    } on ControllerException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        _code.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.state.playerName ?? widget.state.host ?? 'the Player';
    final waiting = widget.state.status == ControllerStatus.waitingForPlayer;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Pair with $name', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit code shown on the Player screen. The Player must '
          'also tap Accept.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        if (waiting) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text('Code accepted. Waiting for $name to tap Accept…'),
        ] else ...[
          TextField(
            controller: _code,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '------',
              counterText: '',
              errorText: _error,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_code.text.length == 6) _submit();
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_code.text.length == 6 && !_busy) ? _submit : null,
            child: const Text('Pair'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => widget.client.disconnect(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- Dashboard

/// Connected Controller: status pill + tabs (Now Playing, Queue, Library, URL).
class ControllerDashboard extends StatelessWidget {
  const ControllerDashboard({super.key, required this.client, required this.state});

  final ControllerClient client;
  final ControllerClientState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reconnecting = state.status == ControllerStatus.reconnecting;
    final enabled = state.isConnected;
    final p = state.playback;
    final player = state.playerName ?? state.host ?? 'Player';
    final source = RemoteMusicSource(client);

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(
                  label: reconnecting
                      ? 'Reconnecting to $player…'
                      : 'Connected to $player · ${state.route == ConnectionType.online ? 'Online' : 'Local'}',
                  // Online has its own colour (violet), as the guardrails ask.
                  color: reconnecting
                      ? RtColors.warning
                      : (state.route == ConnectionType.online
                          ? RtColors.violet
                          : RtColors.teal),
                  icon: reconnecting
                      ? Icons.sync_rounded
                      : (state.route == ConnectionType.online
                          ? Icons.public_rounded
                          : Icons.link_rounded),
                ),
                if (reconnecting) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Connection lost. Trying to reconnect. Controls '
                              'are paused until the Player is back.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Now Playing'),
              Tab(text: 'Queue'),
              Tab(text: 'Library'),
              Tab(text: 'URL'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _NowPlayingTab(client: client, state: state),
                _KeepAlive(
                  child: p.isExternal
                      ? _ExternalNotice(app: p.externalApp)
                      : QueueView(
                          source: source,
                          revision: p.queueRevision,
                          currentIndex: p.queueLength > 0 ? p.queueIndex : -1,
                          shuffle: p.shuffleEnabled,
                          repeat: p.repeatMode,
                          enabled: enabled,
                        ),
                ),
                _KeepAlive(
                  child: p.isExternal
                      ? _ExternalNotice(app: p.externalApp)
                      : MusicBrowser(
                          source: source,
                          enabled: enabled,
                          emptyMessage:
                              "The Player's library is empty.\nOn the Player, tap Add songs or Add folder.",
                        ),
                ),
                _KeepAlive(
                  child: p.isExternal
                      ? _ExternalNotice(app: p.externalApp)
                      : UrlPlayerView(
                          enabled: enabled,
                          target: 'the Player',
                          initialUrl: AppConstants.sampleAudioUrl,
                          onPlay: (url, title) => client.playUrl(url, title: title),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps a tab's state (scroll position, search text) while switching tabs.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _NowPlayingTab extends StatelessWidget {
  const _NowPlayingTab({required this.client, required this.state});

  final ControllerClient client;
  final ControllerClientState state;

  Future<void> _send(
    BuildContext context,
    String action, [
    Map<String, dynamic> params = const {},
  ]) async {
    try {
      await client.sendCommand(action, params);
    } on ControllerException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _switchMode(BuildContext context, ControlMode mode) async {
    try {
      await client.setControlMode(mode);
    } on ControllerException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = state.isConnected;
    final p = state.playback;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Only offered when the Player turned External App Control on.
        if (p.externalEnabled) ...[
          _ControlModeSwitch(
            external: p.isExternal,
            enabled: enabled,
            onChanged: (mode) => _switchMode(context, mode),
          ),
          const SizedBox(height: 12),
        ],
        NowPlayingCard(
          state: p,
          enabled: enabled,
          onSeek: (s) => _send(context, RemoteActions.seek, {'positionSeconds': s}),
        ),
        const SizedBox(height: 8),
        TransportControls(
          canSkip: p.canSkip,
          isPlaying: p.isPlaying,
          enabled: enabled,
          onPrevious: () => _send(context, RemoteActions.previous),
          onToggle: () => _send(context, RemoteActions.toggle),
          onNext: () => _send(context, RemoteActions.next),
        ),
        const SizedBox(height: 8),
        VolumeSlider(
          volume: p.volume,
          enabled: enabled,
          onChanged: (v) => _send(context, RemoteActions.setVolume, {'volume': v}),
        ),
      ],
    );
  }
}

/// Switch between RemoteTunes' own player and another music app on the Player
/// phone. Only shown when the Player has External App Control turned on.
class _ControlModeSwitch extends StatelessWidget {
  const _ControlModeSwitch({
    required this.external,
    required this.enabled,
    required this.onChanged,
  });

  final bool external;
  final bool enabled;
  final ValueChanged<ControlMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ControlMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ControlMode.local, label: Text('RemoteTunes')),
              ButtonSegment(value: ControlMode.external, label: Text('Other music app')),
            ],
            selected: {external ? ControlMode.external : ControlMode.local},
            onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
          ),
        ),
        if (external) ...[
          const SizedBox(height: 8),
          Text(
            externalLimitsText,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Shown instead of the Queue, Library and URL tabs while another app is being
/// controlled (they only exist for RemoteTunes' own player).
class _ExternalNotice extends StatelessWidget {
  const _ExternalNotice({required this.app});

  final String app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new_rounded, size: 40, color: RtColors.violet),
            const SizedBox(height: 12),
            Text(
              'Not available while controlling ${app.isEmpty ? 'another app' : app}',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The queue, library and links belong to RemoteTunes\' own player. '
              'Open the Now Playing tab and switch back to RemoteTunes to use them.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
