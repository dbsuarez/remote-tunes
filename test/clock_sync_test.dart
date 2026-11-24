import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/group/clock_sync.dart';

/// Simulates one probe. The Player's clock is `trueOffset` ahead of ours. The
/// way there takes `out` ms and the way back `back` ms; the Player takes
/// `think` ms to answer.
void probe(ClockSync s, double t0, double trueOffset, double out, double back,
    {double think = 0.3}) {
  final t1 = t0 + out + trueOffset;
  final t2 = t1 + think;
  final t3 = t0 + out + think + back;
  s.add(t0, t1, t2, t3);
}

void main() {
  test('no estimate until there are enough probes', () {
    final s = ClockSync();
    expect(s.offsetMs, isNull);
    for (var i = 0; i < 4; i++) {
      probe(s, i * 100.0, 5000, 3, 3);
    }
    expect(s.ready, isFalse);
    expect(s.offsetMs, isNull);
    probe(s, 500, 5000, 3, 3);
    expect(s.ready, isTrue);
    expect(s.offsetMs, closeTo(5000, 0.01));
  });

  test('a symmetric link gives the exact offset, and the round trip', () {
    final s = ClockSync();
    for (var i = 0; i < 10; i++) {
      probe(s, i * 100.0, -1234.5, 4, 4);
    }
    expect(s.offsetMs, closeTo(-1234.5, 0.01));
    expect(s.rttMs, closeTo(8, 0.01));
    expect(s.spreadMs, closeTo(0, 0.01));
  });

  test('Wi-Fi jitter: the estimate stays within a few ms of the truth', () {
    final rnd = Random(42);
    final s = ClockSync();
    const truth = 86400.0;
    for (var i = 0; i < 24; i++) {
      // Usually quick, sometimes a lot slower, each direction independent.
      double leg() => 2 + rnd.nextDouble() * 4 + (rnd.nextInt(5) == 0 ? rnd.nextDouble() * 60 : 0);
      probe(s, i * 120.0, truth, leg(), leg());
    }
    expect(s.offsetMs!, closeTo(truth, 4), reason: 'within 4 ms despite spikes');
  });

  test('slow outliers do not drag the estimate (the slower half is dropped)', () {
    final s = ClockSync();
    for (var i = 0; i < 12; i++) {
      probe(s, i * 100.0, 1000, 3, 3);
    }
    // A few badly lopsided probes (a stall on the way out only).
    for (var i = 0; i < 6; i++) {
      probe(s, 2000.0 + i * 100, 1000, 180, 3);
    }
    expect(s.offsetMs, closeTo(1000, 0.5));
  });

  test('nonsense replies are ignored', () {
    final s = ClockSync();
    s.add(100, 50, 40, 90); // the Player "replied before it received"
    s.add(100, 150, 160, 90); // arrived before it was sent
    expect(s.sampleCount, 0);
  });

  test('only the newest probes are kept, so a drifting clock is followed', () {
    final s = ClockSync(maxSamples: 10, minSamples: 5);
    for (var i = 0; i < 10; i++) {
      probe(s, i * 100.0, 1000, 3, 3);
    }
    for (var i = 0; i < 10; i++) {
      probe(s, 5000.0 + i * 100, 1010, 3, 3);
    }
    expect(s.sampleCount, 10);
    expect(s.offsetMs, closeTo(1010, 0.01));
  });

  test('clear forgets everything', () {
    final s = ClockSync();
    for (var i = 0; i < 6; i++) {
      probe(s, i * 100.0, 1, 3, 3);
    }
    s.clear();
    expect(s.offsetMs, isNull);
    expect(s.sampleCount, 0);
  });

  test('the spread tells how far to trust it', () {
    final noisy = ClockSync();
    final rnd = Random(7);
    for (var i = 0; i < 20; i++) {
      probe(noisy, i * 100.0, 500, 2 + rnd.nextDouble() * 20, 2 + rnd.nextDouble() * 20);
    }
    final clean = ClockSync();
    for (var i = 0; i < 20; i++) {
      probe(clean, i * 100.0, 500, 3, 3);
    }
    expect(clean.spreadMs!, lessThan(noisy.spreadMs!));
  });
}
