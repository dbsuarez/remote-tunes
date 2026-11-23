import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/song_list_style.dart';
import 'package:remote_tunes/core/widgets/playback_widgets.dart';

void main() {
  PlaybackState at(int pos, {String title = 'Song'}) => PlaybackState(
      title: title, positionSeconds: pos, durationSeconds: 200, isPlaying: true);

  Widget card(PlaybackState s, List<int> seeks) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: NowPlayingCard(state: s, onSeek: seeks.add),
            ),
          ),
        ),
      );

  double sliderValue(WidgetTester t) => t.widget<Slider>(find.byType(Slider)).value;

  testWidgets('the bar stays where it was released until the Player catches up',
      (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(card(at(100), seeks));
    expect(sliderValue(tester), 100);

    // Tap about 35% along the bar (about 70 s).
    final box = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(box.left + box.width * 0.35, box.center.dy));
    await tester.pump();
    expect(seeks, hasLength(1));
    final target = seeks.single.toDouble();
    expect(target, closeTo(70, 12));

    // An old state still says 100: the bar must not jump back.
    await tester.pumpWidget(card(at(100), seeks));
    expect(sliderValue(tester), target);
    await tester.pumpWidget(card(at(101), seeks));
    expect(sliderValue(tester), target);

    // The Player reports the new position: follow it again.
    await tester.pumpWidget(card(at(target.round()), seeks));
    await tester.pumpWidget(card(at(target.round() + 5), seeks));
    expect(sliderValue(tester), target + 5);
  });

  testWidgets('if the Player never confirms, the bar gives up after a few seconds',
      (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(card(at(100), seeks));
    final box = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(box.left + box.width * 0.35, box.center.dy));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(sliderValue(tester), 100);
  });

  testWidgets('a new track clears the held position', (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(card(at(100), seeks));
    final box = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(box.left + box.width * 0.35, box.center.dy));
    await tester.pump();
    await tester.pumpWidget(card(at(3, title: 'Next song'), seeks));
    expect(sliderValue(tester), 3);
    await tester.pump(const Duration(seconds: 5));
  });

  test('song list size: names parse, unknown falls back to small', () {
    expect(SongListSize.parse('large'), SongListSize.large);
    expect(SongListSize.parse('huge'), SongListSize.small);
    expect(SongListSize.parse(null), SongListSize.small);
    expect(SongListSize.small.scale, lessThan(SongListSize.normal.scale));
  });
}
