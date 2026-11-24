import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/models/enums.dart';
import '../../core/online/room_code.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/connection_providers.dart';
import '../../providers/providers.dart';
import 'controller_client.dart';
import 'controller_views.dart';
import '../group/group_models.dart';
import '../group/group_providers.dart';
import 'discovery.dart';
import '../../core/pairing_qr.dart';
import 'qr_scan_screen.dart';
import 'trusted_players.dart';

/// Controller flow in one screen: find a Player -> enter code -> dashboard.
class ControllerScreen extends ConsumerStatefulWidget {
  const ControllerScreen({super.key});

  @override
  ConsumerState<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends ConsumerState<ControllerScreen> {
  late final ControllerClient _client = ref.read(controllerClientProvider);
  late final TrustedPlayersStore _trustedStore =
      ref.read(trustedPlayersStoreProvider);
  List<TrustedPlayer> _trusted = const [];
  String? _trying; // session id of the trusted Player being reconnected
  String? _savedKey;

  @override
  void initState() {
    super.initState();
    _group = ref.read(groupFollowerProvider);
    _loadTrusted(autoConnect: true);
  }

  Future<void> _loadTrusted({bool autoConnect = false}) async {
    List<TrustedPlayer> list;
    try {
      list = await _trustedStore.load();
    } catch (_) {
      list = const [];
    }
    if (!mounted) return;
    setState(() => _trusted = list);
    // Reconnect to the Player used last, without pairing again.
    if (autoConnect &&
        list.isNotEmpty &&
        _client.current.status == ControllerStatus.disconnected) {
      _connectTrusted(list.first);
    }
  }

  ConnectionMode get _mode =>
      ref.read(settingsProvider).valueOrNull?.connectionMode ?? ConnectionMode.auto;

  /// [explicit] means the user picked this exact address (Nearby list, typed
  /// IP or room): use it as it is.
  void _connectTrusted(TrustedPlayer p, {bool explicit = false}) {
    // The Player's Wi-Fi address may have changed: use a fresh one if it is
    // visible on the network right now. It is matched by its online room (which
    // is unique and survives renaming), or else by a name that only one Player
    // on the network has. Two phones can share a name, so a name alone must
    // never pick one.
    String? host;
    int? port;
    String? room;
    final seen = explicit ? null : ref.read(discoveredPlayersProvider).valueOrNull;
    if (seen != null) {
      DiscoveredPlayer? match;
      final byRoom = p.roomCode == null
          ? const <DiscoveredPlayer>[]
          : seen.where((d) => d.roomCode == p.roomCode).toList();
      if (byRoom.isNotEmpty) {
        match = byRoom.first;
      } else {
        final byName = seen.where((d) => d.name == p.name).toList();
        if (byName.length == 1) match = byName.first;
      }
      if (match != null) {
        host = match.host;
        port = match.port;
        room = match.roomCode;
      }
    }
    _trying = p.sessionId;
    _client.resumeTrusted(
      player: p,
      deviceName: ref.read(settingsProvider).valueOrNull?.deviceName ??
          AppConstants.defaultDeviceName,
      mode: _mode,
      host: host,
      port: port,
      roomCode: room,
    );
  }

  Future<void> _forget(TrustedPlayer p) async {
    await _trustedStore.remove(p.sessionId);
    await _loadTrusted();
  }

  /// Remembers the Player once paired (and keeps its address up to date).
  void _onClientState(ControllerClientState s) {
    if (s.status == ControllerStatus.connected) {
      final t = _client.trustedPlayer;
      if (t == null) return;
      final key = '${t.sessionId}|${t.host}|${t.port}|${t.roomCode}|${t.name}';
      if (key == _savedKey) return;
      _savedKey = key;
      _trusted = [t, ..._trusted.where((o) => o.sessionId != t.sessionId)];
      _trustedStore.save(t).then((_) => _loadTrusted());
    } else if (s.status == ControllerStatus.disconnected && s.sessionInvalid) {
      // The Player no longer trusts this phone: forget it here too.
      final id = _trying;
      _trying = null;
      _savedKey = null;
      if (id != null) {
        _trustedStore.remove(id).then((_) => _loadTrusted());
      }
    }
  }

  GroupFollower? _group;

  @override
  void dispose() {
    // Leaving the screen ends group play and the connection (and revokes the
    // session).
    unawaited(_group?.leave());
    unawaited(_client.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(controllerStateProvider, (_, next) {
      final s = next.valueOrNull;
      if (s != null) _onClientState(s);
    });
    final state =
        ref.watch(controllerStateProvider).valueOrNull ?? _client.current;
    final connected = state.status == ControllerStatus.connected ||
        state.status == ControllerStatus.reconnecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Controller'),
        actions: [
          if (connected)
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.link_off_rounded),
              onPressed: () => _client.disconnect(),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state.status) {
          ControllerStatus.disconnected ||
          ControllerStatus.connecting =>
            _ConnectView(
              client: _client,
              state: state,
              trusted: _trusted,
              onConnectTrusted: _connectTrusted,
              onForget: _forget,
            ),
          ControllerStatus.awaitingCode ||
          ControllerStatus.waitingForPlayer =>
            CodeEntryView(client: _client, state: state),
          ControllerStatus.connected ||
          ControllerStatus.reconnecting =>
            ControllerDashboard(client: _client, state: state),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Connect view

/// Find a Player. What is offered follows the connection mode:
///  * Local only:  nearby Players + manual address
///  * Online only: the room code shown on the Player
///  * Auto:        both; the local network is tried first, online is the fallback
class _ConnectView extends ConsumerStatefulWidget {
  const _ConnectView({
    required this.client,
    required this.state,
    required this.trusted,
    required this.onConnectTrusted,
    required this.onForget,
  });

  final ControllerClient client;
  final ControllerClientState state;
  final List<TrustedPlayer> trusted;
  final void Function(TrustedPlayer, {bool explicit}) onConnectTrusted;
  final void Function(TrustedPlayer) onForget;

  @override
  ConsumerState<_ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends ConsumerState<_ConnectView> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '${AppConstants.defaultPlayerPort}');
  final _room = TextEditingController();
  String? _formError;
  String? _roomError;

  @override
  void initState() {
    super.initState();
    // Remember the last room code typed in this session.
    final last = widget.state.roomCode;
    if (last != null) _room.text = RoomCode.format(last);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _room.dispose();
    super.dispose();
  }

  ConnectionMode get _mode =>
      ref.read(settingsProvider).valueOrNull?.connectionMode ?? ConnectionMode.auto;

  String get _deviceName =>
      ref.read(settingsProvider).valueOrNull?.deviceName ??
      AppConstants.defaultDeviceName;

  /// The room code typed in the box, if it is a valid one.
  String? get _typedRoom {
    final n = RoomCode.normalize(_room.text);
    return RoomCode.isValid(n) ? n : null;
  }

  /// A Player this phone already trusts that matches what was picked or typed:
  /// by its online room (stable, even if it is renamed), by address, or by a
  /// name that only one saved Player has.
  TrustedPlayer? _trustedMatch({String? host, int? port, String? room, String? name}) {
    for (final t in widget.trusted) {
      if (room != null && t.roomCode == room) return t;
      if (host != null && port != null && t.host == host && t.port == port) return t;
    }
    if (name != null) {
      final byName = widget.trusted.where((t) => t.name == name).toList();
      if (byName.length == 1) return byName.first;
    }
    return null;
  }

  void _connect({String? host, int? port, String? room, String? ticket, String? name}) {
    FocusScope.of(context).unfocus();
    // Already trusted: reconnect with no code. (A scanned QR is always a fresh
    // pairing.)
    final known = ticket == null
        ? _trustedMatch(host: host, port: port, room: room, name: name)
        : null;
    if (known != null) {
      widget.onConnectTrusted(known.copyWith(host: host, port: port, roomCode: room),
          explicit: true);
      return;
    }
    widget.client.connect(
      host: host,
      port: port,
      roomCode: room,
      deviceName: _deviceName,
      mode: _mode,
      pairingTicket: ticket,
    );
  }

  Future<void> _scan() async {
    final qr = await Navigator.of(context).push<PairingQr>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (qr == null || !mounted) return;
    // The QR carries the local address and/or the online room; the connection
    // mode on this phone decides which of them is used.
    _connect(
      host: qr.host,
      port: qr.port,
      room: qr.roomCode,
      ticket: qr.ticket,
    );
  }

  void _connectManual() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty) {
      setState(() => _formError = "Enter the Player's IP address.");
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _formError = 'Enter a port between 1 and 65535.');
      return;
    }
    setState(() => _formError = null);
    // In Auto mode a valid room code typed above becomes the fallback.
    _connect(host: host, port: port, room: _mode == ConnectionMode.localOnly ? null : _typedRoom);
  }

