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
import '../features/player/audio/audio_format.dart';
import '../features/player/audio/crossfade_backend.dart';
import '../features/player/audio/player_audio_handler.dart';
import '../features/player/eq/equalizer_controller.dart';
import '../features/player/eq/settings_eq_store.dart';
import '../features/player/player_core.dart';
import '../features/player/player_host.dart';
import '../features/player/sleep_timer.dart';
import '../features/player/queue_playback_engine.dart';
import '../features/player/server/player_advertiser.dart';
import '../features/player/server/player_library.dart';
import '../features/player/server/player_server.dart';
import 'library_providers.dart';
import 'providers.dart';

// ------------------------------------------------------------------- Player

/// What plays this phone's own music, whether or not other phones are allowed
/// to control it: the audio engine, the library, the media notification and the
/// sleep timer. Lives as long as the app does.
final playerCoreProvider = FutureProvider<PlayerCore>((ref) async {
  final settings = await ref.watch(settingsRepositoryProvider).load();

  final library = RepositoryPlayerLibrary(
    ref.watch(libraryRepositoryProvider),
    history: OnlineHistoryRepository(ref.watch(databaseProvider)),
    lyrics: ref.watch(lyricsServiceProvider),
  );
  // Two players, so a song can fade into the next (Settings > Crossfade).
  final backend = CrossfadeBackend(JustAudioBackend(), JustAudioBackend());
  final localEngine = QueuePlaybackEngine(
    backend: backend,
    initialVolume: settings.defaultVolume,
    onSongStarted: (id) => unawaited(library.markPlayed(id).catchError((Object _) {})),
    onStreamStarted: (s) => unawaited(library.recordStream(s).catchError((Object _) {})),
    queueStore: DriftQueueStore(ref.watch(databaseProvider)),
    formatReader: AudioFormatReader().describe,
  );
  unawaited(localEngine.setReplayGainMode(settings.replayGainMode));
  unawaited(localEngine.setCrossfade(settings.crossfadeSeconds));
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
  // The Android media session (notification, lock screen, headset buttons).
  // If it can't start, the player still works without a notification.
  final handler = await PlayerAudioService.ensureStarted();
  // The RemoteTunes notification mirrors RemoteTunes' own player only; another
  // app has its own notification.
  handler?.attach(localEngine);
  // A heart button on the lock screen / notification for the song playing.
  try {
    await library.preloadFavorites();
  } catch (_) {}
  handler?.isFavorite = library.isFavorite;
  handler?.setFavorite = library.setFavorite;
  final sleep = SleepTimerService(onFire: engine.pause);

  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final equalizer = EqualizerController(
    backend: backend,
    store: SettingsEqStore(settingsRepo),
    outputRoute: MethodChannelGroupNative().outputRoute,
  );
  // The phone sets its equalizer up when the first song loads; this waits for
  // that, then applies the saved settings.
  unawaited(equalizer.init());

  final core = PlayerCore(
    equalizer: equalizer,
    engine: engine,
    localEngine: localEngine,
    library: library,
    audioHandler: handler,
    sleepTimer: sleep,
  );
  ref.onDispose(() => core.dispose());
  return core;
});

/// Lets other phones control this one: the local server + mDNS advertising
/// (unless the mode is Online only), and the online room (if the mode and
/// settings allow). Runs only while something watches it (the "Start remote
/// playback" switch keeps it watched), on top of [playerCoreProvider], so
/// stopping it never stops the music.
///
/// Local mode never depends on Supabase: with default settings nothing online
/// is created.
final playerHostProvider = FutureProvider.autoDispose<PlayerHost>((ref) async {
  final core = await ref.watch(playerCoreProvider.future);
  final settings = await ref.watch(settingsRepositoryProvider).load();
  final plan = PlayerOnlinePlan.forMode(settings.connectionMode, settings);

  final engine = core.engine;
  final server = PlayerServer(
    engine: engine,
    deviceName: settings.deviceName,
    port: settings.lastPlayerPort,
    store: DriftPairedControllersStore(ref.watch(databaseProvider)),
    advertiser: plan.runLocal ? BonsoirPlayerAdvertiser() : null,
    library: core.library,
    // Where group play's Auto-align click track is written.
    scratchDir: await getTemporaryDirectory(),
    enableLocal: plan.runLocal,
    // If the local port is busy but online is on, carry on online.
    continueWithoutLocal: plan.runOnline,
    sleepTimer: core.sleepTimer,
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

  // The engine and the media session belong to the core: stopping remote
  // playback only stops the server and the online room.
  // While other phones may control this one, the media service stays in the
  // foreground even when nothing plays.
  core.audioHandler?.keepAlive = true;
  ref.onDispose(() => core.audioHandler?.keepAlive = false);

  final host = PlayerHost(
    engine: engine,
    server: server,
    relay: relay,
    relayFactory: relayFactory,
    onlineProblem: plan.problem,
    ownsEngine: false,
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
  // This phone's own player, with or without remote playback running.
  final core = await ref.watch(playerCoreProvider.future);
  yield core.engine.state;
  yield* core.engine.states;
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
