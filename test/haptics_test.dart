import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/haptics.dart';
import 'package:remote_tunes/core/widgets/haptic_button.dart';
import 'package:remote_tunes/core/widgets/playback_widgets.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';

void main() {
  final log = <String>[];

  setUp(() {
    log.clear();
    Haptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') log.add('${call.arguments}');
      return null;
    });
  });

  tearDown(() {
    Haptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('the three kinds of tap', () {
    testWidgets('each kind gives its own feedback', (tester) async {
      Haptics.medium();
      Haptics.light();
      Haptics.selection();
      expect(log, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.selectionClick',
      ]);
    });

    testWidgets('switched off, nothing happens', (tester) async {
      Haptics.enabled = false;
      Haptics.medium();
      Haptics.light();
      Haptics.selection();
      expect(log, isEmpty);
    });
  });

  group('HapticButton', () {
    testWidgets('a press gives the chosen feedback and then does its job', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(host(HapticButton(
        kind: HapticKind.medium,
        tooltip: 'Go',
        icon: const Icon(Icons.play_arrow),
        onPressed: () => pressed++,
      )));
      await tester.tap(find.byTooltip('Go'));
      expect(pressed, 1);
      expect(log, ['HapticFeedbackType.mediumImpact']);
    });

    testWidgets('a disabled button does nothing and feels like nothing', (tester) async {
      await tester.pumpWidget(host(const HapticButton(
        tooltip: 'Go',
        icon: Icon(Icons.play_arrow),
        onPressed: null,
      )));
      await tester.tap(find.byTooltip('Go'), warnIfMissed: false);
      expect(log, isEmpty);
      expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    });

    testWidgets('with feedback switched off it still works, silently', (tester) async {
      Haptics.enabled = false;
      var pressed = 0;
      await tester.pumpWidget(host(HapticButton(
        tooltip: 'Go',
        icon: const Icon(Icons.play_arrow),
        onPressed: () => pressed++,
      )));
      await tester.tap(find.byTooltip('Go'));
      expect(pressed, 1);
      expect(log, isEmpty);
    });

    testWidgets('the filled style has a background fill, the plain one has none',
        (tester) async {
      Color? fillOf() => tester
          .widget<Material>(find
              .descendant(of: find.byType(IconButton), matching: find.byType(Material))
              .first)
          .color;
      await tester.pumpWidget(host(HapticButton(
        filled: true,
        tooltip: 'Go',
        icon: const Icon(Icons.play_arrow),
        onPressed: () {},
      )));
      await tester.pumpAndSettle();
      final filled = fillOf();
      await tester.pumpWidget(host(HapticButton(
        tooltip: 'Go',
        icon: const Icon(Icons.play_arrow),
        onPressed: () {},
      )));
      await tester.pumpAndSettle();
      final plain = fillOf();
      expect(filled, isNot(plain));
    });
  });

  group('the transport buttons', () {
    testWidgets('play is a firm tap; previous and next are light', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(host(TransportControls(
        isPlaying: false,
        enabled: true,
        onPrevious: () => calls.add('prev'),
        onToggle: () => calls.add('toggle'),
        onNext: () => calls.add('next'),
      )));
      await tester.tap(find.byTooltip('Play'));
      await tester.tap(find.byTooltip('Previous'));
      await tester.tap(find.byTooltip('Next'));
      expect(calls, ['toggle', 'prev', 'next']);
      expect(log, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.lightImpact',
      ]);
    });

    testWidgets('buttons that cannot be used (the other app forbids skipping) are silent',
        (tester) async {
      await tester.pumpWidget(host(TransportControls(
        isPlaying: true,
        enabled: true,
        canSkip: false,
        onPrevious: () {},
        onToggle: () {},
        onNext: () {},
      )));
      await tester.tap(find.byTooltip('Next'), warnIfMissed: false);
      await tester.tap(find.byTooltip('Previous'), warnIfMissed: false);
      expect(log, isEmpty);
    });

    testWidgets('while disconnected nothing is felt', (tester) async {
      await tester.pumpWidget(host(TransportControls(
        isPlaying: false,
        enabled: false,
        onPrevious: () {},
        onToggle: () {},
        onNext: () {},
      )));
      await tester.tap(find.byTooltip('Play'), warnIfMissed: false);
      expect(log, isEmpty);
    });
  });

  group('the sliders', () {
    testWidgets('letting go of the volume slider gives a small click', (tester) async {
      await tester.pumpWidget(host(SizedBox(
        width: 400,
        child: VolumeSlider(volume: 0.5, enabled: true, onChanged: (_) {}),
      )));
      final box = tester.getRect(find.byType(Slider));
      await tester.tapAt(Offset(box.left + box.width * 0.8, box.center.dy));
      await tester.pump(const Duration(milliseconds: 300));
      expect(log, contains('HapticFeedbackType.selectionClick'));
    });
  });

  group('the setting', () {
    test('is on unless it is switched off', () {
      expect(const AppSettings().hapticsEnabled, isTrue);
      expect(AppSettings.fromMap(const {}).hapticsEnabled, isTrue);
      expect(AppSettings.fromMap(const {'haptics_enabled': 'true'}).hapticsEnabled, isTrue);
      expect(AppSettings.fromMap(const {'haptics_enabled': 'false'}).hapticsEnabled, isFalse);
    });

    test('the album-art colors setting works the same way', () {
      expect(AppSettings.fromMap(const {}).accentFromArt, isTrue);
      expect(AppSettings.fromMap(const {'accent_from_art': 'false'}).accentFromArt, isFalse);
    });
  });
}
