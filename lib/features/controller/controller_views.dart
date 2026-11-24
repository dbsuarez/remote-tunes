import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/models/enums.dart';
import '../../core/haptics.dart';
import '../../core/protocol/protocol.dart';
import '../../core/song_list_style.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/accent_scope.dart';
import '../../core/widgets/haptic_button.dart';
import '../../core/widgets/playback_widgets.dart';
import '../../core/widgets/status_pill.dart';
import '../external/external_limits.dart';
import '../online_library/online_history_source.dart';
import '../online_library/online_library_view.dart';
import '../group/group_card.dart';
import '../music/music_browser.dart';
import '../../core/widgets/edge_swipe.dart';
import '../music/lyrics_view.dart';
import '../music/queue_peek.dart';
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
      length: 5,
      // The playing song's cover tints the whole Controller (when it has one).
      child: AccentScope(
        songId: p.isExternal ? null : p.songId,
        loadArt: (id) => client.artFor(id, size: 96),
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
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Now Playing'),
              Tab(text: 'Queue'),
              Tab(text: 'Library'),
              Tab(text: 'URL'),
              Tab(text: 'Online'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _NowPlayingTab(client: client, state: state, source: source),
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
                      : Consumer(
                          builder: (context, ref, _) => MusicBrowser(
                            source: source,
                            size: ref.watch(songListSizeProvider),
                            enabled: enabled,
                            emptyMessage:
                                "The Player's library is empty.\nOn the Player, tap Add songs or Add folder.",
                          ),
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
                _KeepAlive(
                  child: p.isExternal
                      ? _ExternalNotice(app: p.externalApp)
                      : OnlineLibraryView(
                          enabled: enabled,
                          history: ClientHistorySource(client),
                          // The Player streams the track itself: only the link
                          // and the title go to it.
                          onTrack: (t, {required queue}) => client.playUrl(
                            t.audioUrl,
                            title: t.title,
                            artist: t.artist,
                            album: t.album,
                            licenseUrl: t.licenseUrl,
                            imageUrl: t.imageUrl,
                            queue: queue,
                          ),
                        ),
                ),
              ],
            ),
          ),
          // Controls stay reachable on every tab, so there is no scrolling
          // back to Now Playing to pause or skip.
          Builder(builder: (context) {
            final tabs = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tabs,
              builder: (context, _) => tabs.index == 0
                  ? const SizedBox.shrink()
                  : _MiniControls(
                      client: client,
                      state: state,
                      onOpen: () => tabs.animateTo(0),
                    ),
            );
          }),
        ],
        ),
      ),
    );
  }
}

/// Compact title + previous / play-pause / next, shown under every tab except
/// Now Playing.
class _MiniControls extends StatelessWidget {
  const _MiniControls({
    required this.client,
    required this.state,
    required this.onOpen,
  });

  final ControllerClient client;
  final ControllerClientState state;
  final VoidCallback onOpen;

