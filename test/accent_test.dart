import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:remote_tunes/core/accent.dart';
import 'package:remote_tunes/core/widgets/accent_scope.dart';

/// A PNG of [w] x [h] pixels filled by [color].
Uint8List png(int w, int h, Color Function(int x, int y) color) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = color(x, y);
      im.setPixelRgba(x, y, (c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), 255);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

Uint8List solid(Color c) => png(40, 40, (x, y) => c);

double hueOf(Color c) => Hct.fromInt(c.toARGB32()).hue;
double toneOf(Color c) => Hct.fromInt(c.toARGB32()).tone;
double chromaOf(Color c) => Hct.fromInt(c.toARGB32()).chroma;

double hueGap(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

void main() {
  group('making a cover color fit the dark screen', () {
    test('a dark color is lightened so a progress bar is never lost', () {
      final c = normalizeAccent(const Color(0xFF1A0A3A)); // near-black violet
      expect(toneOf(c), greaterThanOrEqualTo(61));
    });

    test('a pale color is toned down so it is not glaring white', () {
      final c = normalizeAccent(const Color(0xFFF5F0FF));
      expect(toneOf(c), lessThanOrEqualTo(81));
    });

    test('a dull color gets enough life to be an accent', () {
      final c = normalizeAccent(const Color(0xFF6B6168));
      expect(chromaOf(c), greaterThanOrEqualTo(40));
    });

    test('the hue (what colour it is) is kept', () {
      final red = normalizeAccent(const Color(0xFFB02030));
      final blue = normalizeAccent(const Color(0xFF2030B0));
      expect(hueGap(hueOf(red), hueOf(const Color(0xFFB02030))), lessThan(12));
      expect(hueGap(hueOf(blue), hueOf(const Color(0xFF2030B0))), lessThan(12));
      expect(hueGap(hueOf(red), hueOf(blue)), greaterThan(60));
    });

    test('the result is always readable on the charcoal background', () {
      for (final base in [
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
        const Color(0xFF123456),
        const Color(0xFFFFE000),
        const Color(0xFFCC00CC),
      ]) {
        final c = normalizeAccent(base);
        // Contrast against RemoteTunes' background (#111317) of at least 4.5.
        final bg = const Color(0xFF111317).computeLuminance();
        final ratio = (c.computeLuminance() + 0.05) / (bg + 0.05);
        expect(ratio, greaterThan(4.5), reason: '$base became $c');
      }
    });

    test("Spotify's green is never used as the accent", () {
      const brand = Color(0xFF1DB954);
      final exact = normalizeAccent(brand);
      final brandHue = hueOf(brand);
      expect(hueGap(hueOf(exact), brandHue), greaterThan(16),
          reason: 'it was nudged away from the brand colour');
      // Close shades too.
      for (final c in [const Color(0xFF1ED760), const Color(0xFF19AE50), const Color(0xFF22C55E)]) {
        final n = normalizeAccent(c);
        expect(hueGap(hueOf(n), brandHue), greaterThan(16), reason: '$c became $n');
      }
    });

    test('other greens (a forest cover) are left as they are', () {
      final lime = normalizeAccent(const Color(0xFF9ACD32)); // yellow-green
      final teal = normalizeAccent(const Color(0xFF00A99D));
      expect(hueGap(hueOf(lime), hueOf(const Color(0xFF9ACD32))), lessThan(12));
      expect(hueGap(hueOf(teal), hueOf(const Color(0xFF00A99D))), lessThan(12));
    });
  });

  group('finding the main color of a picture', () {
    test('a plain red cover gives a red accent', () async {
      final c = await accentFromArgbPixels(List.filled(400, 0xFFC02030));
      expect(c, isNotNull);
      expect(hueGap(hueOf(c!), hueOf(const Color(0xFFC02030))), lessThan(15));
    });

    test('the dominant vivid color wins over a little background', () async {
      final px = [
        ...List.filled(300, 0xFF2040C0), // blue, most of the picture
        ...List.filled(60, 0xFFC02030), // some red
        ...List.filled(40, 0xFF202020), // dark edge
      ];
      final c = await accentFromArgbPixels(px);
      expect(hueGap(hueOf(c!), hueOf(const Color(0xFF2040C0))), lessThan(20));
    });

    test('a grey cover gives no accent (the normal colors stay)', () async {
      expect(await accentFromArgbPixels(List.filled(400, 0xFF808080)), isNull);
      expect(await accentFromArgbPixels(List.filled(400, 0xFF000000)), isNull);
      expect(await accentFromArgbPixels(List.filled(400, 0xFFFFFFFF)), isNull);
    });

    test('an empty picture gives no accent', () async {
      expect(await accentFromArgbPixels(const []), isNull);
    });
  });

  group('reading a real image', () {
    testWidgets('a PNG of a blue cover gives a blue accent', (tester) async {
      final c = await tester.runAsync(() => accentFromImageBytes(solid(const Color(0xFF2050D0))));
      expect(c, isNotNull);
      expect(hueGap(hueOf(c!), hueOf(const Color(0xFF2050D0))), lessThan(15));
    });

    testWidgets('a two-tone cover uses the larger, more vivid part', (tester) async {
      final bytes = png(40, 40, (x, y) => x < 30 ? const Color(0xFFD06020) : const Color(0xFF303030));
      final c = await tester.runAsync(() => accentFromImageBytes(bytes));
      expect(hueGap(hueOf(c!), hueOf(const Color(0xFFD06020))), lessThan(15));
    });

    testWidgets('bytes that are not a picture give nothing, not an error', (tester) async {
      final c = await tester.runAsync(() => accentFromImageBytes(Uint8List.fromList([1, 2, 3, 4])));
      expect(c, isNull);
    });

    testWidgets('a grey photo gives nothing', (tester) async {
      final c = await tester.runAsync(() => accentFromImageBytes(solid(const Color(0xFF777777))));
      expect(c, isNull);
    });
  });

  group('the cache', () {
    test('each song is worked out once', () async {
      var loads = 0;
      final cache = AccentCache();
      Future<Uint8List?> load(int id) async {
        loads++;
        return null;
      }

      await cache.forSong(7, load);
      await cache.forSong(7, load);
      await cache.forSong(8, load);
      expect(loads, 2);
    });

    test('it forgets the oldest when full', () async {
      var loads = 0;
      final cache = AccentCache(maxEntries: 2);
      Future<Uint8List?> load(int id) async {
        loads++;
        return null;
      }

      await cache.forSong(1, load);
      await cache.forSong(2, load);
      await cache.forSong(3, load); // pushes 1 out
      await cache.forSong(1, load);
      expect(loads, 4);
    });
  });

  group('tinting the screen (AccentScope)', () {
    Future<void> pump(
      WidgetTester tester, {
      required int? songId,
      required Future<Uint8List?> Function(int) loadArt,
      bool enabled = true,
      AccentCache? cache,
      Key? key,
    }) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [accentFromArtProvider.overrideWith((ref) => enabled)],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: const ColorScheme.dark(primary: Color(0xFF22E5D0)),
          ),
          home: AccentScope(
            key: key,
            songId: songId,
            loadArt: loadArt,
            cache: cache ?? AccentCache(),
            child: Builder(
              builder: (c) => Text(
                'x',
                key: const Key('probe'),
                style: TextStyle(color: Theme.of(c).colorScheme.primary),
              ),
            ),
          ),
        ),
      ));
    }

    Color probeColor(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('probe'))).style!.color!;

    testWidgets('a song with a red cover turns the accent red, fading in', (tester) async {
      await pump(tester,
          songId: 5, loadArt: (_) async => solid(const Color(0xFFC02030)));
      expect(probeColor(tester), const Color(0xFF22E5D0), reason: 'teal until it is known');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250)); // part way
      final mid = probeColor(tester);
      expect(mid, isNot(const Color(0xFF22E5D0)));
      await tester.pump(const Duration(milliseconds: 600)); // done
      final end = probeColor(tester);
      expect(hueGap(hueOf(end), hueOf(const Color(0xFFC02030))), lessThan(15));
      expect(end, isNot(mid), reason: 'it was still moving half way');
    });

    testWidgets('no song, or no art, keeps the normal colors', (tester) async {
      await pump(tester, songId: null, loadArt: (_) async => null);
      expect(probeColor(tester), const Color(0xFF22E5D0));
      await pump(tester, songId: 9, loadArt: (_) async => null, key: UniqueKey());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(probeColor(tester), const Color(0xFF22E5D0));
    });

    testWidgets('the sync test and internet tracks (no library id) are not tinted',
        (tester) async {
      var asked = 0;
      await pump(tester, songId: -1, loadArt: (_) async {
        asked++;
        return solid(const Color(0xFFC02030));
      });
      await tester.pumpAndSettle();
      expect(asked, 0);
      expect(probeColor(tester), const Color(0xFF22E5D0));
    });

    testWidgets('switched off in Settings, the cover is not used', (tester) async {
      await pump(tester,
          songId: 5, enabled: false, loadArt: (_) async => solid(const Color(0xFFC02030)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(probeColor(tester), const Color(0xFF22E5D0));
    });

    testWidgets('a grey cover leaves the normal colors', (tester) async {
      await pump(tester,
          songId: 5, loadArt: (_) async => solid(const Color(0xFF808080)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(probeColor(tester), const Color(0xFF22E5D0));
    });

    testWidgets('when the song changes, an answer for the old song is ignored',
        (tester) async {
      // Song 1's art arrives slowly; song 2 is red and quick.
      Future<Uint8List?> load(int id) async {
        if (id == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return solid(const Color(0xFF2050D0)); // blue
        }
        return solid(const Color(0xFFC02030)); // red
      }

      final cache = AccentCache();
      await pump(tester, songId: 1, loadArt: load, cache: cache, key: const Key('scope'));
      await pump(tester, songId: 2, loadArt: load, cache: cache, key: const Key('scope'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
      await tester.pumpAndSettle();
      expect(hueGap(hueOf(probeColor(tester)), hueOf(const Color(0xFFC02030))), lessThan(15),
          reason: 'red, not the late blue');
    });

    testWidgets('a failing picture load changes nothing and does not crash', (tester) async {
      await pump(tester, songId: 5, loadArt: (_) async => throw StateError('offline'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(probeColor(tester), const Color(0xFF22E5D0));
    });
  });
}
