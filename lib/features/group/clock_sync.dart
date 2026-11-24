/// Estimates how far the Player's clock is ahead of this phone's clock, the
/// NTP way: a probe goes out at `t0` (this clock), reaches the Player at `t1`
/// and is answered at `t2` (the Player's clock), and arrives back at `t3`
/// (this clock). Then
///
///   offset = ((t1 - t0) + (t2 - t3)) / 2     (Player clock minus this clock)
///   round trip = (t3 - t0) - (t2 - t1)
///
/// A single probe can be wrong by up to half its round trip, and Wi-Fi round
/// trips vary a lot. So many probes are taken, the slower half (by round trip)
/// is thrown away, and the median of the rest is used.
///
/// Pure Dart; all times are milliseconds on a monotonic clock.
class ClockSync {
  ClockSync({this.maxSamples = 24, this.minSamples = 5});

  final int maxSamples;

  /// Fewer probes than this and there is no estimate yet.
  final int minSamples;

  final List<({double offset, double rtt})> _samples = [];

  int get sampleCount => _samples.length;
  bool get ready => _samples.length >= minSamples;

  /// Adds one probe. A reply that makes no sense (negative round trip) is
  /// ignored.
  void add(double t0, double t1, double t2, double t3) {
    final rtt = (t3 - t0) - (t2 - t1);
    if (rtt < 0 || t3 < t0 || t2 < t1) return;
    _samples.add((offset: ((t1 - t0) + (t2 - t3)) / 2, rtt: rtt));
    if (_samples.length > maxSamples) _samples.removeAt(0);
  }

  void clear() => _samples.clear();

  List<({double offset, double rtt})> get _fastest {
    final sorted = List.of(_samples)..sort((a, b) => a.rtt.compareTo(b.rtt));
    final keep = (sorted.length / 2).ceil().clamp(1, sorted.length);
    return sorted.take(keep).toList();
  }

  static double _median(List<double> v) {
    final s = List.of(v)..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  /// Player clock minus this clock, in ms, or null until [ready].
  double? get offsetMs =>
      ready ? _median([for (final s in _fastest) s.offset]) : null;

  /// A typical round trip of the good probes, in ms.
  double? get rttMs => ready ? _median([for (final s in _fastest) s.rtt]) : null;

  /// How much the good probes disagree (max - min offset), in ms. Small means
  /// the estimate can be trusted.
  double? get spreadMs {
    if (!ready) return null;
    final o = [for (final s in _fastest) s.offset];
    o.sort();
    return o.last - o.first;
  }
}
