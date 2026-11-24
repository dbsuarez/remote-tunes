import 'dart:async';
import 'dart:math' as math;

import '../player/audio/audio_backend.dart';
import 'group_models.dart';

/// Where the follower gets song files from. The real one downloads them from
/// the Player; tests use a fake.
abstract class GroupAudioSource {
  /// Path of the song on this phone if it is already here and checked, else null.
  String? pathIfReady(int songId);

  /// Starts fetching a song (does nothing if it is already here or on its way).
  Future<void> fetch(int songId);

  /// A plain-language reason the last fetch of this song failed, else null.
  String? failureOf(int songId);

  /// 0.0 to 1.0 while a song is being fetched, else null.
  double? progressOf(int songId);
}

/// Keeps this phone's audio in step with the Player's, given the Player's
/// `group_sync` messages and the clock difference between the two phones.
///
/// For each message it works out where the song should be *right now* on this
/// phone, `expected = position + (Player's clock now - its clock when it
/// sampled) * speed + nudge`, and compares it with where this phone's audio
/// really is. Then:
///
///  * not playing yet: seek there and start;
///  * the Player jumped (a seek there): jump too;
///  * far off ([hardSeekMs]) twice in a row: seek;
///  * a little off ([nudgeAboveMs], judged on the median of the last few
///    readings so one noisy reading does nothing): play 1% faster or slower
///    until it is close again (no audible jump, no pitch change you can hear);
///  * close ([settleBelowMs]): back to normal speed.
///
/// Right after a start or a jump the audio engine's position is unsettled, so
/// nothing is corrected for [settleMs]. If it stays far off for a long time the
/// follower says so instead of pretending.
///
/// Pure logic around an [AudioBackend], so it is tested without a phone.
class GroupFollowerCore {
  GroupFollowerCore({
    required this.backend,
    required this.audio,
    required this.nowMs,
    required this.offsetMs,
    required this.onStatus,
    this.hardSeekMs = 250,
    this.nudgeAboveMs = 18,
    this.settleBelowMs = 8,
    this.hardSeekCooldownMs = 2000,
    this.settleMs = 800,
    this.jumpMs = 400,
    this.stuckAboveMs = 40,
    this.stuckForMs = 12000,
    this.speedStep = 0.01,
  });

  final AudioBackend backend;
  final GroupAudioSource audio;

  /// This phone's monotonic clock.
  final double Function() nowMs;

  /// Player clock minus this clock, or null while it is not measured yet.
  final double? Function() offsetMs;

  final void Function(GroupStatus) onStatus;

  final double hardSeekMs;
  final double nudgeAboveMs;
  final double settleBelowMs;
  final double hardSeekCooldownMs;
  final double settleMs;
  final double jumpMs;
  final double stuckAboveMs;
  final double stuckForMs;

  /// How much faster or slower to play while catching up (0.01 = 1%).
  final double speedStep;

  /// Latency adjustment in ms: positive when this phone's sound comes out late,
  /// so it is played that much ahead.
  int nudgeMs = 0;

  GroupStatus _status = const GroupStatus();
  GroupStatus get status => _status;

  int? _loadedId;
  bool _localPlaying = false;
  bool _muted = false;

  /// 1.0, or 1 - step / 1 + step while catching up.
  double _ratio = 1.0;
  double _appliedSpeed = 1.0;
  double _lastHardSeekAt = -1e9;
  double _settleUntil = -1e9;
  int _farCount = 0;
  double? _badSince;
  final List<double> _errs = [];
  GroupSync? _prev;

  bool _busy = false;
  GroupSync? _latest;
  bool _stopped = false;

  /// The newest filtered error in ms (positive = this phone is ahead).
  double? get filteredErrorMs => _errs.isEmpty ? null : _median(_errs);

  /// Where this phone's audio is right now, in ms (for calibration).
  int get positionMs => backend.position.inMilliseconds;

  bool get isPlayingAlong => _localPlaying;

  void _emit(GroupStatus s) {
    _status = s;
    onStatus(s);
  }

