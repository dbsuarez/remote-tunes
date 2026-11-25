import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/player/eq/eq_model.dart';
import 'package:remote_tunes/features/player/eq/equalizer_controller.dart';
import 'package:remote_tunes/features/player/eq/equalizer_screen.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/memory_eq_store.dart';

void main() {
  group('the levels', () {
    test('off does nothing; the others get stronger', () {
      expect(CompressorLevel.off.on, isFalse);
      final on = [CompressorLevel.light, CompressorLevel.medium, CompressorLevel.strong];
      expect(on.every((l) => l.on), isTrue);
      for (var i = 1; i < on.length; i++) {
        expect(on[i].ratio, greaterThan(on[i - 1].ratio));
        expect(on[i].thresholdDb, lessThan(on[i - 1].thresholdDb), reason: 'it starts working sooner');
        expect(on[i].attackMs, lessThan(on[i - 1].attackMs));
        expect(on[i].makeupDb, greaterThan(on[i - 1].makeupDb), reason: 'and is turned back up more');
      }
    });

    test('every level keeps its numbers inside what Android accepts', () {
      for (final l in CompressorLevel.values) {
        expect(l.ratio, inInclusiveRange(1, 20));
        expect(l.thresholdDb, inInclusiveRange(-80, 0));
        expect(l.attackMs, inInclusiveRange(0, 500));
        expect(l.releaseMs, inInclusiveRange(10, 5000));
        expect(l.makeupDb, inInclusiveRange(0, 24));
      }
    });

    test('a name is read back; nothing or nonsense is off', () {
      expect(CompressorLevel.parse('medium'), CompressorLevel.medium);
      expect(CompressorLevel.parse(null), CompressorLevel.off);
      expect(CompressorLevel.parse('loud'), CompressorLevel.off);
    });

    test('the level is part of the saved settings, and older saved settings read as off', () {
      const s = EqSettings(compressor: 'strong');
      expect(EqSettings.fromJson(s.toJson())!.compressorLevel, CompressorLevel.strong);
      expect(EqSettings.fromJson('{"enabled":true}')!.compressorLevel, CompressorLevel.off);
      expect(EqSettings.fromJson('{"compressor":"bogus"}')!.compressor, 'off');
      expect(s.copyWith(enabled: true).compressor, 'strong', reason: 'other changes keep it');
    });
  });

  group('the controller', () {
    late FakeAudioBackend backend;
    late MemoryEqStore store;

    EqualizerController make() =>
        EqualizerController(backend: backend, store: store, outputRoute: () async => 'speaker');

    setUp(() {
      backend = FakeAudioBackend();
      store = MemoryEqStore();
    });

    test('starts off', () async {
      final c = make();
      await c.init();
      expect(c.settings.compressorLevel, CompressorLevel.off);
      expect(backend.trueCalls.last.compressor, CompressorLevel.off);
    });

    test('a level is sent to the effect, also with the equalizer switched off', () async {
      final c = make();
      await c.init();
      expect(c.settings.enabled, isFalse);
      await c.setCompressor(CompressorLevel.medium);
      final call = backend.trueCalls.last;
      expect(call.compressor, CompressorLevel.medium);
      expect(call.enabled, isFalse, reason: 'the equalizer stage stays off');
      expect(call.gains.every((g) => g == 0), isTrue);
      expect(backend.trueEqualizerActive, isTrue, reason: 'the effect is running for the compressor');
    });

    test('with the ten bands on, both go to the effect together', () async {
      final c = make();
      await c.init();
      await c.setTenBand(true);
      await c.setEnabled(true);
      await c.setCompressor(CompressorLevel.light);
      final call = backend.trueCalls.last;
      expect((call.enabled, call.compressor), (true, CompressorLevel.light));
    });

    test('back to off turns it off again', () async {
      final c = make();
      await c.init();
      await c.setCompressor(CompressorLevel.strong);
      await c.setCompressor(CompressorLevel.off);
      expect(backend.trueCalls.last.compressor, CompressorLevel.off);
    });

    test('it is remembered, and comes back after a restart', () async {
      final c = make();
      await c.init();
      await c.setCompressor(CompressorLevel.medium);
      final again = make();
      await again.init();
      expect(again.settings.compressorLevel, CompressorLevel.medium);
      expect(backend.trueCalls.last.compressor, CompressorLevel.medium);
    });

    test('a phone that refuses the effect does not break anything', () async {
      backend.trueEqSupported = false;
      final c = make();
      await c.init();
      await c.setCompressor(CompressorLevel.strong);
      expect(c.settings.compressorLevel, CompressorLevel.strong, reason: 'the choice is kept');
      expect(backend.trueEqualizerActive, isFalse);
    });
  });

  group('the screen', () {
    late FakeAudioBackend backend;
    late EqualizerController c;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend = FakeAudioBackend();
      c = EqualizerController(backend: backend, store: MemoryEqStore(), outputRoute: () async => 'speaker');
      await tester.runAsync(() => c.init());
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: EqualizerView(controller: c)),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('has a Compressor section with Off, Light, Medium and Strong; Off is chosen', (tester) async {
      await open(tester);
      expect(find.text('Compressor'), findsOneWidget);
      for (final l in CompressorLevel.values) {
        expect(find.byKey(ValueKey('compressor-${l.name}')), findsOneWidget, reason: l.name);
      }
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('compressor-off'))).selected, isTrue);
      expect(find.text('The music as it is'), findsOneWidget);
    });

    testWidgets('choosing a level applies it and says what it does', (tester) async {
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('compressor-medium')));
      await tester.tap(find.byKey(const ValueKey('compressor-medium')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(c.settings.compressorLevel, CompressorLevel.medium);
      expect(backend.trueCalls.last.compressor, CompressorLevel.medium);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('compressor-medium'))).selected, isTrue);
      expect(find.text('Good for quiet listening and for talk'), findsOneWidget);
    });
  });
}
