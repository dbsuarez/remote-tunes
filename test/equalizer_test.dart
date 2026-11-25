import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/player/eq/eq_model.dart';
import 'package:remote_tunes/features/player/eq/equalizer_controller.dart';
import 'package:remote_tunes/features/player/eq/equalizer_screen.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/memory_eq_store.dart';

const five = EqBands(minDb: -12, maxDb: 12, centersHz: [60, 230, 910, 3600, 14000]);

void main() {
  group('presets', () {
    test('flat is zero everywhere', () {
      expect(EqPreset.flat.gainsFor(five), [0, 0, 0, 0, 0]);
    });

    test('on the five usual bands a preset gives its own numbers', () {
      expect(EqPreset.byName('Bass boost')!.gainsFor(five), [6, 4, 0, 0, 0]);
      expect(EqPreset.byName('Rock')!.gainsFor(five), [4, 2, -1, 3, 4]);
    });

    test('other band counts are worked out between the anchors', () {
      const ten = EqBands(
        minDb: -12,
        maxDb: 12,
        centersHz: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000],
      );
      final g = EqPreset.byName('Bass boost')!.gainsFor(ten);
      expect(g, hasLength(10));
      expect(g.first, 6, reason: 'below the first anchor it stays at its value');
      expect(g.last, 0);
      // Falling steadily from the bass to the mids.
      for (var i = 1; i < 6; i++) {
        expect(g[i], lessThanOrEqualTo(g[i - 1] + 0.0001));
      }
    });

    test('gains are kept inside what the phone allows', () {
      const narrow = EqBands(minDb: -3, maxDb: 3, centersHz: [60, 230, 910, 3600, 14000]);
      final g = EqPreset.byName('Bass boost')!.gainsFor(narrow);
      expect(g.every((x) => x >= -3 && x <= 3), isTrue);
      expect(g.first, 3);
    });

    test('names are found, unknown ones are not', () {
      expect(EqPreset.byName('Jazz'), isNotNull);
      expect(EqPreset.byName('nope'), isNull);
      expect(EqPreset.byName(null), isNull);
    });

    test('band labels read well', () {
      expect(five.labelFor(0), '60 Hz');
      expect(five.labelFor(2), '910 Hz');
      expect(five.labelFor(3), '3.6 kHz');
      expect(five.labelFor(4), '14 kHz');
    });

    test('settings survive being saved as text; junk gives nothing', () {
      const s = EqSettings(enabled: true, preset: 'Pop', gains: [1, 2.5, 0, -1, 3]);
      final back = EqSettings.fromJson(s.toJson())!;
      expect([back.enabled, back.preset, back.gains], [true, 'Pop', [1, 2.5, 0, -1, 3]]);
      expect(EqSettings.fromJson('not json'), isNull);
      expect(EqSettings.fromJson(null), isNull);
      expect(EqSettings.fromJson('[1,2]'), isNull);
    });
  });

  group('the controller', () {
    late FakeAudioBackend backend;
    late MemoryEqStore store;
    var route = 'speaker';

    EqualizerController make() => EqualizerController(
        backend: backend, store: store, outputRoute: () async => route);

    setUp(() {
      backend = FakeAudioBackend();
      store = MemoryEqStore();
      route = 'speaker';
    });

    test('starts off and flat, and knows the phone\'s bands', () async {
      final c = make();
      await c.init();
      expect(c.bands, five);
      expect(c.settings.enabled, isFalse);
      expect(backend.eqCalls.last.enabled, isFalse);
      expect(backend.eqCalls.last.gains, [0, 0, 0, 0, 0]);
    });

    test('a phone with no equalizer has no bands and nothing breaks', () async {
      backend.eqBands = null;
      final c = make();
      await c.init();
      expect(c.bands, isNull);
      await c.setEnabled(true);
      await c.applyPreset(EqPreset.all[1]);
      expect(backend.eqCalls, isEmpty);
    });

    test('a preset switches it on and sets every band', () async {
      final c = make();
      await c.init();
      await c.applyPreset(EqPreset.byName('Bass boost')!);
      expect(c.settings.enabled, isTrue);
      expect(c.settings.preset, 'Bass boost');
      expect(backend.eqCalls.last.enabled, isTrue);
      expect(backend.eqCalls.last.gains, [6, 4, 0, 0, 0]);
    });

    test('moving a slider by hand makes it custom and stays in range', () async {
      final c = make();
      await c.init();
      await c.applyPreset(EqPreset.byName('Rock')!);
      await c.setBand(1, 50);
      expect(c.settings.preset, isNull);
      expect(c.settings.gains[1], 12);
      await c.setBand(1, -50);
      expect(c.settings.gains[1], -12);
      await c.setBand(99, 3); // no such band: ignored
      expect(c.settings.gains, hasLength(5));
    });

    test('settings are kept and come back after a restart', () async {
      final a = make();
      await a.init();
      await a.applyPreset(EqPreset.byName('Vocal')!);
      final b = make();
      await b.init();
      expect(b.settings.enabled, isTrue);
      expect(b.settings.preset, 'Vocal');
      expect(backend.eqCalls.last.gains, [-2, 0, 4, 3, -1]);
      expect(backend.eqCalls.last.enabled, isTrue);
    });

    test('reset goes back to flat', () async {
      final c = make();
      await c.init();
      await c.applyPreset(EqPreset.byName('Rock')!);
      await c.reset();
      expect(c.settings.preset, 'Flat');
      expect(backend.eqCalls.last.gains, [0, 0, 0, 0, 0]);
    });

    test('saved gains for another number of bands are rebuilt from the preset', () async {
      store.values['eq_default'] =
          const EqSettings(enabled: true, preset: 'Bass boost', gains: [1, 2, 3]).toJson();
      final c = make();
      await c.init();
      expect(c.settings.gains, [6, 4, 0, 0, 0]);
    });

    group('per output', () {
      test('what is remembered for the speaker is used when the sound is on the speaker',
          () async {
        final c = make();
        await c.init();
        await c.applyPreset(EqPreset.byName('Bass boost')!);
        await c.setSavedForOutput(true);
        expect(c.savedForOutput, isTrue);
        expect(store.values.containsKey('eq_output_speaker'), isTrue);
      });

      test('another output has its own settings, and switching applies them', () async {
        final c = make();
        await c.init();
        await c.applyPreset(EqPreset.byName('Bass boost')!);
        await c.setSavedForOutput(true); // for the speaker
        route = 'bluetooth';
        await c.refreshOutput();
        expect(c.output, 'bluetooth');
        expect(c.savedForOutput, isFalse);
        // Nothing saved for it: it uses the general settings (bass boost).
        expect(c.settings.preset, 'Bass boost');
        await c.applyPreset(EqPreset.byName('Treble boost')!);
        await c.setSavedForOutput(true);
        route = 'speaker';
        await c.refreshOutput();
        expect(c.settings.preset, 'Bass boost', reason: 'back to the speaker\'s own');
        expect(backend.eqCalls.last.gains, [6, 4, 0, 0, 0]);
        route = 'bluetooth';
        await c.refreshOutput();
        expect(c.settings.preset, 'Treble boost');
      });

      test('changes while an output is remembered are kept for it', () async {
        final c = make();
        await c.init();
        await c.setSavedForOutput(true);
        await c.applyPreset(EqPreset.byName('Pop')!);
        final saved = EqSettings.fromJson(store.values['eq_output_speaker'])!;
        expect(saved.preset, 'Pop');
      });

      test('forgetting an output removes only its settings', () async {
        final c = make();
        await c.init();
        await c.applyPreset(EqPreset.byName('Jazz')!);
        await c.setSavedForOutput(true);
        await c.setSavedForOutput(false);
        expect(store.values.containsKey('eq_output_speaker'), isFalse);
        expect(store.values.containsKey('eq_default'), isTrue);
      });

      test('an output that cannot be read is just "unknown"', () async {
        final c = EqualizerController(
            backend: backend, store: store, outputRoute: () async => throw StateError('x'));
        await c.init();
        expect(c.output, 'unknown');
      });
    });
  });

  group('the screen', () {
    late FakeAudioBackend backend;
    late EqualizerController c;

    Future<void> open(WidgetTester tester, {bool init = true}) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend = FakeAudioBackend();
      c = EqualizerController(
          backend: backend, store: MemoryEqStore(), outputRoute: () async => 'bluetooth');
      if (init) await tester.runAsync(() => c.init());
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: EqualizerView(controller: c)),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('shows a switch, the presets and a slider for each band', (tester) async {
      await open(tester);
      expect(find.text('Equalizer'), findsOneWidget);
      expect(find.text('Bass boost'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(5));
      for (final l in ['60 Hz', '910 Hz', '3.6 kHz', '14 kHz']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
    });

    testWidgets('a preset chip sets the sliders and switches it on', (tester) async {
      await open(tester);
      await tester.tap(find.text('Bass boost'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(c.settings.enabled, isTrue);
      expect(find.text('+6.0'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    });

    testWidgets('dragging a slider makes it Custom', (tester) async {
      await open(tester);
      await tester.tap(find.text('Rock'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(-5);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('the output switch names where the sound goes', (tester) async {
      await open(tester);
      expect(find.text('Remember for Bluetooth'), findsOneWidget);
      await tester.tap(find.text('Remember for Bluetooth'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(c.savedForOutput, isTrue);
    });

    testWidgets('before a song has played it says what to do', (tester) async {
      backend = FakeAudioBackend()..eqBands = null;
      c = EqualizerController(
          backend: backend, store: MemoryEqStore(), outputRoute: () async => 'speaker');
      await tester.runAsync(() => c.init());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: EqualizerView(controller: c))));
      await tester.pump();
      expect(find.textContaining('once a song has been played'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('Reset to flat', (tester) async {
      await open(tester);
      await tester.tap(find.text('Rock'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      await tester.tap(find.text('Reset to flat'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(c.settings.preset, 'Flat');
    });
  });
}
