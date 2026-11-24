import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/online/relay.dart';
import '../core/online/room_code.dart';
import '../core/protocol/protocol.dart';
import '../core/transport/local_websocket_transport.dart';
import '../data/repositories/drift_queue_store.dart';
import 'package:path_provider/path_provider.dart';

import '../features/group/group_native.dart';
import '../data/repositories/online_history_repository.dart';
import '../data/repositories/paired_controllers_store.dart';
import '../data/repositories/settings_repository.dart';
import '../features/controller/controller_client.dart';
import '../features/controller/discovery.dart';
import '../features/controller/trusted_players.dart';
import '../features/external/control_mode_engine.dart';
import '../features/external/external_app_engine.dart';
import '../features/external/external_media.dart';
import '../features/online/online_relay_host.dart';
import '../features/online/online_setup.dart';
import '../features/online/online_status.dart';
import '../features/online/online_transport.dart';
import '../features/online/supabase_relay.dart';
import '../features/player/audio/audio_backend.dart';
import '../features/player/audio/player_audio_handler.dart';
import '../features/player/player_host.dart';
import '../features/player/queue_playback_engine.dart';
import '../features/player/server/player_advertiser.dart';
import '../features/player/server/player_library.dart';
import '../features/player/server/player_server.dart';
import 'library_providers.dart';
import 'providers.dart';

// ------------------------------------------------------------------- Player

/// Starts the Player while the Player screen is open and stops it when the
/// screen closes: the engine, the local server + mDNS advertising (unless the
/// mode is Online only), and the online room (if the mode and settings allow).
///
/// Local mode never depends on Supabase: with default settings nothing online
/// is created.
final playerHostProvider = FutureProvider.autoDispose<PlayerHost>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider).load();
  final plan = PlayerOnlinePlan.forMode(settings.connectionMode, settings);

  final library = RepositoryPlayerLibrary(
    ref.watch(libraryRepositoryProvider),
    history: OnlineHistoryRepository(ref.watch(databaseProvider)),
    lyrics: ref.watch(lyricsServiceProvider),
  );
  final localEngine = QueuePlaybackEngine(
    backend: JustAudioBackend(),
    initialVolume: settings.defaultVolume,
    onSongStarted: (id) => unawaited(library.markPlayed(id).catchError((Object _) {})),
    onStreamStarted: (s) => unawaited(library.recordStream(s).catchError((Object _) {})),
    queueStore: DriftQueueStore(ref.watch(databaseProvider)),
  );
  // The queue is kept between runs: pick up where it was, paused.
  try {
    await localEngine.restoreQueue();
  } catch (_) {}
  // External App Control (Phase 5) exists only if the user opted in. With the
  // default settings, no other app is ever looked at.
  final engine = ControlModeEngine(
    local: localEngine,
    external: settings.externalAppControlEnabled
        ? ExternalAppEngine(bridge: ref.watch(externalMediaBridgeProvider))
        : null,
  );
  final server = PlayerServer(
    engine: engine,
    deviceName: settings.deviceName,
    port: settings.lastPlayerPort,
    store: DriftPairedControllersStore(ref.watch(databaseProvider)),
    advertiser: plan.runLocal ? BonsoirPlayerAdvertiser() : null,
    library: library,
    // Where group play's Auto-align click track is written.
    scratchDir: await getTemporaryDirectory(),
    enableLocal: plan.runLocal,
    // If the local port is busy but online is on, carry on online.
    continueWithoutLocal: plan.runOnline,
  );

  // The room code is kept between runs so trusted Controllers can find this
  // Player online again. "Forget all" on the Player screen makes a new one.
  String? roomCode;
  if (plan.runOnline) {
    final repo = ref.watch(settingsRepositoryProvider);
    final saved = await repo.loadPlayerRoomCode();
    if (saved != null && RoomCode.isValid(saved)) {
      roomCode = saved;
    } else {
      roomCode = RoomCode.generate();
      await repo.savePlayerRoomCode(roomCode);
    }
  }
  if (roomCode != null) {
    // Set before start() so the local advertisement can include the room.
    server.updateOnline(
      OnlineRelayInfo(roomCode: roomCode, phase: OnlinePhase.connecting),
    );
  }

  // The Android media session (notification, lock screen, headset buttons).
  // If it can't start, the Player still works without a notification.
  final handler = await PlayerAudioService.ensureStarted();
  // The RemoteTunes notification mirrors RemoteTunes' own player only; another
  // app has its own notification.
  handler?.attach(localEngine);

  SupabaseRelayFactory? relayFactory;
  OnlineRelayHost? relay;
  if (roomCode != null) {
    relayFactory = SupabaseRelayFactory(
      url: settings.supabaseUrl!.trim(),
      anonKey: settings.supabaseAnonKey!.trim(),
    );
    relay = OnlineRelayHost(
      channelFactory: relayFactory.call,
      roomCode: roomCode,
      onPeer: server.acceptConnection,
      onStatus: server.updateOnline,
    );
  }

  final host = PlayerHost(
    engine: engine,
    server: server,
    audioHandler: handler,
    relay: relay,
    relayFactory: relayFactory,
    onlineProblem: plan.problem,
  );
  ref.onDispose(() => host.dispose());
  // While a Controller plays along (group play), this Player stays awake with
  // its Wi-Fi in a fast mode: power saving adds jittery delay that spoils the
  // timing.
  final groupNative = MethodChannelGroupNative();
  var groupLocked = false;
  final groupSub = server.stateStream.listen((st) {
    if (st.groupJoined != groupLocked) {
      groupLocked = st.groupJoined;
      unawaited(groupNative.setLocks(enabled: groupLocked));
    }
  });
  ref.onDispose(() {
    unawaited(groupSub.cancel());
    if (groupLocked) unawaited(groupNative.setLocks(enabled: false));
  });
  await server.start();
  // Joining the room can take seconds (or fail when offline); the Player UI
  // follows its status instead of waiting here.
  if (relay != null) unawaited(relay.start());
  return host;
});