  /// Silences (or restores) this phone's output without stopping playback, so
  /// it stays in step. Used while measuring one phone at a time.
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    try {
      await backend.setVolume(muted ? 0.0 : 1.0);
    } catch (_) {}
  }

  static double _median(List<double> v) {
    final s = List.of(v)..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  /// Handles a Player update. Updates that arrive while one is being handled
  /// are collapsed: only the newest one is used next.
  Future<void> onSync(GroupSync m) async {
    if (_stopped) return;
    _latest = m;
    if (_busy) return;
    _busy = true;
    try {
      while (_latest != null && !_stopped) {
        final next = _latest!;
        _latest = null;
        try {
          await _handle(next);
        } catch (e) {
          _emit(_status.copyWith(
            phase: GroupPhase.problem,
            message: "Couldn't play along: ${_plain(e)}",
          ));
        }
      }
    } finally {
      _busy = false;
    }
  }

  String _plain(Object e) {
    if (e is AudioBackendException) return e.message;
    return 'something went wrong with the audio on this phone.';
  }

  void _resetTracking() {
    _errs.clear();
    _farCount = 0;
    _badSince = null;
    _ratio = 1.0;
  }

  Future<void> _handle(GroupSync m) async {
    final offset = offsetMs();
    if (offset == null) {
      _emit(_status.copyWith(
          phase: GroupPhase.syncing, message: 'Measuring the connection…'));
      return;
    }
    // Fetch the next song ahead of time so changing songs is seamless.
    final next = m.nextSongId;
    if (next != null && audio.pathIfReady(next) == null) unawaited(audio.fetch(next));

    final prev = _prev;
    _prev = m;

    final id = m.songId;
    if (id == null) {
      await _pauseLocal();
      _resetTracking();
      _emit(_status.copyWith(
        phase: GroupPhase.idle,
        message: 'Waiting for the Player to play a song from its library.',
        clearDrift: true,
        clearWarning: true,
      ));
      return;
    }

    final path = audio.pathIfReady(id);
    if (path == null) {
      unawaited(audio.fetch(id));
      await _pauseLocal();
      _resetTracking();
      final failure = audio.failureOf(id);
      if (failure != null) {
        _emit(_status.copyWith(
            phase: GroupPhase.problem, message: failure, clearDrift: true));
      } else {
        final p = audio.progressOf(id);
        _emit(_status.copyWith(
          phase: GroupPhase.downloading,
          message: p == null
              ? 'Getting the song from the Player…'
              : 'Getting the song from the Player… ${(p * 100).round()}%',
          clearDrift: true,
        ));
      }
      return;
    }

    if (_loadedId != id) {
      await _pauseLocal();
      await backend.load(path);
      _loadedId = id;
      _resetTracking();
      await _applySpeed(m.speed);
    }

    if (!m.playing) {
      // Paused on the Player: wait at the same spot, ready to go.
      await _pauseLocal();
      _resetTracking();
      final target = m.positionMs;
      if ((backend.position.inMilliseconds - target).abs() > 60) {
        await backend.seek(Duration(milliseconds: math.max(0, target)));
      }
      _emit(_status.copyWith(
          phase: GroupPhase.idle,
          message: 'Paused with the Player.',
          clearDrift: true,
          clearWarning: true));
      return;
    }

    double expected() =>
        m.positionMs + ((nowMs() + offset) - m.atMs) * m.speed + nudgeMs;

    Future<void> seekToExpected() async {
      await backend.seek(Duration(milliseconds: math.max(0, expected().round())));
      _lastHardSeekAt = nowMs();
      _settleUntil = nowMs() + settleMs;
      _resetTracking();
      await _applySpeed(m.speed);
    }

    if (!_localPlaying) {
      await backend.seek(Duration(milliseconds: math.max(0, expected().round())));
      await _applySpeed(m.speed * _ratio);
      await backend.play();
      _localPlaying = true;
      _lastHardSeekAt = nowMs();
      _settleUntil = nowMs() + settleMs;
      _resetTracking();
      _emit(_status.copyWith(
          phase: GroupPhase.playing, message: '', clearDrift: true, clearWarning: true));
      return;
    }

    // The Player jumped (someone seeked there): follow at once, not after a
    // second or two of measuring.
    if (prev != null && prev.songId == m.songId && prev.playing) {
      final predicted = prev.positionMs + (m.atMs - prev.atMs) * prev.speed;
      if ((m.positionMs - predicted).abs() > jumpMs) {
        await seekToExpected();
        _emit(_status.copyWith(phase: GroupPhase.playing, message: '', clearDrift: true));
        return;
      }
    }

    final err = backend.position.inMilliseconds - expected(); // + means ahead
    if (nowMs() < _settleUntil) {
      // The engine's position is unsettled just after a start or a jump.
      _emit(_status.copyWith(phase: GroupPhase.playing, message: '', driftMs: err));
      return;
    }

    _errs.add(err);
    if (_errs.length > 5) _errs.removeAt(0);
    final filtered = _median(_errs);

    // Far off, twice in a row: jump.
    _farCount = err.abs() > hardSeekMs ? _farCount + 1 : 0;
    if (_farCount >= 2 && nowMs() - _lastHardSeekAt >= hardSeekCooldownMs) {
      await seekToExpected();
      _emit(_status.copyWith(phase: GroupPhase.playing, message: '', driftMs: err));
      return;
    }

    var ratio = _ratio;
    if (filtered > nudgeAboveMs) {
      ratio = 1.0 - speedStep; // ahead: slow down a little
    } else if (filtered < -nudgeAboveMs) {
      ratio = 1.0 + speedStep; // behind: speed up a little
    } else if (filtered.abs() < settleBelowMs) {
      ratio = 1.0;
    }
    _ratio = ratio;
    await _applySpeed(m.speed * ratio);

    // If it cannot get close for a long time, say so.
    if (filtered.abs() > stuckAboveMs) {
      _badSince ??= nowMs();
    } else {
      _badSince = null;
    }
    final stuck = _badSince != null && nowMs() - _badSince! >= stuckForMs;
    _emit(_status.copyWith(
      phase: GroupPhase.playing,
      message: '',
      driftMs: filtered,
      warning: stuck
          ? "Can't stay in step (about ${filtered.abs().round()} ms off). "
              'Check the Wi-Fi, keep both phones close to the router, or use '
              'Auto-align.'
          : null,
      clearWarning: !stuck,
    ));
  }

  Future<void> _applySpeed(double speed) async {
    if ((speed - _appliedSpeed).abs() < 1e-6) return;
    _appliedSpeed = speed;
    await backend.setSpeed(speed.clamp(0.5, 2.0));
  }

  Future<void> _pauseLocal() async {
    if (_localPlaying) {
      await backend.pause();
      _localPlaying = false;
    }
  }

  /// Stops playing and forgets the loaded song (leaving the group).
  Future<void> stop() async {
    _stopped = true;
    _latest = null;
    try {
      await _pauseLocal();
    } catch (_) {}
    if (_muted) await setMuted(false);
    _loadedId = null;
    _prev = null;
  }

  /// Ready for a new run after [stop].
  void reset() {
    _stopped = false;
    _loadedId = null;
    _localPlaying = false;
    _ratio = 1.0;
    _appliedSpeed = 1.0;
    _prev = null;
    _resetTracking();
    _status = const GroupStatus();
  }
}
