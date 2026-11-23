import '../external/control_mode_engine.dart';
import '../online/online_relay_host.dart';
import '../online/supabase_relay.dart';
import 'audio/player_audio_handler.dart';
import 'playback_engine.dart';
import 'queue_aware_engine.dart';
import 'server/player_server.dart';

/// Bundles the Player's engine, server, online relay and (optionally) the
/// Android media session so they start and stop together.
class PlayerHost {
  PlayerHost({
    required this.engine,
    required this.server,
    this.audioHandler,
    this.relay,
    this.relayFactory,
    this.onlineProblem,
  });

  final PlaybackEngine engine;
  final PlayerServer server;
  final RemoteTunesAudioHandler? audioHandler;

  /// The online room connection, when online is in use.
  final OnlineRelayHost? relay;
  final SupabaseRelayFactory? relayFactory;

  /// Why online was wanted but not started (e.g. keys not entered).
  final String? onlineProblem;

  /// The engine that can switch to another music app (null if the Player was
  /// built without that, e.g. in tests).
  ControlModeEngine? get controlEngine {
    final e = engine;
    return e is ControlModeEngine ? e : null;
  }

  /// The queue-aware engine (null for the Phase 1 simulated engine).
  QueueAwareEngine? get queueEngine {
    final e = engine;
    return e is QueueAwareEngine ? e : null;
  }

  Future<void> dispose() async {
    audioHandler?.detach();
    await relay?.stop();
    await relayFactory?.dispose();
    await server.stop();
    await engine.dispose();
  }
}
