import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/player/sleep_timer.dart';

void main() {
  test('off at first', () {
    final t = SleepTimerService(onFire: () async {});
    expect(t.secondsLeft, 0);
    expect(t.isRunning, isFalse);
    t.dispose();
  });

  test('counts down, pauses at the end and says so', () {
    fakeAsync((async) {
      var fired = 0;
      final seen = <int>[];
      final t = SleepTimerService(onFire: () async => fired++, now: async.getClock(DateTime(2026)).now);
      t.changes.listen(seen.add);
      t.set(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(t.isRunning, isTrue);
      expect(t.secondsLeft, 60);
      async.elapse(const Duration(seconds: 30));
      expect(t.secondsLeft, 30);
      async.elapse(const Duration(seconds: 31));
      async.flushMicrotasks();
      expect(fired, 1);
      expect(t.isRunning, isFalse);
      expect(seen, [60, 0]);
      t.dispose();
    });
  });

  test('setting it again restarts it; null or zero cancels it', () {
    fakeAsync((async) {
      var fired = 0;
      final t = SleepTimerService(onFire: () async => fired++, now: async.getClock(DateTime(2026)).now);
      t.set(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 50));
      t.set(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 50));
      expect(fired, 0, reason: 'restarted, so not yet');
      t.set(null);
      async.elapse(const Duration(minutes: 5));
      expect(fired, 0);
      expect(t.secondsLeft, 0);
      t.set(Duration.zero);
      expect(t.isRunning, isFalse);
      t.dispose();
    });
  });

  test('a failing pause does not break it', () {
    fakeAsync((async) {
      final t = SleepTimerService(onFire: () async => throw StateError('x'), now: async.getClock(DateTime(2026)).now);
      t.set(const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(t.isRunning, isFalse);
      t.dispose();
    });
  });
}
