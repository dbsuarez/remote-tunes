import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/screen_awake.dart';

void main() {
  late List<bool> calls;

  setUp(() {
    calls = [];
    ScreenAwake.setFlag = (on) async => calls.add(on);
  });

  test('the screen is held while the job runs and let go afterwards', () async {
    late int during;
    final r = await ScreenAwake.during(() async {
      during = ScreenAwake.holds;
      expect(calls, [true]);
      return 42;
    });
    expect(r, 42);
    expect(during, 1);
    expect(calls, [true, false]);
    expect(ScreenAwake.holds, 0);
  });

  test('it is let go even when the job fails', () async {
    await expectLater(
        ScreenAwake.during(() async => throw StateError('boom')), throwsA(isA<StateError>()));
    expect(calls, [true, false]);
    expect(ScreenAwake.holds, 0);
  });

  test('overlapping jobs hold it once, and the last one lets go', () async {
    final a = ScreenAwake.during(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    final b = ScreenAwake.during(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await a;
    expect(calls, [true], reason: 'still held by the second job');
    await b;
    expect(calls, [true, false]);
  });
}