final playerServerStateProvider =
    StreamProvider.autoDispose<PlayerServerState>((ref) async* {
  final host = await ref.watch(playerHostProvider.future);
  yield host.server.current;
  yield* host.server.stateStream;
});

final playerPlaybackProvider =
    StreamProvider.autoDispose<PlaybackState>((ref) async* {
  final host = await ref.watch(playerHostProvider.future);
  yield host.engine.state;
  yield* host.engine.states;
});

/// The link to other music apps on this phone (Android media sessions).
/// Overridable in tests (the real one needs the Android side).
final externalMediaBridgeProvider = Provider<ExternalMediaBridge>(
  (ref) => MethodChannelExternalMediaBridge(),
);

// --------------------------------------------------------------- Controller

/// The Controller connection. This is the only place that picks the concrete
/// transports: the local WebSocket (dart:io) and the Supabase relay. A future
/// web Controller would supply its own.
final controllerClientProvider = Provider<ControllerClient>((ref) {
  SupabaseRelayFactory? cached;
  String? cachedKey;

  /// A relay factory for the *current* settings (they may change while the app
  /// runs). If the online relay isn't set up, joining fails with the reason.
  RelayChannelFactory relayForCurrentSettings() {
    final s = ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    final availability = OnlineAvailability.evaluate(s);
    if (!availability.usable) {
      return (_) => UnavailableRelayChannel(availability.problem!);
    }
    final key = '${s.supabaseUrl}|${s.supabaseAnonKey}';
    if (cachedKey != key) {
      cached?.dispose();
      cached = SupabaseRelayFactory(
        url: s.supabaseUrl!.trim(),
        anonKey: s.supabaseAnonKey!.trim(),
      );
      cachedKey = key;
    }
    return cached!.call;
  }

  final client = ControllerClient(
    transportFactory: (host, port) =>
        LocalWebSocketTransport(host: host, port: port),
    onlineTransportFactory: (roomCode, peerId) => OnlineTransport(
      channelFactory: relayForCurrentSettings(),
      roomCode: roomCode,
      peerId: peerId,
    ),
  );
  ref.onDispose(() {
    client.dispose();
    cached?.dispose();
  });
  return client;
});

/// Players this phone trusts (reconnect without pairing again).
final trustedPlayersStoreProvider =
    Provider<TrustedPlayersStore>((ref) => PrefsTrustedPlayersStore());

final controllerStateProvider = StreamProvider<ControllerClientState>((ref) async* {
  final client = ref.watch(controllerClientProvider);
  yield client.current;
  yield* client.stateStream;
});

/// Overridable in tests (the real one needs the Android NSD plugin).
final playerDiscoveryProvider =
    Provider<PlayerDiscovery>((ref) => BonsoirPlayerDiscovery());

final discoveredPlayersProvider =
    StreamProvider.autoDispose<List<DiscoveredPlayer>>((ref) {
  return ref.watch(playerDiscoveryProvider).discover();
});

/// "Test online relay" in Settings. Overridable in tests.
final relayTesterProvider =
    Provider<Future<RelayTestResult> Function(AppSettings)>((ref) {
  return (settings) async {
    final availability = OnlineAvailability.evaluate(settings);
    if (!availability.usable) return RelayTestResult.failed(availability.problem!);
    final factory = SupabaseRelayFactory(
      url: settings.supabaseUrl!.trim(),
      anonKey: settings.supabaseAnonKey!.trim(),
    );
    try {
      return await testRelayConnection(factory.call);
    } finally {
      await factory.dispose();
    }
  };
});