  void _connectOnline() {
    final problem = RoomCode.problem(_room.text);
    if (problem != null) {
      setState(() => _roomError = problem);
      return;
    }
    setState(() => _roomError = null);
    _connect(room: RoomCode.normalize(_room.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = ref.watch(settingsProvider).valueOrNull?.connectionMode ??
        ConnectionMode.auto;
    final connecting = widget.state.status == ControllerStatus.connecting;
    final showLocal = mode != ConnectionMode.onlineOnly;
    final showOnline = mode != ConnectionMode.localOnly;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _ModeNote(mode: mode),
        const SizedBox(height: 12),
        if (widget.state.message != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.state.message!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (connecting) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(_connectingText(widget.state)),
          const SizedBox(height: 16),
        ],
        if (widget.trusted.isNotEmpty) ...[
          _TrustedCard(
            players: widget.trusted,
            enabled: !connecting,
            onConnect: widget.onConnectTrusted,
            onForget: widget.onForget,
          ),
          const SizedBox(height: 16),
        ],
        _ScanCard(onScan: connecting ? null : _scan),
        const SizedBox(height: 8),
        // Everything below is the fallback: kept folded so the screen is short.
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Other ways to connect', style: theme.textTheme.titleMedium),
            subtitle: const Text('Nearby list, IP address, room code'),
            initiallyExpanded: widget.state.message != null,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLocal) ..._localSection(theme, connecting),
              if (showLocal && showOnline) const SizedBox(height: 24),
              if (showOnline) ..._onlineSection(theme, connecting, mode),
            ],
          ),
        ),
      ],
    );
  }

  String _connectingText(ControllerClientState s) {
    if (s.host != null) return 'Connecting to ${s.host}…';
    return 'Connecting online…';
  }

  List<Widget> _localSection(ThemeData theme, bool connecting) {
    final discovered = ref.watch(discoveredPlayersProvider);
    return [
      Row(
        children: [
          Expanded(
            child: Text('Nearby Players', style: theme.textTheme.titleMedium),
          ),
          IconButton(
            tooltip: 'Search again',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(discoveredPlayersProvider),
          ),
        ],
      ),
      discovered.when(
        loading: () => const _Hint('Looking for Players…'),
        error: (_, __) => const _Hint(
          "Automatic discovery isn't available on this network. "
          'Use manual connect below.',
        ),
        data: (list) => list.isEmpty
            ? const _Hint(
                'No Players found yet. On the other phone, choose '
                '"Start as PLAYER" and stay on that screen. Both phones must '
                'be on the same Wi‑Fi or hotspot. Hotspots often hide '
                'Players, so you can also connect manually below.',
              )
            : Card(
                child: Column(
                  children: [
                    for (final p in list)
                      ListTile(
                        minTileHeight: 64,
                        leading: const Icon(Icons.speaker_rounded),
                        title: Text(p.name),
                        subtitle: Text(
                          p.roomCode != null
                              ? '${p.host}:${p.port} · also online'
                              : '${p.host}:${p.port}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        enabled: !connecting,
                        onTap: () => _connect(
                          host: p.host,
                          port: p.port,
                          name: p.name,
                          // The Player advertises its room, so Auto mode can
                          // fall back online without typing anything.
                          room: p.roomCode ?? _typedRoom,
                        ),
                      ),
                  ],
                ),
              ),
      ),
      const SizedBox(height: 24),
      Text('Connect manually', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(
        controller: _host,
        enabled: !connecting,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Player IP address',
          hintText: 'e.g. 192.168.1.20',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _port,
        enabled: !connecting,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Port'),
        onSubmitted: (_) => _connectManual(),
      ),
      if (_formError != null) ...[
        const SizedBox(height: 8),
        Text(_formError!, style: TextStyle(color: theme.colorScheme.error)),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: connecting ? null : _connectManual,
        child: const Text('Connect'),
      ),
      const SizedBox(height: 8),
      Text(
        'The Player screen shows its address.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    ];
  }

  List<Widget> _onlineSection(ThemeData theme, bool connecting, ConnectionMode mode) {
    final onlineOnly = mode == ConnectionMode.onlineOnly;
    return [
      Row(
        children: [
          const Icon(Icons.public_rounded, color: RtColors.violet),
          const SizedBox(width: 8),
          Text(onlineOnly ? 'Connect online' : 'Online (optional)',
              style: theme.textTheme.titleMedium),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        onlineOnly
            ? 'Works on any network or mobile data. Enter the room code shown on '
                'the Player. Both phones need internet.'
            : 'Used when the local network is not available. Enter the room code '
                'shown on the Player (it is also picked up automatically when '
                'you choose a nearby Player).',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _room,
        enabled: !connecting,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 12,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
        ],
        decoration: InputDecoration(
          labelText: 'Room code',
          hintText: 'ABCD-2345',
          errorText: _roomError,
          errorMaxLines: 3,
          counterText: '',
        ),
        onChanged: (_) {
          if (_roomError != null) setState(() => _roomError = null);
        },
        onSubmitted: (_) {
          if (onlineOnly) _connectOnline();
        },
      ),
      if (onlineOnly) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: RtColors.violet,
            foregroundColor: const Color(0xFF1B1240),
          ),
          onPressed: connecting ? null : _connectOnline,
          icon: const Icon(Icons.public_rounded),
          label: const Text('Connect online'),
        ),
      ],
    ];
  }
}

