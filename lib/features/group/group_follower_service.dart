import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/mono_clock.dart';
import '../../core/models/enums.dart';
import '../controller/controller_client.dart';
import '../player/audio/audio_backend.dart';
import 'calibration_analysis.dart';
import 'clock_sync.dart';
import 'group_audio_cache.dart';
import 'group_calibrator.dart';
import 'group_follower_core.dart';
import 'group_models.dart';
import 'group_native.dart';
import 'mic_recorder.dart';

/// Where this phone's latency adjustment is remembered. It is kept separately
/// for each way the sound comes out (phone speaker, wired, Bluetooth): the delay
/// is different for each, so one number cannot fit them all.
abstract class NudgeStore {
  Future<int> load(String route);
  Future<void> save(String route, int ms);
}

class PrefsNudgeStore implements NudgeStore {
  static String _key(String route) => 'rt.group_nudge_ms.$route';
  static const _legacy = 'rt.group_nudge_ms';

  @override
  Future<int> load(String route) async {
    try {
      final p = await SharedPreferences.getInstance();
      // The first version kept one number, which was for the speaker.
      return p.getInt(_key(route)) ?? (route == 'speaker' ? p.getInt(_legacy) : null) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> save(String route, int ms) async =>
      (await SharedPreferences.getInstance()).setInt(_key(route), ms);
}

/// This phone playing the connected Player's song along with it: downloads the
/// song from the Player over the local network, measures the clock difference,
/// and keeps its own audio in step (see [GroupFollowerCore]).
///
/// While it runs, the phone is kept awake with its Wi-Fi in a fast mode (power
/// saving adds jittery delay, which is poison for clock measurements), and it
/// warns about things that make sync unlikely: Bluetooth output, an uneven
/// Wi-Fi.
class GroupFollowerService implements GroupFollower, CalibrationHost {
  GroupFollowerService({
    required ControllerClient client,
    AudioBackend Function()? makeBackend,
    GroupAudioSource? audio,
    NudgeStore? nudges,
    GroupNative? native,
    MicRecorder Function()? makeRecorder,
    Future<SyncMeasurement> Function(Float64List)? analyze,
    Future<void> Function(double mediaSeconds)? waitForMedia,
    MonoClock? clock,
    this.resyncEvery = const Duration(seconds: 5),
  })  : _client = client,
        _makeBackend = makeBackend ?? JustAudioBackend.new,
        _clock = clock ?? MonoClock.instance,
        _nudges = nudges ?? PrefsNudgeStore(),
        _native = native ?? MethodChannelGroupNative(),
        _makeRecorder = makeRecorder ?? RecordMicRecorder.new,
        _analyze = analyze,
        _waitForMedia = waitForMedia {
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
  final GroupNative _native;
  final MicRecorder Function() _makeRecorder;
  final Future<SyncMeasurement> Function(Float64List)? _analyze;
  final Future<void> Function(double mediaSeconds)? _waitForMedia;
  final Duration resyncEvery;
  late final GroupAudioSource _audio;

  /// Probes at join (enough for a solid first estimate) and in each re-check.
  static const joinProbes = 20;
  static const resyncProbes = 6;

  /// The uneven-Wi-Fi warning appears when the good probes disagree by more
  /// than this.
  static const unevenWifiMs = 15.0;

  final ClockSync _sync = ClockSync();
  GroupFollowerCore? _core;
  AudioBackend? _backend;

  StreamSubscription<dynamic>? _msgSub;
  StreamSubscription<ControllerClientState>? _stateSub;
  Timer? _resyncTimer;
  bool _wantOn = false;
  bool _wasConnected = false;
  int _nudgeMs = 0;
  String _route = 'speaker';
  int? _outputLatency;

  final StreamController<GroupStatus> _statusController =
      StreamController<GroupStatus>.broadcast();
  GroupStatus _status = const GroupStatus();

  @override
  GroupStatus get status => _status;

  @override
  Stream<GroupStatus> get statusStream => _statusController.stream;

  @override
  GroupFollowerCore? get core => _core;
  @override
  ControllerClient get client => _client;
  MonoClock get clock => _clock;
  @override
  bool get isOn => _wantOn;
  @override
  String get route => _route;
  @override
  int get nudgeMs => _nudgeMs;

  GroupCalibrator? _calibrator;

  @override
  Future<CalibrationReport> autoAlign() async {
    if (_calibrator != null) {
      return const CalibrationReport(ok: false, message: 'Auto-align is already running.');
    }
    final recorder = _makeRecorder();
    final c = _calibrator = GroupCalibrator(
      host: this,
      recorder: recorder,
      analyze: _analyze,
      waitForMedia: _waitForMedia,
    );
    try {
      final r = await c.run(onProgress: setCalibrationNote);
      setCalibrationNote(r.message);
      return r;
    } finally {
      _calibrator = null;
      try {
        await recorder.dispose();
      } catch (_) {}
    }
  }

  @override
  void cancelAutoAlign() => _calibrator?.cancel();

  String _warnings(GroupStatus s) {
    final lines = <String>[
      if (s.warning.isNotEmpty) s.warning,
      if (_route == 'bluetooth')
        'The sound is going to Bluetooth. Bluetooth adds a large delay that '
            'changes from moment to moment, so the phones will not stay in '
            'step. Use the phone speaker or a wire.',
      if (_wantOn &&
          (_sync.spreadMs ?? 0) > unevenWifiMs &&
          s.phase == GroupPhase.playing)
        'The Wi-Fi is uneven right now, so the timing may wobble a little. '
            'Move closer to the router.',
    ];
    return lines.join('\n');
  }

  void _set(GroupStatus s) {
    _status = s.copyWith(
      nudgeMs: _nudgeMs,
      offsetMs: _sync.offsetMs,
      rttMs: _sync.rttMs,
      spreadMs: _sync.spreadMs,
      route: _route,
      outputLatencyMs: _outputLatency,
      available: _client.current.isConnected &&
          _client.current.route == ConnectionType.local,
    );
    _status = GroupStatus(
      phase: _status.phase,
      message: _status.message,
      offsetMs: _status.offsetMs,
      rttMs: _status.rttMs,
      spreadMs: _status.spreadMs,
      driftMs: _status.driftMs,
      nudgeMs: _status.nudgeMs,
      title: _status.title,
      available: _status.available,
      warning: _warnings(s),
      route: _status.route,
      outputLatencyMs: _status.outputLatencyMs,
      calibration: _status.calibration,
    );
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  /// Publishes a calibration progress line (see Auto-align).
  void setCalibrationNote(String note) => _set(_status.copyWith(calibration: note));

  Future<void> _readRoute() async {
    final r = await _native.outputRoute();
    _outputLatency = await _native.outputLatencyMs();
    if (r != _route) {
      _route = r;
      // A different output has a different delay: use its own saved setting.
      _nudgeMs = await _nudges.load(_route);
      _core?.nudgeMs = _nudgeMs;
    }
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
    _route = await _native.outputRoute();
    _outputLatency = await _native.outputLatencyMs();
    _nudgeMs = await _nudges.load(_route);
    _wantOn = true;
    _wasConnected = true;
    _sync.clear();
    // Awake, with a fast Wi-Fi, and the screen on so the audio is not stopped.
    await _native.setLocks(enabled: true, keepScreenOn: true);
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
    unawaited(_probeBurst(joinProbes));
    _resyncTimer = Timer.periodic(resyncEvery, (_) {
      unawaited(_probeBurst(resyncProbes));
      unawaited(_readRoute().then((_) {
        if (_wantOn) _set(_status);
      }));
    });
  }

  /// A short run of clock probes. Each is a round trip to the Player; the
  /// estimator keeps the quickest.
  Future<void> _probeBurst(int count) async {
    for (var i = 0; i < count && _wantOn; i++) {
      try {
        final p = await _client.syncProbe();
        _sync.add(p.t0, p.t1, p.t2, p.t3);
      } catch (_) {
        // A lost probe is fine.
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
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
      _core?.reset();
      _set(const GroupStatus(phase: GroupPhase.syncing, message: 'Rejoining…'));
      unawaited(() async {
        try {
          await _client.setGroupJoin(true);
          await _probeBurst(joinProbes);
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
    await _probeBurst(joinProbes);
  }

  @override
  Future<void> setNudgeMs(int ms) async {
    _nudgeMs = ms.clamp(-300, 300);
    _core?.nudgeMs = _nudgeMs;
    await _nudges.save(_route, _nudgeMs);
    _set(_status);
  }

  Future<void> _teardown() async {
    _calibrator?.cancel();
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
    await _native.setLocks(enabled: false);
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
