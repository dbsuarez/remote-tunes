import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/visualizer_position.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/music/lyrics_view.dart';

Widget host({Widget? overlay, Alignment align = Alignment.center}) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: CoverWithLyrics(
            cover: Container(key: const Key('cover'), color: Colors.purple),
            size: 320,
            radius: 20,
            songId: 5,
            positionSeconds: 0,
            isPlaying: false,
            fetch: (_) async => const RemoteLyrics(found: true, plain: 'La la', source: 'x'),
            overlay: overlay,
            overlayAlignment: align,
          ),
        ),
      ),
    );

void main() {
  const viz = SizedBox(key: Key('viz'), height: 72);

  testWidgets('with the setting on, the visualizer sits over the dimmed cover', (tester) async {
    await tester.pumpWidget(host(overlay: viz));
    expect(find.byKey(const Key('viz')), findsOneWidget);
    expect(find.byKey(const Key('cover')), findsOneWidget);
    final dim = tester.widget<ColoredBox>(find
        .ancestor(of: find.byKey(const Key('viz')), matching: find.byType(ColoredBox))
        .first);
    expect(dim.color.a, greaterThan(0.3));
  });

  testWidgets('opening the lyrics removes it, closing them brings it back', (tester) async {
    await tester.pumpWidget(host(overlay: viz));
    await tester.tap(find.byTooltip('Show lyrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('viz')), findsNothing, reason: 'never with the lyrics');
    await tester.tap(find.byTooltip('Show cover'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('viz')), findsOneWidget);
  });

  testWidgets('with the setting off the cover is as before: no dimming layer', (tester) async {
    await tester.pumpWidget(host());
    expect(find.byKey(const Key('viz')), findsNothing);
    expect(find.descendant(of: find.byType(CoverWithLyrics), matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color.a < 1)), findsNothing);
  });

  test('the setting is remembered, and off by default', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SettingsRepository(db);
    expect((await repo.load()).visualizerOnCover, isFalse);
    await repo.setVisualizerOnCover(true);
    expect((await repo.load()).visualizerOnCover, isTrue);
  });

  group('where it sits on the cover', () {
    Future<double> centerY(WidgetTester tester, Alignment a) async {
      await tester.pumpWidget(host(overlay: viz, align: a));
      final cover = tester.getRect(find.byKey(const Key('cover')));
      final v = tester.getCenter(find.byKey(const Key('viz')));
      return (v.dy - cover.center.dy) / cover.height;
    }

    testWidgets('top, middle and bottom put it there, inside the cover', (tester) async {
      final top = await centerY(tester, Alignment.topCenter);
      final mid = await centerY(tester, Alignment.center);
      final bottom = await centerY(tester, Alignment.bottomCenter);
      expect(top, lessThan(-0.25));
      expect(mid.abs(), lessThan(0.02));
      expect(bottom, greaterThan(0.25));
      expect(bottom, lessThan(0.5), reason: 'still inside the picture');
    });

    test('the choices, and bottom when nothing (or nonsense) is saved', () {
      expect(VisualizerCoverPosition.values.map((v) => v.name), ['top', 'middle', 'bottom']);
      expect(VisualizerCoverPosition.parse(null), VisualizerCoverPosition.bottom);
      expect(VisualizerCoverPosition.parse('sideways'), VisualizerCoverPosition.bottom);
      expect(VisualizerCoverPosition.parse('top').alignment, Alignment.topCenter);
    });

    test('the position is remembered; bottom is the default', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SettingsRepository(db);
      expect((await repo.load()).visualizerCoverPosition, 'bottom');
      await repo.setVisualizerCoverPosition('top');
      expect((await repo.load()).visualizerCoverPosition, 'top');
    });
  });
}
