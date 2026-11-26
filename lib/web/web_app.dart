import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/enums.dart';
import '../core/online/room_code.dart';
import '../core/online_defaults.dart';
import '../core/pairing_qr.dart';
import '../core/theme/app_theme.dart';
import '../features/controller/controller_client.dart';
import '../features/controller/controller_views.dart';
import '../features/online/online_transport.dart';
import '../features/online/supabase_relay.dart';
import '../features/cloud/cloud_library_view.dart';
import '../features/cloud/cloud_pickers.dart';
import '../features/cloud/cloud_settings_screen.dart';
import '../features/cloud/cloud_web_upload.dart';
import 'web_storage.dart';

/// The browser's storage. Overridden in `main_web.dart` (and in tests).
final webStorageProvider = Provider<WebStorage>(
  (ref) => throw UnimplementedError('webStorageProvider must be overridden'),
);

/// The pairing link the page was opened with (from the Player's QR code), read
/// once at start-up in `main_web.dart`. Null for a normal visit.
final webLaunchLinkProvider = Provider<PairingQr?>((ref) => null);

/// The web Controller's connection. Online only: browsers cannot reach a
/// phone's local WebSocket (docs/17 §4), so this uses the Supabase relay with
/// the build's default project.
final webControllerProvider = Provider<ControllerClient>((ref) {
  final relay = SupabaseRelayFactory(
    url: OnlineDefaults.supabaseUrl,
    anonKey: OnlineDefaults.supabaseAnonKey,
  );
  final client = ControllerClient(
    onlineTransportFactory: (roomCode, peerId) => OnlineTransport(
      channelFactory: relay.call,
      roomCode: roomCode,
      peerId: peerId,
    ),
  );
  ref.onDispose(() {
    client.dispose();
    relay.dispose();
  });
  return client;
});

final webControllerStateProvider = StreamProvider<ControllerClientState>((ref) async* {
  final client = ref.watch(webControllerProvider);
  yield client.current;
  yield* client.stateStream;
});

/// RemoteTunes Web: a Controller only (it never plays music itself).
class WebControllerApp extends StatelessWidget {
  const WebControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RemoteTunes Web',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      // The address after # may hold a pairing link, not a screen name.
      initialRoute: '/',
      home: const WebHome(),
    );
  }
}

class WebHome extends ConsumerStatefulWidget {
  const WebHome({super.key});

  @override
  ConsumerState<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends ConsumerState<WebHome> {
  late final ControllerClient _client = ref.read(webControllerProvider);
  late final WebStorage _storage = ref.read(webStorageProvider);
  StreamSubscription<ControllerClientState>? _sub;
  String? _lastSavedKey;

  /// True while resuming a saved session after the page loaded.
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    _sub = _client.stateStream.listen(_persist);
    final link = ref.read(webLaunchLinkProvider);
    final saved = _storage.loadSession();
    if (link != null) {
      // Opened from a Player's QR code: connect to it right away. (The Player
      // user still taps Accept.)
      _startFromLink(link);
    } else if (saved != null) {
      _resuming = true;
      _client
          .resumeSession(session: saved, deviceName: _storage.deviceName)
          .whenComplete(() {
        if (mounted) setState(() => _resuming = false);
      });
    }
  }

  void _startFromLink(PairingQr link) {
    if (!link.hasOnline) {
      // The code has no online room: a browser can only use the online relay.
      setState(() => _linkProblem =
          'This Player is not online, so the web page cannot reach it. On the '
          "Player, turn on online mode (Settings), then scan its QR code again.");
      return;
    }
    _client.connect(
      roomCode: link.roomCode,
      deviceName: _storage.deviceName,
      mode: ConnectionMode.onlineOnly,
      pairingTicket: link.ticket,
    );
  }

  /// Why a scanned link could not be used (shown on the connect screen).
  String? _linkProblem;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Keeps browser storage in step with the connection.
  void _persist(ControllerClientState s) {
    final saved = _client.savedSession;
    if (saved != null && s.isConnected) {
      final key = '${saved.sessionId}|${saved.token}|${saved.peerId}|${saved.playerName}';
      if (key != _lastSavedKey) {
        _lastSavedKey = key;
        _storage.saveSession(saved);
        _storage.rememberRoom(saved.roomCode, playerName: saved.playerName);
      }
    }
    // The Player no longer accepts this session: forget it. (A mere network
    // failure keeps it, so a page reload can still resume.)
    if (s.status == ControllerStatus.disconnected && s.sessionInvalid) {
      _lastSavedKey = null;
      _storage.clearSession();
    }
  }

