import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/mono_clock.dart';
import '../../core/models/enums.dart';
import '../controller/controller_client.dart';
import '../player/audio/audio_backend.dart';
import 'clock_sync.dart';
import 'group_audio_cache.dart';
import 'group_follower_core.dart';
import 'group_models.dart';

/// Where this phone's latency adjustment is remembered.
abstract class NudgeStore {
  Future<int> load();
  Future<void> save(int ms);
}

class PrefsNudgeStore implements NudgeStore {
  static const _key = 'rt.group_nudge_ms';

  @override
  Future<int> load() async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_key) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> save(int ms) async =>
      (await SharedPreferences.getInstance()).setInt(_key, ms);
}

/// This phone playing the connected Player's song along with it: downloads the
/// song from the Player over the local network, measures the clock difference,
/// and keeps its own audio in step (see [GroupFollowerCore]).
class GroupFollowerService implements GroupFollower {
  GroupFollowerService({
    required ControllerClient client,
    AudioBackend Function()? makeBackend,
    GroupAudioSource? audio,
    NudgeStore? nudges,
    MonoClock? clock,
    this.resyncEvery = const Duration(seconds: 10),
  })  : _client = client,
        _makeBackend = makeBackend ?? JustAudioBackend.new,
        _clock = clock ?? MonoClock.instance,
        _nudges = nudges ?? PrefsNudgeStore() {
    _audio = audio ??
        GroupAudioCache(
          requestFor: client.groupAudioRequest,
          folder: () async {
            final tmp = await getTemporaryDirectory();
            return Directory('${tmp.path}/group_audio');
          },
        );
  }

  final ControllerClient _client;
  final AudioBackend Function() _makeBackend;
  final MonoClock _clock;
  final NudgeStore _nudges;
  final Duration resyncEvery;
  late final GroupAudioSource _audio;

  final ClockSync _sync = ClockSync();
  GroupFollowerCore? _core;
  AudioBackend? _backend;

  StreamSubscription<dynamic>? _msgSub;
  StreamSubscription<ControllerClientState>? _stateSub;
  Timer? _resyncTimer;
  bool _wantOn = false;
  bool _wasConnected = false;
  int _nudgeMs = 0;

  final StreamController<GroupStatus> _statusController =
      StreamController<GroupStatus>.broadcast();
  GroupStatus _status = const GroupStatus();

  @override
  GroupStatus get status => _status;

  @override
  Stream<GroupStatus> get statusStream => _statusController.stream;

  void _set(GroupStatus s) {
    _status = s.copyWith(
      nudgeMs: _nudgeMs,
      offsetMs: _sync.offsetMs,
      rttMs: _sync.rttMs,
      spreadMs: _sync.spreadMs,
      available: _client.current.isConnected &&
          _client.current.route == ConnectionType.local,
    );
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  @override
  Future<void> join() async {
    if (_wantOn) return;
    final cs = _client.current;
    if (!cs.isConnected) {
      throw ControllerException('Connect to a Player first.');
    }
    if (cs.route != ConnectionType.local) {
      throw ControllerException(
          'Playing on both phones needs the local network (the same Wi-Fi). '
          'The internet is too slow and uneven to keep them in step.');
    }
    _nudgeMs = await _nudges.load();
    _wantOn = true;
    _wasConnected = true;
    _sync.clear();
    _set(const GroupStatus(phase: GroupPhase.syncing, message: 'Joining…'));

    final backend = _backend = _makeBackend();
    final core = _core = GroupFollowerCore(
      backend: backend,
      audio: _audio,
      nowMs: _clock.nowMs,
      offsetMs: () => _sync.offsetMs,
      onStatus: _set,
    )..nudgeMs = _nudgeMs;

    _msgSub = _client.groupMessages.listen((m) {
      final sync = GroupSync.fromPayload(m.payload);
      if (sync != null) unawaited(core.onSync(sync));
    });
    _stateSub = _client.stateStream.listen(_onClientState);

    try {
      await _client.setGroupJoin(true);
    } catch (e) {
      await _teardown();
      rethrow;
    }
    unawaited(_probeBurst(14));
    _resyncTimer = Timer.periodic(resyncEvery, (_) => unawaited(_probeBurst(5)));
  }

  /// A short run of clock probes. Each is a round trip to the Player; the
  /// estimator keeps the best ones.
  Future<void> _probeBurst(int count) async {
    for (var i = 0; i < count && _wantOn; i++) {
      try {
        final p = await _client.syncProbe();
        _sync.add(p.t0, p.t1, p.t2, p.t3);
      } catch (_) {
        // A lost probe is fine.
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    if (_wantOn) _set(_status);
  }

  void _onClientState(ControllerClientState s) {
    if (!_wantOn) return;
    final connected = s.isConnected;
    if (!connected && _wasConnected) {
      _wasConnected = false;
      unawaited(_core?.stop());
      _core?.reset();
      _set(const GroupStatus(
          phase: GroupPhase.syncing, message: 'Connection lost. Reconnecting…'));
    } else if (connected && !_wasConnected) {
      _wasConnected = true;
      if (s.route != ConnectionType.local) {
        unawaited(leave());
        return;
      }
      // Back: join again and measure again (the Player forgot we had joined).
      _sync.clear();
      _set(const GroupStatus(phase: GroupPhase.syncing, message: 'Rejoining…'));
      unawaited(() async {
        try {
          await _client.setGroupJoin(true);
          await _probeBurst(10);
        } catch (_) {
          _set(const GroupStatus(
              phase: GroupPhase.problem, message: "Couldn't rejoin. Switch it off and on."));
        }
      }());
    }
  }

  @override
  Future<void> resync() async {
    if (!_wantOn) return;
    _sync.clear();
    _set(_status.copyWith(phase: GroupPhase.syncing, message: 'Measuring the connection…'));
    await _probeBurst(14);
  }

  @override
  Future<void> setNudgeMs(int ms) async {
    _nudgeMs = ms.clamp(-300, 300);
    _core?.nudgeMs = _nudgeMs;
    await _nudges.save(_nudgeMs);
    _set(_status);
  }

  Future<void> _teardown() async {
    _wantOn = false;
    _resyncTimer?.cancel();
    _resyncTimer = null;
    await _msgSub?.cancel();
    _msgSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _core?.stop();
    } catch (_) {}
    _core = null;
    try {
      await _backend?.dispose();
    } catch (_) {}
    _backend = null;
    final a = _audio;
    if (a is GroupAudioCache) await a.clear();
  }

  @override
  Future<void> leave() async {
    if (!_wantOn) return;
    final wasConnected = _client.current.isConnected;
    await _teardown();
    if (wasConnected) {
      try {
        await _client.setGroupJoin(false);
      } catch (_) {}
    }
    _set(const GroupStatus());
  }

  Future<void> dispose() async {
    await leave();
    await _statusController.close();
  }
}
