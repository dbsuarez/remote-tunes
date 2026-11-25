import 'dart:async';

/// The sleep timer: pauses playback after a time. One instance is shared by
/// the Player server (for Controllers) and this phone's own screens, so the
/// timer is the same whoever set it.
class SleepTimerService {
  SleepTimerService({required this.onFire, DateTime Function()? now})
      : _now = now ?? DateTime.now;

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

  /// Starts the timer for [d], or with null cancels it.
  void set(Duration? d) {
    _timer?.cancel();
    _timer = null;
    _endsAt = (d == null || d <= Duration.zero) ? null : _now().add(d);
    if (_endsAt != null) {
      _timer = Timer(d!, () async {
        _endsAt = null;
        _timer = null;
        try {
          await onFire();
        } catch (_) {}
        if (!_changes.isClosed) _changes.add(0);
      });
    }
    if (!_changes.isClosed) _changes.add(secondsLeft);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _endsAt = null;
    _changes.close();
  }
}
