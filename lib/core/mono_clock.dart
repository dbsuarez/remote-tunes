/// A clock that only moves forward and is not affected by the user or the
/// network changing the phone's time. Group play measures time with this, never
/// with the wall clock. Each phone's clock starts at its own zero, so two
/// phones' readings are only comparable after a clock-offset estimate.
abstract class MonoClock {
  /// Milliseconds since this app process started clocking (fractions kept).
  double nowMs();

  static final MonoClock instance = _StopwatchClock();
}

class _StopwatchClock implements MonoClock {
  final Stopwatch _watch = Stopwatch()..start();

  @override
  double nowMs() => _watch.elapsedMicroseconds / 1000.0;
}
