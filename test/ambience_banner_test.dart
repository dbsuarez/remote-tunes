import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/ambience/ambience_banner.dart';
import 'package:remote_tunes/features/ambience/ambience_controller.dart';
import 'package:remote_tunes/features/ambience/ambience_view.dart';

import 'ambience_controller_test.dart' show FakeEngine, FakeFiles, MemoryAmbienceStore;

final onePixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

void main() {
  group('the part of a picture that shows', () {
    const wide = Size(7000, 1000); // wider than the banner
    const tall = Size(700, 2000); // much taller

    test('as much as fits, from the middle, in the shape of the banner', () {
      expect(const BannerFraming(aspect: 3.5).partOf(wide), const Rect.fromLTWH(1750, 0, 3500, 1000));
      expect(const BannerFraming(aspect: 3.5).partOf(tall), const Rect.fromLTWH(0, 900, 700, 200));
    });

    test('zooming shows less around the same middle', () {
      expect(const BannerFraming(zoom: 2, aspect: 3.5).partOf(tall), const Rect.fromLTWH(175, 950, 350, 100));
    });

    test('it never leaves the picture', () {
      final r = const BannerFraming(x: 0, y: 1, aspect: 3.5).partOf(tall);
      expect((r.left, r.bottom), (0, 2000));
      expect(const BannerFraming(zoom: 99, aspect: 3.5).partOf(tall).width, closeTo(700 / ambienceMaxZoom, 0.001));
    });

    test('dragging moves the picture with the finger, and stops at the edge', () {
      // The frame is 350 wide and shows 700 pixels: each point is two pixels.
      final down = const BannerFraming(aspect: 3.5).moved(tall, 350, const Offset(0, 100));
      expect(down.partOf(tall).top, 700);
      final far = down.moved(tall, 350, const Offset(0, 5000));
      expect(far.partOf(tall).top, 0);
      expect(far.moved(tall, 350, const Offset(0, -10)).partOf(tall).top, 20, reason: 'back at once');
    });

    test('a taller banner shows more of the height, around the same middle', () {
      final f = const BannerFraming(aspect: 3.5).moved(tall, 350, Offset.zero, aspect: 1.4);
      expect(f.partOf(tall), const Rect.fromLTWH(0, 750, 700, 500));
      expect(const BannerFraming().moved(tall, 350, Offset.zero, aspect: 99).aspect, ambienceFlattestBanner);
      expect(const BannerFraming().moved(tall, 350, Offset.zero, aspect: 0.1).aspect, ambienceTallestBanner);
      expect(BannerFraming.fromJson(f.toJson()).aspect, 1.4);
    });

    test('is kept and read back; nonsense is the usual', () {
      final f = BannerFraming.fromJson(const BannerFraming(zoom: 2, x: 0.2, y: 0.7).toJson());
      expect((f.zoom, f.x, f.y), (2, 0.2, 0.7));
      expect(BannerFraming.fromJson('x').zoom, 1);
    });
  });

  testWidgets('the finished banner is a PNG in the shape of the banner', (tester) async {
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(onePixel);
      final image = (await codec.getNextFrame()).image;
      final png = await renderBanner(image, const BannerFraming(aspect: 3.5), width: 350);
      final out = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
      expect((out.width, out.height), (350, 100));
    });
  });

  group('keeping banners', () {
    late FakeFiles files;
    late MemoryAmbienceStore store;
    AmbienceController make() => AmbienceController(engine: FakeEngine(), files: files, store: store);
    setUp(() {
      files = FakeFiles();
      store = MemoryAmbienceStore();
    });

    test('each group has its own, kept between runs; old files go', () async {
      final c = make();
      await c.setBanner('Rain', Uint8List.fromList([1]), const BannerFraming(zoom: 2), newSource: '/p/rain.jpg');
      await c.setBanner('Night', Uint8List.fromList([2]), const BannerFraming(), newSource: '/p/night.png');
      expect(c.banner('Rain')!.imagePath, 'banner-1.png');
      expect(c.banner('Rain')!.sourcePath, '/kept/bannersrc.jpg');
      expect(c.banner('Ocean'), isNull);
      // Framed again: the picture it came from stays.
      await c.setBanner('Rain', Uint8List.fromList([3]), const BannerFraming(zoom: 3));
      expect(files.removed, ['banner-1.png']);
      expect(c.banner('Rain')!.sourcePath, '/kept/bannersrc.jpg');
      final again = make();
      await again.load();
      expect(again.banner('Rain')!.framing.zoom, 3);
      expect(again.banner('Night')!.imagePath, 'banner-2.png');
      await again.removeBanner('Rain');
      expect(again.banner('Rain'), isNull);
      expect(files.removed, containsAll(['banner-3.png', '/kept/bannersrc.jpg']));
    });
  });

  group('on the screen', () {
    late AmbienceController c;
    String? picked;
    final saved = <String>[];

    setUp(() {
      c = AmbienceController(engine: FakeEngine(), files: FakeFiles(), store: MemoryAmbienceStore());
      picked = '/p/photo.jpg';
      saved.clear();
    });

    AmbienceOwner owner() => AmbienceOwner(
          pickFile: () async => null,
          addFile: c.addFile,
          addOwnSound: c.addOwnSound,
          removeFile: c.removeFile,
          setMaxVolume: c.setMaxVolume,
          banners: AmbienceBanners(
            of: (group) {
              final b = c.banner(group);
              return b == null ? null : (image: MemoryImage(onePixel), sourcePath: b.sourcePath, framing: b.framing);
            },
            pick: () async => picked,
            read: (path) async => onePixel,
            set: (group, png, framing, {newSource}) async {
              saved.add('$group ${newSource ?? '-'} ${framing.zoom.round()}');
              await c.setBanner(group, png, framing, newSource: newSource);
            },
            remove: c.removeBanner,
          ),
        );

    /// Decoding and drawing the picture happen outside the test's pretend time.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    Future<void> open(WidgetTester tester, {Size size = const Size(400, 900), bool owned = true}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await c.load();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AmbienceView(controls: c, owner: owned ? owner() : null))));
      await tester.pump();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      if (key == 'amb-banner-edit') {
        await tester.tap(find.byKey(const Key('amb-menu')));
        await settle(tester);
      }
      await tester.tap(find.byKey(Key(key)));
      await settle(tester);
    }

    void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
      testWidgets(name, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
        c.dispose();
      });
    }

    screenTest('pick, zoom, save: the group shows the picture, and the others do not', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('amb-banner-picture')), findsNothing);
      await tap(tester, 'amb-banner-edit');
      expect(find.text('Banner of Ready'), findsOneWidget);
      await tester.drag(find.byKey(const Key('banner-zoom')), const Offset(400, 0));
      await tester.pump();
      await tap(tester, 'banner-save');
      expect(saved, ['Ready /p/photo.jpg 6']);
      expect(find.byKey(const Key('amb-banner-picture')), findsOneWidget);
      await tester.fling(find.byKey(const Key('amb-pages')), const Offset(-300, 0), 1000);
      await settle(tester);
      expect(find.byKey(const Key('amb-banner-picture')), findsNothing, reason: 'the Selected page has none');
    });

    screenTest('a banner can be moved again, changed or taken away', (tester) async {
      await open(tester);
      await tap(tester, 'amb-banner-edit');
      await tap(tester, 'banner-save');
      await tap(tester, 'amb-banner-edit');
      await tap(tester, 'banner-move');
      await tester.drag(find.byKey(const Key('banner-drag')), const Offset(30, 10));
      await tester.pump();
      await tap(tester, 'banner-save');
      expect(saved.last, 'Ready - 1', reason: 'the same picture');
      await tap(tester, 'amb-banner-edit');
      await tap(tester, 'banner-remove');
      expect(find.byKey(const Key('amb-banner-picture')), findsNothing);
    });

    screenTest('the height can be set, the page shows it, and the next picture starts there', (tester) async {
      await open(tester);
      double shown() => tester.getSize(find.byKey(const Key('amb-banner-picture'))).height;
      await tap(tester, 'amb-banner-edit');
      await tap(tester, 'banner-save');
      expect(shown(), closeTo(400 / ambienceBannerAspect, 1));
      await tap(tester, 'amb-banner-edit');
      await tap(tester, 'banner-move');
      await tester.drag(find.byKey(const Key('banner-height')), const Offset(400, 0));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('banner-height-value'))).data, '${(400 / ambienceTallestBanner).round()}');
      await tap(tester, 'banner-save');
      expect(shown(), closeTo(900 * 0.3, 1), reason: 'never more than three tenths of the screen');
      await tap(tester, 'amb-banner-edit');
      await tap(tester, 'banner-new');
      expect(tester.widget<Text>(find.byKey(const Key('banner-height-value'))).data, '${(400 / ambienceTallestBanner).round()}');
      await tap(tester, 'banner-cancel');
    });

    screenTest('cancelling, or picking nothing, keeps things as they were', (tester) async {
      await open(tester);
      await tap(tester, 'amb-banner-edit');
      await tap(tester, 'banner-cancel');
      picked = null;
      await tap(tester, 'amb-banner-edit');
      expect(find.byKey(const Key('banner-save')), findsNothing);
      expect(saved, isEmpty);
    });

    screenTest('fits a narrow, short phone', (tester) async {
      await open(tester, size: const Size(320, 600));
      await tap(tester, 'amb-banner-edit');
      await tap(tester, 'banner-save');
      expect(find.byKey(const Key('amb-banner-picture')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    screenTest('is not offered from the other phone', (tester) async {
      await open(tester, owned: false);
      expect(find.byKey(const Key('amb-menu')), findsNothing);
    });
  });
}