  Future<void> _disconnect() async {
    _lastSavedKey = null;
    await _storage.clearSession();
    await _client.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webControllerStateProvider).valueOrNull ?? _client.current;
    final theme = Theme.of(context);
    final connected = state.status == ControllerStatus.connected ||
        state.status == ControllerStatus.reconnecting;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Icon(Icons.settings_remote_rounded, color: RtColors.teal),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                connected && state.playerName != null
                    ? 'RemoteTunes Web · ${state.playerName}'
                    : 'RemoteTunes Web',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('web-cloud'),
            tooltip: 'Cloud Library',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => WebCloudPage(client: _client)),
            ),
          ),
          if (connected)
            TextButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Disconnect'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: switch (state.status) {
              ControllerStatus.connected ||
              ControllerStatus.reconnecting =>
                ControllerDashboard(client: _client, state: state),
              ControllerStatus.awaitingCode ||
              ControllerStatus.waitingForPlayer =>
                CodeEntryView(client: _client, state: state),
              ControllerStatus.connecting => _Connecting(
                  text: _resuming
                      ? 'Reconnecting to your Player…'
                      : 'Connecting to the Player as "${_storage.deviceName}"…',
                  onCancel: _disconnect,
                ),
              ControllerStatus.disconnected => _resuming
                  ? _Connecting(text: 'Reconnecting to your Player…', onCancel: _disconnect)
                  : ConnectPanel(
                      client: _client,
                      storage: _storage,
                      message: _linkProblem ?? state.message,
                    ),
            },
          ),
        ),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting({required this.text, required this.onCancel});

  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

/// Enter the room code shown on the Player, or pick a recent room.
class ConnectPanel extends StatefulWidget {
  const ConnectPanel({
    super.key,
    required this.client,
    required this.storage,
    this.message,
  });

  final ControllerClient client;
  final WebStorage storage;
  final String? message;

  @override
  State<ConnectPanel> createState() => _ConnectPanelState();
}

class _ConnectPanelState extends State<ConnectPanel> {
  final _room = TextEditingController();
  late final TextEditingController _name =
      TextEditingController(text: widget.storage.deviceName);
  String? _roomError;
  late List<RecentRoom> _rooms = widget.storage.loadRooms();

  @override
  void dispose() {
    _room.dispose();
    _name.dispose();
    super.dispose();
  }

  void _connect(String input) {
    final problem = RoomCode.problem(input);
    if (problem != null) {
      setState(() => _roomError = problem);
      return;
    }
    setState(() => _roomError = null);
    FocusScope.of(context).unfocus();
    widget.storage.setDeviceName(_name.text);
    final name = _name.text.trim().isEmpty ? WebStorage.defaultDeviceName : _name.text.trim();
    widget.client.connect(
      roomCode: RoomCode.normalize(input),
      deviceName: name,
      mode: ConnectionMode.onlineOnly,
    );
  }

  Future<void> _forget(RecentRoom r) async {
    await widget.storage.removeRoom(r.code);
    if (mounted) setState(() => _rooms = widget.storage.loadRooms());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Text('Control your Player from this browser',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'On the Player phone, open RemoteTunes, choose Start as PLAYER, and '
          'make sure the connection mode is Online or Auto. It shows a room '
          'code. Enter it here. Both need an internet connection. Only '
          'playback commands and status pass through the online relay: your '
          'music never leaves the Player.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (widget.message != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: theme.colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.message!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _room,
          autofocus: true,
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
          onSubmitted: _connect,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          maxLength: 40,
          // Remembered as you type, so it is also used when this page is opened
          // from a Player's QR code (which has no name box).
          onChanged: widget.storage.setDeviceName,
          decoration: const InputDecoration(
            labelText: 'Your name (shown on the Player)',
            helperText: 'Remembered on this browser',
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: RtColors.violet,
            foregroundColor: const Color(0xFF1B1240),
          ),
          onPressed: () => _connect(_room.text),
          icon: const Icon(Icons.public_rounded),
          label: const Text('Connect to Player'),
        ),
        if (_rooms.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Recent rooms', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final r in _rooms)
                  ListTile(
                    minTileHeight: 64,
                    leading: const Icon(Icons.history_rounded),
                    title: Text(RoomCode.format(r.code)),
                    subtitle: Text(r.playerName ?? 'Player'),
                    onTap: () {
                      _room.text = RoomCode.format(r.code);
                      _connect(r.code);
                    },
                    trailing: IconButton(
                      tooltip: 'Forget this room',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => _forget(r),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Room codes change every time a Player starts, so an old room only '
            'works while that Player session is still running.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// The Cloud Library on the web page: browse and upload from the computer; play on the connected Player.
class WebCloudPage extends ConsumerWidget {
  const WebCloudPage({super.key, required this.client});

  final ControllerClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Library')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: CloudLibraryView(
              shuffleOn: () => client.current.playback.shuffleEnabled,
              onOpenSettings: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen()),
              ),
              onUpload: ref.watch(cloudSongPickerProvider) == null ? null : () => uploadPickedSongs(context, ref),
              // The Player streams the song itself; the browser plays nothing.
              onTrack: (s, url, image, {required queue}) {
                if (!client.current.isConnected) {
                  throw ControllerException('Connect to a Player first: the web page plays songs on a Player.');
                }
                return client.playUrl(url, title: s.title, artist: s.artist, album: s.album, imageUrl: image, queue: queue);
              },
            ),
          ),
        ),
      ),
    );
  }
}
