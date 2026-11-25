import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/widgets/default_art.dart';
import 'package:remote_tunes/features/music/song_art.dart';

import 'music_widgets_test.dart' show FakeMusicSource, song, tinyJpeg;

Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  late FakeMusicSource source;

  setUp(() {
    SongArt.forgetAll();
    source = FakeMusicSource(songs: [song(1, 'Plain'), song(2, 'Covered')]);
    source.withArt.add(2);
  });

  CircleAvatar avatar(WidgetTester tester) => tester.widget<CircleAvatar>(find.byType(CircleAvatar).last);

  testWidgets('a song with no cover shows the default picture from the very first frame', (tester) async {
    await tester.pumpWidget(host(SongArt(source: source, songId: 1)));
    // Nothing has been awaited yet: this is the first frame.
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(avatar(tester).backgroundImage, isA<ResizeImage>(), reason: 'the default, never a plain grey circle');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircleAvatar), findsOneWidget, reason: 'and nothing changes when the answer (none) arrives');
    expect(avatar(tester).backgroundImage, isA<ResizeImage>());
  });

  testWidgets('a song with a cover starts on the default and fades to the cover', (tester) async {
    await tester.pumpWidget(host(SongArt(source: source, songId: 2)));
    expect(avatar(tester).backgroundImage, isA<ResizeImage>());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(avatar(tester).backgroundImage, isA<MemoryImage>());
  });

  testWidgets('a row built again shows what was found at once, and asks nothing', (tester) async {
    await tester.pumpWidget(host(SongArt(source: source, songId: 2)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(source.artAsked, [2]);
    // Scrolled away and back: a new row for the same song.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(SongArt(source: source, songId: 2)));
    expect(avatar(tester).backgroundImage, isA<MemoryImage>(), reason: 'the very first frame already has the cover');
    expect(source.artAsked, [2], reason: 'not fetched again');
  });

  testWidgets('a song known to have no cover is not asked about again either', (tester) async {
    await tester.pumpWidget(host(SongArt(source: source, songId: 1)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(SongArt(source: source, songId: 1)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(source.artAsked, [1]);
  });

  testWidgets('what is remembered is kept per source', (tester) async {
    final other = FakeMusicSource(songs: [song(2, 'Same id, another library')]);
    await tester.pumpWidget(host(SongArt(source: source, songId: 2)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(SongArt(source: other, songId: 2)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(other.artAsked, [2], reason: 'the other library has its own answer');
    expect(avatar(tester).backgroundImage, isA<ResizeImage>(), reason: 'no cover there');
  });

  testWidgets('forgetting what is remembered (covers changed) fetches again', (tester) async {
    await tester.pumpWidget(host(SongArt(source: source, songId: 2)));
    await tester.pump(const Duration(milliseconds: 500));
    SongArt.forgetAll();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(SongArt(source: source, songId: 2)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(source.artAsked, [2, 2]);
  });

  testWidgets('a row that is given another song shows that song, not the old picture', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(host(SongArt(key: key, source: source, songId: 2)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(avatar(tester).backgroundImage, isA<MemoryImage>());
    await tester.pumpWidget(host(SongArt(key: key, source: source, songId: 1)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(avatar(tester).backgroundImage, isA<ResizeImage>());
  });

  testWidgets('a state icon (selected, missing) replaces the default and keeps showing', (tester) async {
    await tester.pumpWidget(host(SongArt(source: source, songId: 1, overlayIcon: Icons.check_rounded)));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.pumpWidget(host(SongArt(source: source, songId: 2, overlayIcon: Icons.check_rounded)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget, reason: 'on the cover');
    expect(avatar(tester).backgroundImage, isA<MemoryImage>());
  });

  testWidgets('a link (no library id) never fetches and shows the default', (tester) async {
    await tester.pumpWidget(host(SongArt(source: source, songId: 0)));
    expect(avatar(tester).backgroundImage, isA<ResizeImage>());
    expect(source.artAsked, isEmpty);
  });

  testWidgets('a source that fails shows the default, quietly', (tester) async {
    final failing = _FailingSource();
    await tester.pumpWidget(host(SongArt(source: failing, songId: 5)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(avatar(tester).backgroundImage, isA<ResizeImage>());
  });

  test('every size of default avatar is decoded at one width, so one decoded copy serves them all', () {
    ResizeImage widthOf(Widget w) => (w as CircleAvatar).backgroundImage! as ResizeImage;
    expect(widthOf(DefaultArt.albumAvatar(radius: 14)).width, DefaultArt.avatarDecodeWidth);
    expect(widthOf(DefaultArt.albumAvatar(radius: 80)).width, DefaultArt.avatarDecodeWidth);
    expect(widthOf(DefaultArt.artistAvatar(radius: 20)).width, DefaultArt.avatarDecodeWidth);
    expect(widthOf(DefaultArt.albumAvatar(radius: 14)) == widthOf(DefaultArt.albumAvatar(radius: 80)), isTrue,
        reason: 'the same image key: the image cache serves both');
  });

  testWidgets('the default pictures can be decoded ahead of time', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    await tester.runAsync(() => DefaultArt.precache(ctx));
    expect(tinyJpeg, isNotEmpty);
  });
}

class _FailingSource extends FakeMusicSource {
  _FailingSource() : super(songs: []);
  @override
  Future<Uint8List?> artFor(int songId, {int size = 96}) async => throw Exception('no');
}
