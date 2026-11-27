import 'dart:async';

/// The sleep timer: pauses playback after a time. One instance is shared by
/// the Player server (for Controllers) and this phone's own screens, so the
/// timer is the same whoever set it.
///
/// It can let the last song finish: when the time is up the player is asked to stop after it.
class SleepTimerService {
  SleepTimerService({required this.onFire, this.afterSong, this.cancelAfterSong, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Asks the player to pause once the song playing ends, calling [done] then. False if it cannot
  /// (nothing playing, a stream with no end): it is paused at once instead.
  final Future<bool> Function(void Function() done)? afterSong;
  final void Function()? cancelAfterSong;

  bool _finishSong = false;
  bool _waiting = false;

  /// The time is up and the last song is being played to its end.
  bool get finishingSong => _waiting;

  /// Changes with every [set], so an answer that comes late is not used.
  int _round = 0;

  final DateTime Function() _now;

  /// Called when the time is up (pauses playback).
  final Future<void> Function() onFire;

  Timer? _timer;
  DateTime? _endsAt;
  final StreamController<int> _changes = StreamController<int>.broadcast();

  /// Fires with the seconds left whenever the timer is set, cancelled or ends.
  Stream<int> get changes => _changes.stream;

  /// Seconds left (rounded up), 0 when it is off.
  int get secondsLeft {
    final end = _endsAt;
    if (end == null) return 0;
    final ms = end.difference(_now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  bool get isRunning => _endsAt != null;

  /// Starts the timer for [d], or with null cancels it. With [finishSong] the song playing when the
  /// time is up is played to its end.
  void set(Duration? d, {bool finishSong = false}) {
    _round++;
    _finishSong = finishSong;
    _stopWaiting();
    _timer?.cancel();
    _timer = null;
    _endsAt = (d == null || d <= Duration.zero) ? null : _now().add(d);
    if (_endsAt != null) {
      _timer = Timer(d!, () async {
        _endsAt = null;
        _timer = null;
        await _timeUp();
      });
    }
    if (!_changes.isClosed) _changes.add(secondsLeft);
  }

  Future<void> _timeUp() async {
    final round = _round;
    final ask = afterSong;
    if (_finishSong && ask != null) {
      _waiting = true;
      var willStop = false;
      try {
        willStop = await ask(() {
          if (round != _round) return;
          _waiting = false;
          if (!_changes.isClosed) _changes.add(0);
        });
      } catch (_) {}
      if (round != _round) return;
      if (willStop) {
        if (!_changes.isClosed) _changes.add(0);
        return;
      }
      _waiting = false;
    }
    try {
      await onFire();
    } catch (_) {}
    if (!_changes.isClosed) _changes.add(0);
  }

  void _stopWaiting() {
    if (!_waiting) return;
    _waiting = false;
    cancelAfterSong?.call();
  }

  void dispose() {
    _round++;
    _timer?.cancel();
    _timer = null;
    _endsAt = null;
    _changes.close();
  }
}