  Future<void> _send(BuildContext context, String action) async {
    try {
      await client.sendCommand(action);
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
    final theme = Theme.of(context);
    final p = state.playback;
    final enabled = state.isConnected;
    final title = p.title.isEmpty ? 'Nothing playing' : p.title;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    RemoteArt(
                        client: client,
                        songId: p.isExternal || (p.songId ?? 0) <= 0 ? null : p.songId,
                        size: 44),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                      if (p.artist.isNotEmpty)
                        Text(p.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  )),
                  ]),
                ),
              ),
            ),
            HapticButton(
              kind: HapticKind.light,
              tooltip: 'Previous',
              iconSize: 28,
              onPressed: enabled && p.canSkip ? () => _send(context, RemoteActions.previous) : null,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            HapticButton(
              kind: HapticKind.medium,
              filled: true,
              tooltip: p.isPlaying ? 'Pause' : 'Play',
              iconSize: 28,
              onPressed: enabled ? () => _send(context, RemoteActions.toggle) : null,
              icon: Icon(p.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            HapticButton(
              kind: HapticKind.light,
              tooltip: 'Next',
              iconSize: 28,
              onPressed: enabled && p.canSkip ? () => _send(context, RemoteActions.next) : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
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

class _NowPlayingTab extends StatefulWidget {
  const _NowPlayingTab({required this.client, required this.state, required this.source});

  final ControllerClient client;
  final ControllerClientState state;

  /// The queue, for the peek sheet.
  final MusicSource source;

  @override
  State<_NowPlayingTab> createState() => _NowPlayingTabState();
}

class _NowPlayingTabState extends State<_NowPlayingTab> {
  final DraggableScrollableController _sheet = DraggableScrollableController();

  ControllerClient get client => widget.client;
  ControllerClientState get state => widget.state;
  MusicSource get source => widget.source;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  /// A swipe in from the right edge raises the queue: first to the middle, then
  /// all the way up.
  void _raiseQueue() {
    if (!_sheet.isAttached) return;
    final mid = QueuePeekSheet.midSize;
    final target = _sheet.size < mid - 0.03 ? mid : QueuePeekSheet.fullSize;
    _sheet.animateTo(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// A swipe in from the left edge opens the Library.
  void _openLibrary() => DefaultTabController.of(context).animateTo(2);

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

    // The queue peek rests along the bottom; the page scrolls clear of it.
    return LayoutBuilder(builder: (context, box) {
      final peekSpace = p.isExternal ? 0.0 : box.maxHeight * QueuePeekSheet.peekSize + 12;
      return EdgeSwipe(
        enabled: enabled,
        onFromLeft: _openLibrary,
        onFromRight: p.isExternal ? null : _raiseQueue,
        child: Stack(
        children: [
          ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + peekSpace),
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
          art: RemoteArt(
              client: client,
              songId: p.isExternal || (p.songId ?? 0) <= 0 ? null : p.songId,
              size: 64),
          trailing: p.songId == null || p.songId! <= 0 || p.isExternal
              ? null
              : HapticButton(
                  kind: HapticKind.selection,
                  tooltip: p.favorite ? 'Remove from favorites' : 'Add to favorites',
                  onPressed: enabled
                      ? () => _send(context, RemoteActions.setFavorite,
                          {'songId': p.songId, 'favorite': !p.favorite})
                      : null,
                  icon: Icon(
                    p.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: p.favorite ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
        ),
        if (!p.isExternal)
          LyricsSection(
            songId: p.songId,
            positionSeconds: p.positionSeconds,
            isPlaying: p.isPlaying,
            enabled: enabled,
            fetch: source.lyrics,
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
        if (!p.isExternal) ...[
          const SizedBox(height: 8),
          _SpeedRow(
            speed: p.speed,
            enabled: enabled,
            onSet: (v) => _send(context, RemoteActions.setSpeed, {'speed': v}),
          ),
        ],
        const SizedBox(height: 8),
        _SleepTimerRow(
          secondsLeft: p.sleepTimerSeconds,
          enabled: enabled,
          onSet: (m) => _send(context, RemoteActions.setSleepTimer, {'minutes': m}),
        ),
        // Only on the phone app: this phone plays the same song, in sync.
        if (!p.isExternal) GroupCard(enabled: enabled),
      ],
          ),
          if (!p.isExternal)
            Positioned.fill(
              child: QueuePeekSheet(
                controller: _sheet,
                source: source,
                revision: p.queueRevision,
                currentIndex: p.queueIndex,
                enabled: enabled,
              ),
            ),
        ],
        ),
      );
    });
  }
}

/// Playback speed picker (0.5x to 2x).
class _SpeedRow extends StatelessWidget {
  const _SpeedRow({required this.speed, required this.enabled, required this.onSet});

  final double speed;
  final bool enabled;
  final ValueChanged<double> onSet;

  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static String label(double v) =>
      '${v.toString().replaceAll(RegExp(r'\.0$'), '')}\u00d7';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = speed != 1.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.speed_rounded,
                color: changed ? RtColors.violet : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(changed ? 'Speed ${label(speed)}' : 'Speed',
                  style: theme.textTheme.titleSmall),
            ),
            PopupMenuButton<double>(
              tooltip: 'Set playback speed',
              enabled: enabled,
              onSelected: onSet,
              itemBuilder: (_) => [
                for (final v in speeds)
                  CheckedPopupMenuItem(
                    value: v,
                    checked: v == speed,
                    child: Text(v == 1.0 ? 'Normal (1\u00d7)' : label(v)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Change', style: TextStyle(color: theme.colorScheme.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Album art for a library song, fetched from the Player as a small picture.
/// Shows a music note while loading, or if the song has no art.
class RemoteArt extends StatefulWidget {
  const RemoteArt({super.key, required this.client, required this.songId, this.size = 64});

  final ControllerClient client;
  final int? songId;
  final double size;

  @override
  State<RemoteArt> createState() => _RemoteArtState();
}

class _RemoteArtState extends State<RemoteArt> {
  Future<Uint8List?>? _art;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RemoteArt old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) _load();
  }

  void _load() {
    final id = widget.songId;
    _art = id == null ? null : widget.client.artFor(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = widget.size;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size / 5),
      ),
      child: Icon(Icons.music_note_rounded,
          color: theme.colorScheme.primary, size: size / 2),
    );
    final art = _art;
    if (art == null) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: art,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 5),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        );
      },
    );
  }
}

/// Sleep timer: pick a time, see it count down, cancel. The Player does the
/// pausing, so it works even if this phone disconnects.
class _SleepTimerRow extends StatefulWidget {
  const _SleepTimerRow({
    required this.secondsLeft,
    required this.enabled,
    required this.onSet,
  });

  final int secondsLeft;
  final bool enabled;
  final ValueChanged<int> onSet;

  @override
  State<_SleepTimerRow> createState() => _SleepTimerRowState();
}

class _SleepTimerRowState extends State<_SleepTimerRow> {
  DateTime? _endsAt;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_SleepTimerRow old) {
    super.didUpdateWidget(old);
    if (old.secondsLeft != widget.secondsLeft) _sync();
  }

  void _sync() {
    _tick?.cancel();
    if (widget.secondsLeft <= 0) {
      _endsAt = null;
      return;
    }
    _endsAt = DateTime.now().add(Duration(seconds: widget.secondsLeft));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _left() {
    final end = _endsAt;
    if (end == null) return '';
    final s = end.difference(DateTime.now()).inSeconds.clamp(0, 999999);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _endsAt != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.bedtime_rounded,
                color: active ? RtColors.violet : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                active ? 'Pauses in ${_left()}' : 'Sleep timer',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (active)
              TextButton(
                onPressed: widget.enabled ? () => widget.onSet(0) : null,
                child: const Text('Cancel'),
              ),
            PopupMenuButton<int>(
              tooltip: 'Set sleep timer',
              enabled: widget.enabled,
              onSelected: widget.onSet,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 15, child: Text('15 minutes')),
                PopupMenuItem(value: 30, child: Text('30 minutes')),
                PopupMenuItem(value: 45, child: Text('45 minutes')),
                PopupMenuItem(value: 60, child: Text('1 hour')),
                PopupMenuItem(value: 120, child: Text('2 hours')),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(active ? 'Change' : 'Set',
                    style: TextStyle(color: theme.colorScheme.primary)),
              ),
            ),
          ],
        ),
      ),
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
