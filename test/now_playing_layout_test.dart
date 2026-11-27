import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/widgets/fill_middle.dart';
import 'package:remote_tunes/core/widgets/playback_widgets.dart';

void main() {
  const state = PlaybackState(
      title: 'A song with a rather long title that would like two whole lines to itself',
      artist: 'Artist',
      album: 'Album',
      positionSeconds: 30,
      durationSeconds: 200,
      queueLength: 5,
      source: 'local_file',
      format: '48 kHz 256 kbps mp3');

  Future<void> open(WidgetTester tester, Size size, {Widget? under}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: NowPlayingCard(
              hero: true,
              state: state,
              enabled: true,
              onSeek: (_) {},
              actions: const SizedBox(key: Key('actions'), height: 48),
              fill: NowPlayingFill(
                height: box.maxHeight,
                underCover: under,
                art: (side) => SizedBox(key: const Key('cover'), width: side, height: side),
                transport: TransportControls(
                    isPlaying: true, enabled: true, onPrevious: () {}, onToggle: () {}, onNext: () {}),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  double cover(WidgetTester tester) => tester.getSize(find.byKey(const Key('cover'))).width;
  Rect rect(WidgetTester tester, Finder f) => tester.getRect(f);

  testWidgets('the progress bar is under the play button, at the bottom of the page', (tester) async {
    await open(tester, const Size(400, 800));
    final play = rect(tester, find.byTooltip('Pause'));
    final bar = rect(tester, find.byType(Slider));
    expect(bar.top, greaterThanOrEqualTo(play.bottom - 1));
    expect(rect(tester, find.byKey(const Key('actions'))).bottom, lessThanOrEqualTo(play.top + 1));
    final format = rect(tester, find.text('48 kHz 256 kbps mp3'));
    expect(800 - format.bottom, lessThan(12), reason: 'nothing left under it');
    expect(rect(tester, find.byKey(const Key('cover'))).bottom, lessThan(rect(tester, find.textContaining('A song')).top));
  });

  testWidgets('the cover takes what is left: larger on a tall phone, never wider than the page', (tester) async {
    await open(tester, const Size(500, 640));
    final small = cover(tester);
    await open(tester, const Size(500, 760));
    expect(cover(tester), closeTo(small + 120, 1));
    await open(tester, const Size(400, 1200));
    expect(cover(tester), 400);
  });

  for (final size in const [Size(320, 480), Size(360, 560), Size(360, 640)]) {
    testWidgets('a small page (${size.width.round()}x${size.height.round()}) shows all of it without scrolling',
        (tester) async {
      await open(tester, size);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scroll.position.maxScrollExtent, 0);
      expect(rect(tester, find.byType(Slider)).bottom, lessThanOrEqualTo(size.height));
      expect(cover(tester), greaterThanOrEqualTo(96));
    });
  }

  testWidgets('something under the cover takes its room from the cover', (tester) async {
    await open(tester, const Size(400, 700));
    final before = cover(tester);
    await open(tester, const Size(400, 700), under: const SizedBox(height: 60));
    expect(cover(tester), closeTo(before - 60, 1));
  });

  testWidgets('on a page too small for everything the cover keeps a least size and the page scrolls', (tester) async {
    await open(tester, const Size(320, 320));
    expect(cover(tester), 96);
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent, greaterThan(0));
    expect(find.byType(FillMiddle), findsOneWidget);
  });
}
