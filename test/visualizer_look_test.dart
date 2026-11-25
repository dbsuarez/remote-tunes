import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/player/visualizer_look.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('shaping what Android reports', () {
    test('the treble bars are lifted and the bass bars eased, so all of them move', () {
      expect(VisualizerShaper.tilt(0, 24), closeTo(0.8, 1e-9));
      expect(VisualizerShaper.tilt(23, 24), closeTo(1.25, 1e-9));
      expect(VisualizerShaper.tilt(5, 24), lessThan(VisualizerShaper.tilt(15, 24)));
    });

    test('a quiet song and a loud one fill the display the same way', () {
      final quiet = VisualizerShaper().shape([0.4, 0.3, 0.2, 0.1]);
      final loud = VisualizerShaper().shape([1.0, 0.75, 0.5, 0.25]);
      expect(quiet.reduce((a, b) => a > b ? a : b), greaterThan(0.9));
      for (var i = 0; i < 4; i++) {
        expect(quiet[i], closeTo(loud[i], 0.12));
      }
    });

    test('silence stays flat, and noise under the floor is cut', () {
      final s = VisualizerShaper();
      expect(s.shape(List.filled(8, 0.0)).every((v) => v == 0), isTrue);
      expect(s.shape(List.filled(8, 0.02)).every((v) => v == 0), isTrue,
          reason: 'a hiss is not music');
    });

    test('the loudness it follows is forgotten slowly, so a quiet part after a loud one dips',
        () {
      final s = VisualizerShaper();
      s.shape([1, 1, 1, 1]);
      final after = s.shape([0.3, 0.3, 0.3, 0.3]);
      expect(after.first, lessThan(0.5));
    });

    test('numbers stay between 0 and 1, and nothing in gives nothing out', () {
      final out = VisualizerShaper().shape([5, -3, 0.5, 2]);
      expect(out.every((v) => v >= 0 && v <= 1), isTrue);
      expect(VisualizerShaper().shape(const []), isEmpty);
    });
  });

  group('the movement', () {
    test('a bar rises almost at once', () {
      final a = VisualizerAnimator()..setTarget([1.0, 0.0]);
      a.step(1 / 60);
      expect(a.values[0], greaterThan(0.5));
      a.step(1 / 60);
      a.step(1 / 60);
      expect(a.values[0], greaterThan(0.9));
      expect(a.values[1], 0);
    });

    test('and falls slowly', () {
      final a = VisualizerAnimator()..setTarget([1.0]);
      for (var i = 0; i < 10; i++) {
        a.step(1 / 60);
      }
      final top = a.values[0];
      a.setTarget([0.0]);
      a.step(1 / 60);
      expect(a.values[0], lessThan(top));
      expect(a.values[0], greaterThan(top - 0.05), reason: 'one frame is a small step down');
      for (var i = 0; i < 60; i++) {
        a.step(1 / 60);
      }
      expect(a.values[0], lessThan(0.05), reason: 'about a second to fall');
    });

    test('the cap holds for a moment, then drifts down behind the bar', () {
      final a = VisualizerAnimator()..setTarget([1.0]);
      for (var i = 0; i < 10; i++) {
        a.step(1 / 60);
      }
      final cap = a.peaks[0];
      a.setTarget([0.0]);
      for (var i = 0; i < 6; i++) {
        a.step(1 / 60);
      }
      expect(a.peaks[0], cap, reason: 'held for a quarter of a second');
      for (var i = 0; i < 30; i++) {
        a.step(1 / 60);
      }
      expect(a.peaks[0], lessThan(cap));
      expect(a.peaks[0], greaterThanOrEqualTo(a.values[0]));
    });

    test('an empty reading lets everything fall in place (it does not vanish at once)', () {
      final a = VisualizerAnimator()..setTarget([1.0, 1.0, 1.0]);
      for (var i = 0; i < 10; i++) {
        a.step(1 / 60);
      }
      a.setTarget(const []);
      expect(a.values.length, 3);
      a.step(1 / 60);
      expect(a.values[0], greaterThan(0.5));
      for (var i = 0; i < 200; i++) {
        a.step(1 / 60);
      }
      expect(a.idle, isTrue);
    });
  });

  group('every style draws', () {
    for (final style in VisualizerStyle.values) {
      testWidgets('${style.label} draws without trouble at different sizes', (tester) async {
        final a = VisualizerAnimator()..setTarget([for (var i = 0; i < 24; i++) i / 23]);
        for (var i = 0; i < 8; i++) {
          a.step(1 / 60);
        }
        for (final size in const [Size(360, 72), Size(120, 72), Size(300, 150)]) {
          await tester.pumpWidget(Center(
            child: SizedBox.fromSize(
              size: size,
              child: CustomPaint(
                painter: VisualizerPainter(
                    animator: a, style: style, low: Colors.teal, high: Colors.purple),
                size: Size.infinite,
              ),
            ),
          ));
          expect(tester.takeException(), isNull);
        }
        // And with nothing to show.
        await tester.pumpWidget(CustomPaint(
          painter: VisualizerPainter(
              animator: VisualizerAnimator(),
              style: style,
              low: Colors.teal,
              high: Colors.purple),
          size: const Size(200, 60),
        ));
        expect(tester.takeException(), isNull);
      });
    }

    test('a style is found by its saved name, and an unknown one is Bars', () {
      expect(VisualizerStyle.byName('circle'), VisualizerStyle.circle);
      expect(VisualizerStyle.byName('nothing'), VisualizerStyle.bars);
      expect(VisualizerStyle.byName(null), VisualizerStyle.bars);
    });
  });

  test('the chosen style is remembered', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SettingsRepository(db);
    expect((await repo.load()).visualizerStyle, 'bars');
    await repo.setVisualizerStyle('wave');
    expect((await repo.load()).visualizerStyle, 'wave');
  });
}