/// Players this phone already trusts: one tap, no pairing.
class _TrustedCard extends StatelessWidget {
  const _TrustedCard({
    required this.players,
    required this.enabled,
    required this.onConnect,
    required this.onForget,
  });

  final List<TrustedPlayer> players;
  final bool enabled;
  final void Function(TrustedPlayer) onConnect;
  final void Function(TrustedPlayer) onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your Players', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'These trust this phone, so there is no pairing.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            for (final p in players)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 64,
                leading: const Icon(Icons.verified_user_rounded, color: RtColors.teal),
                title: Text(p.name),
                subtitle: Text(p.host != null ? '${p.host}:${p.port}' : 'Online'),
                onTap: enabled ? () => onConnect(p) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Forget ${p.name}',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => onForget(p),
                    ),
                    FilledButton(
                      onPressed: enabled ? () => onConnect(p) : null,
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The quick way to pair: scan the QR code shown on the Player.
class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.onScan});
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scan to connect', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "Scan the QR code on the Player's screen. No typing: you only "
              'tap Accept on the Player.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan QR code'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line saying how this phone will connect.
class _ModeNote extends StatelessWidget {
  const _ModeNote({required this.mode});

  final ConnectionMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = mode == ConnectionMode.onlineOnly;
    final color = online ? RtColors.violet : RtColors.teal;
    return Row(
      children: [
        Icon(
          switch (mode) {
            ConnectionMode.auto => Icons.sync_alt_rounded,
            ConnectionMode.localOnly => Icons.wifi_rounded,
            ConnectionMode.onlineOnly => Icons.public_rounded,
          },
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${mode.label}: ${mode.description} (change it on the Home screen)',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
