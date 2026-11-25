import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/lyrics_view.dart';

const _lrc = '''
[00:05.00]Intro
[00:12.50]First line
[00:20.00]Second line
[01:30]Last
''';

const synced = RemoteLyrics(found: true, synced: _lrc, source: 'LRCLIB');

Widget host(
  Future<RemoteLyrics> Function(int) fetch, {
  int position = 0,
  ValueChanged<int>? onSeek,
  String title = 'Killing in the Name',
  String artist = 'Rage',
}) =>
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: CoverWithLyrics(
            cover: Container(key: const Key('cover'), color: Colors.purple),
            size: 320,
            radius: 20,
            songId: 5,
            title: title,
            artist: artist,
            positionSeconds: position,
            isPlaying: false,
            fetch: fetch,
            onSeek: onSeek,
          ),
        ),
      ),
    );

Future<void> show(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Show lyrics'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

FadeTransition coverFade(WidgetTester tester) => tester.widget<FadeTransition>(find
    .ancestor(of: find.byKey(const Key('cover')), matching: find.byType(FadeTransition))
    .first);

TextStyle styleOf(WidgetTester tester, String text, {Type? inside}) {
  var f = find.ancestor(of: find.text(text), matching: find.byType(AnimatedDefaultTextStyle));
  if (inside != null) f = find.descendant(of: find.byType(inside), matching: f);
  // A line's own style (line height 1.25); the others belong to Material.
  return tester
      .widgetList<AnimatedDefaultTextStyle>(f)
      .firstWhere((w) => w.style.height == 1.25)
      .style;
}

void main() {
  testWidgets('the cover fades out completely and the lyrics take its place', (tester) async {
    await tester.pumpWidget(host((id) async => synced));
    expect(coverFade(tester).opacity.value, 1.0);
    await tester.tap(find.byTooltip('Show lyrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(coverFade(tester).opacity.value, lessThan(1.0), reason: 'fading');
    await tester.pump(const Duration(milliseconds: 600));
    expect(coverFade(tester).opacity.value, 0.0, reason: 'gone: nothing of it shows through');
    expect(find.byType(LyricsCard), findsOneWidget);
  });

  testWidgets('the cover and the lyrics are never both fully visible', (tester) async {
    await tester.pumpWidget(host((id) async => synced));
    await tester.tap(find.byTooltip('Show lyrics'));
    await tester.pump();
    for (var ms = 0; ms < 460; ms += 40) {
      await tester.pump(const Duration(milliseconds: 40));
      final cover = coverFade(tester).opacity.value;
      final lyrics = tester
          .widget<FadeTransition>(find
              .ancestor(of: find.byType(LyricsCard), matching: find.byType(FadeTransition))
              .first)
          .opacity
          .value;
      expect(cover + lyrics, lessThanOrEqualTo(1.001), reason: 'at $ms ms');
    }
  });

  testWidgets('the button brings the cover back, and taps no longer reach the lyrics',
      (tester) async {
    await tester.pumpWidget(host((id) async => synced));
    await show(tester);
    await tester.tap(find.byTooltip('Show cover'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(coverFade(tester).opacity.value, 1.0);
    expect(find.byTooltip('Show lyrics'), findsOneWidget);
    final ignoring = tester
        .widgetList<IgnorePointer>(find.ancestor(
            of: find.byType(LyricsCard, skipOffstage: false),
            matching: find.byType(IgnorePointer)))
        .any((w) => w.ignoring);
    expect(ignoring, isTrue);
  });

  testWidgets('the card fills the cover space, with a margin', (tester) async {
    await tester.pumpWidget(host((id) async => synced));
    await show(tester);
    final size = tester.getSize(
        find.descendant(of: find.byType(LyricsCard), matching: find.byType(DecoratedBox)).first);
    expect(size.width, closeTo(320 - 12, 1));
    expect(size.height, closeTo(320 - 12, 1));
  });

  testWidgets('the line being sung is the biggest and brightest', (tester) async {
    await tester.pumpWidget(host((id) async => synced, position: 13));
    await show(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final now = styleOf(tester, 'First line');
    final next = styleOf(tester, 'Second line');
    final far = styleOf(tester, 'Last');
    expect(now.fontWeight, FontWeight.w800);
    expect(now.color, Colors.white);
    expect(next.fontSize!, lessThan(now.fontSize!));
    expect(far.fontSize!, lessThanOrEqualTo(next.fontSize!));
    expect(far.color!.a, lessThan(next.color!.a));
  });

  testWidgets('the credit is a quiet line at the foot', (tester) async {
    await tester.pumpWidget(host((id) async => synced));
    await show(tester);
    expect(find.text('Lyrics: LRCLIB'), findsOneWidget);
  });

  testWidgets('plain lyrics get the same card and credit', (tester) async {
    await tester.pumpWidget(host(
        (id) async => const RemoteLyrics(found: true, plain: 'La la la', source: 'lyrics.ovh')));
    await show(tester);
    expect(find.byType(LyricsCard), findsOneWidget);
    expect(find.text('La la la'), findsOneWidget);
    expect(find.text('Lyrics: lyrics.ovh'), findsOneWidget);
  });

  testWidgets('"Show fullscreen" is on the lyrics card', (tester) async {
    await tester.pumpWidget(host((id) async => synced));
    await show(tester);
    expect(find.byTooltip('Show fullscreen'), findsOneWidget);
  });

  testWidgets('full screen: the song, bigger lyrics, a way out; it closes back to the card',
      (tester) async {
    await tester.pumpWidget(host((id) async => synced, position: 13));
    await show(tester);
    await tester.tap(find.byTooltip('Show fullscreen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LyricsLightbox), findsOneWidget);
    expect(find.text('Killing in the Name'), findsOneWidget);
    expect(find.text('Rage'), findsWidgets);
    expect(find.byTooltip('Close lyrics'), findsOneWidget);
    expect(find.text('Lyrics: LRCLIB'), findsWidgets);
    final big = styleOf(tester, 'First line', inside: LyricsLightbox).fontSize!;
    final small = styleOf(tester, 'First line', inside: LyricsCard).fontSize!;
    expect(big, greaterThan(small));

    await tester.tap(find.byTooltip('Close lyrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LyricsLightbox), findsNothing);
    expect(find.byType(LyricsCard), findsOneWidget, reason: 'still in lyrics mode');
  });

  testWidgets('a tap on a line in full screen jumps the song', (tester) async {
    final seeks = <int>[];
    await tester.pumpWidget(host((id) async => synced, onSeek: seeks.add));
    await show(tester);
    await tester.tap(find.byTooltip('Show fullscreen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
        find.descendant(of: find.byType(LyricsLightbox), matching: find.text('Second line')));
    expect(seeks, [20]);
  });

  testWidgets('the full-screen view follows the song behind it', (tester) async {
    await tester.pumpWidget(host((id) async => synced, position: 1));
    await show(tester);
    await tester.tap(find.byTooltip('Show fullscreen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Rage'), findsWidgets);
    await tester.pumpWidget(host((id) async => synced, position: 21, title: 'Bulls on Parade'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Bulls on Parade'), findsOneWidget);
  });

  testWidgets('full screen shows the messages too', (tester) async {
    await tester.pumpWidget(host((id) async => const RemoteLyrics()));
    await show(tester);
    await tester.tap(find.byTooltip('Show fullscreen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No lyrics found for this song.'), findsWidgets);
  });

  test('the controller asks once, and again for a new song or Try again', () async {
    var asked = 0;
    final c = LyricsController((id) async {
      asked++;
      return synced;
    });
    c.load(1);
    c.load(1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(asked, 1);
    expect(c.lines, isNotEmpty);
    c.load(1);
    expect(asked, 1, reason: 'already there');
    c.load(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(asked, 2);
    c.retry();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(asked, 3);
    c.dispose();
  });

  test('a slow answer for an old song is ignored', () async {
    final c = LyricsController((id) async {
      if (id == 1) await Future<void>.delayed(const Duration(milliseconds: 80));
      return RemoteLyrics(found: true, plain: 'words $id');
    });
    c.load(1);
    c.load(2);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(c.lyrics!.plain, 'words 2');
    c.dispose();
  });
}
