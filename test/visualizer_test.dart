import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/player/visualizer.dart';

const _channel = MethodChannel('remotetunes/visualizer');

/// Plays the part of Android's side: records what the app asks, and can send bars.
class _Native {
  final calls = <String>[];
  bool startWorks = true;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        calls.add(call.method == 'start' ? 'start:${(call.arguments as Map)['session']}' : call.method);
        return call.method == 'start' ? startWorks : null;
      },
    );
  }

  Future<void> sendBars(List<double> bars) async {
    final data = const StandardMethodCodec().encodeMethodCall(MethodCall('bars', bars));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('remotetunes/visualizer', data, (_) {});
  }

  void remove() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Native native;
  int? session;
  var allowed = true;

  VisualizerService make() => VisualizerService(
        hasPermission: () async => allowed,
        sessionId: () => session,
        barCount: 4,
        checkEvery: const Duration(milliseconds: 20),
      );

  setUp(() {
    native = _Native()..install();
    session = 7;
    allowed = true;
  });
  tearDown(() => native.remove());

  Future<void> wait([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));

  test('starts on the sound\'s session and stops when told', () async {
    final v = make();
    await v.start();
    expect(native.calls, ['start:7']);
    await v.stop();
    expect(native.calls.last, 'stop');
    await v.dispose();
  });

  test('without the microphone permission it does not start and says why', () async {
    allowed = false;
    final v = make();
    await v.start();
    expect(native.calls, isEmpty);
    expect(v.problem.value, 'permission');
    await v.dispose();
  });

  test('a phone that refuses is reported, not retried every moment', () async {
    native.startWorks = false;
    final v = make();
    await v.start();
    expect(v.problem.value, 'unavailable');
    await wait();
    expect(native.calls.where((c) => c.startsWith('start')).length, 1);
    await v.dispose();
  });

  test('nothing is started until the sound has an id; it attaches once it has one', () async {
    session = null;
    final v = make();
    await v.start();
    expect(native.calls, isEmpty);
    session = 3;
    await wait();
    expect(native.calls, ['start:3']);
    await v.dispose();
  });

  test('when the song changes to the other player it follows the new sound', () async {
    final v = make();
    await v.start();
    session = 9;
    await wait();
    expect(native.calls.where((c) => c.startsWith('start')).toList(), ['start:7', 'start:9']);
    await v.dispose();
  });

  test('bars rise at once and fall slowly', () async {
    final v = make();
    await v.start();
    await native.sendBars([1, 0.5, 0, 0]);
    expect(v.bars.value, [1, 0.5, 0, 0]);
    await native.sendBars([0, 0, 0, 0]);
    expect(v.bars.value[0], greaterThan(0.7), reason: 'it eases down');
    expect(v.bars.value[0], lessThan(1));
    await native.sendBars([0.2, 2, -1, 0]); // out-of-range numbers are kept in range
    expect(v.bars.value[1], 1);
    expect(v.bars.value[2], 0);
    await v.dispose();
  });

  testWidgets('the strip follows the music: it listens while playing, lets go when paused',
      (tester) async {
    final v = make();
    Widget strip(bool playing) =>
        MaterialApp(home: Scaffold(body: VisualizerStrip(isPlaying: playing, service: v)));
    await tester.pumpWidget(strip(true));
    await tester.runAsync(() => wait());
    expect(native.calls, contains('start:7'));
    await tester.pumpWidget(strip(false));
    await tester.runAsync(() => wait());
    expect(native.calls.last, 'stop');
    expect(find.byKey(const Key('visualizer-bars')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without the permission the strip explains instead of showing dead bars',
      (tester) async {
    allowed = false;
    final v = make();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: VisualizerStrip(isPlaying: true, service: v))));
    await tester.runAsync(() => wait());
    await tester.pump();
    expect(find.textContaining('microphone permission'), findsOneWidget);
    expect(find.byKey(const Key('visualizer-bars')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
