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
/// sampled) * speed + nudge`, and then:
///
///  * not playing yet: seek there and start;
///  * off by more than [hardSeekMs]: seek;
///  * off by more than [nudgeAboveMs]: play 2% faster or slower until it is
///    close (no audible jump, no pitch glitch);
///  * within [settleBelowMs]: back to normal speed.
///
/// Pure logic around an [AudioBackend], so it is tested without a phone.
class GroupFollowerCore {
  GroupFollowerCore({
    required this.backend,
    required this.audio,
    required this.nowMs,
    required this.offsetMs,
    required this.onStatus,
    this.hardSeekMs = 200,
    this.nudgeAboveMs = 15,
    this.settleBelowMs = 8,
    this.hardSeekCooldownMs = 1500,
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

  /// Latency adjustment in ms: positive when this phone's sound comes out late,
  /// so it is played that much ahead.
  int nudgeMs = 0;

  GroupStatus _status = const GroupStatus();
  GroupStatus get status => _status;

  int? _loadedId;
  bool _localPlaying = false;

  /// 1.0, or 0.98 / 1.02 while catching up.
  double _ratio = 1.0;
  double _appliedSpeed = 1.0;
  double _lastHardSeekAt = -1e9;

  bool _busy = false;
  GroupSync? _latest;
  bool _stopped = false;

  void _emit(GroupStatus s) {
    _status = s;
    onStatus(s);
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

    final id = m.songId;
    if (id == null) {
      await _pauseLocal();
      _emit(_status.copyWith(
        phase: GroupPhase.idle,
        message: 'Waiting for the Player to play a song from its library.',
        clearDrift: true,
      ));
      return;
    }

    final path = audio.pathIfReady(id);
    if (path == null) {
      unawaited(audio.fetch(id));
      await _pauseLocal();
      final failure = audio.failureOf(id);
      if (failure != null) {
        _emit(_status.copyWith(phase: GroupPhase.problem, message: failure, clearDrift: true));
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
      _ratio = 1.0;
      await _applySpeed(m.speed);
    }

    if (!m.playing) {
      // Paused on the Player: wait at the same spot, ready to go.
      await _pauseLocal();
      final target = m.positionMs;
      if ((backend.position.inMilliseconds - target).abs() > 60) {
        await backend.seek(Duration(milliseconds: math.max(0, target)));
      }
      _emit(_status.copyWith(
          phase: GroupPhase.idle, message: 'Paused with the Player.', clearDrift: true));
      return;
    }

    double expected() =>
        m.positionMs + ((nowMs() + offset) - m.atMs) * m.speed + nudgeMs;

    if (!_localPlaying) {
      await backend.seek(Duration(milliseconds: math.max(0, expected().round())));
      await _applySpeed(m.speed * _ratio);
      await backend.play();
      _localPlaying = true;
      _lastHardSeekAt = nowMs();
      _emit(_status.copyWith(
          phase: GroupPhase.playing, message: '', title: _status.title, clearDrift: true));
      return;
    }

    final err = backend.position.inMilliseconds - expected(); // + means ahead
    var ratio = _ratio;
    if (err.abs() > hardSeekMs) {
      if (nowMs() - _lastHardSeekAt >= hardSeekCooldownMs) {
        await backend.seek(Duration(milliseconds: math.max(0, expected().round())));
        _lastHardSeekAt = nowMs();
      }
      ratio = 1.0;
    } else if (err > nudgeAboveMs) {
      ratio = 0.98; // ahead: slow down a little
    } else if (err < -nudgeAboveMs) {
      ratio = 1.02; // behind: speed up a little
    } else if (err.abs() < settleBelowMs) {
      ratio = 1.0;
    }
    _ratio = ratio;
    await _applySpeed(m.speed * ratio);
    _emit(_status.copyWith(phase: GroupPhase.playing, message: '', driftMs: err));
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
    _loadedId = null;
  }

  /// Ready for a new run after [stop].
  void reset() {
    _stopped = false;
    _loadedId = null;
    _localPlaying = false;
    _ratio = 1.0;
    _appliedSpeed = 1.0;
    _status = const GroupStatus();
  }
}
