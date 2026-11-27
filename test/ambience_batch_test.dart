import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/ambience/ambience_banner.dart';
import 'package:remote_tunes/features/ambience/ambience_beats.dart';
import 'package:remote_tunes/features/ambience/ambience_controller.dart';
import 'package:remote_tunes/features/ambience/ambience_import.dart';
import 'package:remote_tunes/features/ambience/ambience_view.dart';

import 'ambience_controller_test.dart' show FakeEngine, FakeFiles, MemoryAmbienceStore;

final onePixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, //
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  late FakeEngine engine;
  late MemoryAmbienceStore store;
  late AmbienceController c;

  setUp(() {
    engine = FakeEngine();
    store = MemoryAmbienceStore();
    c = AmbienceController(engine: engine, files: FakeFiles(), store: store);
  });

  group('the binaural tones', () {
    /// How often one ear's wave crosses zero going up, per second: its frequency.
    double heard(Uint8List wav, int ear) {
      final d = ByteData.sublistView(wav);
      final frames = (d.lengthInBytes - 44) ~/ 4;
      var crossings = 0;
      var before = d.getInt16(44 + (frames - 1) * 4 + ear * 2, Endian.little);
      for (var i = 0; i < frames; i++) {
        final v = d.getInt16(44 + i * 4 + ear * 2, Endian.little);
        if (before < 0 && v >= 0) crossings++;
        before = v;
      }
      return crossings / (frames / 44100);
    }

    test('each ear gets its own frequency, as in the table', () {
      const table = {
        'beat-deep-sleep': (199.75, 200.25),
        'beat-sleep': (199.25, 200.75),
        'beat-relaxation': (198.75, 201.25),
        'beat-calm': (198.25, 201.75),
        'beat-meditation': (197.75, 202.25),
        'beat-intuition': (197.25, 202.75),
        'beat-creativity': (196.25, 203.75),
        'beat-focus': (196.0, 204.0),
        'beat-alert': (194.75, 205.25),
      };
      expect(ambienceBeats.keys, table.keys);
      for (final e in table.entries) {
        final t = beatTones(e.key)!;
        expect((t.left, t.right), e.value, reason: e.key);
        final wav = beatWav(ambienceBeats[e.key]!);
        expect(heard(wav, 0), closeTo(t.left, 0.26), reason: '${e.key} left');
        expect(heard(wav, 1), closeTo(t.right, 0.26), reason: '${e.key} right');
      }
    });

    test('the end runs into the start without a click, and it is quiet', () {
      for (final beat in ambienceBeats.values) {
        final wav = beatWav(beat);
        final d = ByteData.sublistView(wav);
        final frames = (d.lengthInBytes - 44) ~/ 4;
        // The largest step between two neighbouring samples of a 206 Hz wave at this strength.
        final step = 0.25 * 32767 * 2 * pi * 206 / 44100;
        var loudest = 0;
        for (var ear = 0; ear < 2; ear++) {
          final first = d.getInt16(44 + ear * 2, Endian.little);
          final last = d.getInt16(44 + (frames - 1) * 4 + ear * 2, Endian.little);
          expect((first - last).abs(), lessThan(step + 2), reason: 'beat $beat');
          for (var i = 0; i < frames; i += 7) {
            loudest = max(loudest, d.getInt16(44 + i * 4 + ear * 2, Endian.little).abs());
          }
        }
        expect(loudest, lessThanOrEqualTo((0.25 * 32767).round()));
      }
      expect(String.fromCharCodes(beatWav(8).sublist(0, 4)), 'RIFF');
      expect(ByteData.sublistView(beatWav(8)).getUint16(22, Endian.little), 2, reason: 'stereo');
    });

    test('play with nothing added, start lower, are not evened louder, and mix with others', () async {
      await c.load();
      expect(c.state.sounds.where((s) => s.category == ambienceBeatCategory && s.available), hasLength(9));
      engine.levels['/noise/beat-focus.wav'] = (rms: 0.001, peak: 0.01);
      await c.setMaster(1);
      await c.setActive('beat-focus', true);
      await c.setActive('white-noise', true);
      expect(c.state.active['beat-focus'], 0.4);
      expect(engine.voices['beat-focus'], closeTo(0.4, 0.001));
      expect(engine.measured, isNot(contains('/noise/beat-focus.wav')));
      expect(engine.voices.keys, {'beat-focus', 'white-noise'});
      await c.saveMix('Study');
      expect(c.state.mixes.last.layers.keys, contains('beat-focus'));
      expect(importTargets(c.state.sounds).where((s) => isAmbienceBeat(s.id)), isEmpty);
      c.dispose();
    });
  });

  group('renaming and the list style', () {
    test('only your own sounds can be renamed, and both are remembered', () async {
      await c.addOwnSound('Box', '/d/box.mp3');
      final id = c.state.sounds.last.id;
      await c.renameSound(id, '  Music box  ');
      await c.renameSound('rain', 'Nope');
      await expectLater(c.renameSound(id, ' '), throwsA(isA<AmbienceException>()));
      await c.setListBanners(true);
      final again = AmbienceController(engine: engine, files: FakeFiles(), store: store);
      await again.load();
      expect(again.state.sound(id)!.name, 'Music box');
      expect(again.state.sound('rain')!.name, 'Morning Rain');
      expect(again.listBanners, isTrue);
      again.dispose();
      c.dispose();
    });
  });

  group('on the screen', () {
    AmbienceOwner owner() => AmbienceOwner(
          pickFile: () async => '/d/box.mp3',
          addFile: c.addFile,
          addOwnSound: c.addOwnSound,
          removeFile: c.removeFile,
          setMaxVolume: c.setMaxVolume,
          rename: c.renameSound,
          setIcon: c.setIcon,
          listBanners: () => c.listBanners,
          setListBanners: c.setListBanners,
          banners: AmbienceBanners(
            of: (group) {
              final b = c.banner(group);
              return b == null ? null : (image: MemoryImage(onePixel), sourcePath: b.sourcePath, framing: b.framing);
            },
            pick: () async => null,
            read: (_) async => onePixel,
            set: (group, png, framing, {newSource}) => c.setBanner(group, png, framing, newSource: newSource),
            remove: c.removeBanner,
          ),
        );

    void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
      testWidgets(name, (tester) async {
        await body(tester);
        await c.stop();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
        c.dispose();
      });
    }

    Future<void> open(WidgetTester tester, {bool owned = true, Size size = const Size(400, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await c.load();
      await tester.pumpWidget(MaterialApp(home: AmbienceView(controls: c, title: 'Quiet time', owner: owned ? owner() : null)));
      await tester.pump();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    String title(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('amb-title-text'))).data!;

    Future<void> goTo(WidgetTester tester, String page) async {
      await tap(tester, 'amb-title');
      await tester.ensureVisible(find.byKey(ValueKey('amb-cat-$page')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('amb-cat-$page')));
      await tester.pumpAndSettle();
    }

    screenTest('the bar has the name, and a menu only for the playing phone', (tester) async {
      await open(tester);
      expect(find.text('Quiet time'), findsOneWidget);
      expect(find.byKey(const Key('amb-menu')), findsOneWidget);
      await open(tester, owned: false);
      expect(find.byKey(const Key('amb-menu')), findsNothing);
      expect(find.byKey(const Key('amb-info')), findsNothing);
    });

    screenTest('the title sits on the banner, and swiping the banner or the title changes group', (tester) async {
      await open(tester);
      final banner = tester.getRect(find.byKey(const Key('amb-banner')));
      final name = tester.getCenter(find.byKey(const Key('amb-title-text')));
      expect(banner.contains(name), isTrue);
      expect((name.dy - banner.center.dy).abs(), lessThan(2));
      Future<void> swipe(String key, double by) async {
        await tester.fling(find.byKey(Key(key)), Offset(by, 0), 800, warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      await swipe('amb-banner', 200);
      expect(title(tester), 'Ready', reason: 'nothing before the first');
      await swipe('amb-banner', -200);
      expect(title(tester), 'Selected');
      await swipe('amb-title', -150);
      expect(title(tester), 'Rain');
      await swipe('amb-banner', 200);
      expect(title(tester), 'Selected');
      // A slow drag counts too.
      await tester.timedDrag(find.byKey(const Key('amb-banner')), const Offset(-150, 0), const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(title(tester), 'Rain');
    });

    screenTest('the group list shows circles or banners, and remembers which', (tester) async {
      await c.setBanner('Rain', onePixel, const BannerFraming());
      await open(tester);
      await tap(tester, 'amb-title');
      final rain = find.byKey(const ValueKey('amb-cat-Rain'));
      expect(tester.widget<CircleAvatar>(find.descendant(of: rain, matching: find.byType(CircleAvatar))).foregroundImage, isNotNull);
      await tap(tester, 'amb-list-banners');
      expect(c.listBanners, isTrue);
      expect(tester.getSize(rain).height, 100);
      expect(find.descendant(of: rain, matching: find.byType(Image)), findsOneWidget);
      final label = tester.getRect(find.descendant(of: rain, matching: find.text('Rain')));
      final card = tester.getRect(rain);
      expect(card.right - label.right, lessThan(30));
      expect(card.bottom - label.bottom, lessThan(20));
      await tester.tap(rain);
      await tester.pumpAndSettle();
      expect(title(tester), 'Rain');
      await tap(tester, 'amb-title');
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('amb-list-banners'))).selected, isTrue);
      await tap(tester, 'amb-list-circles');
      expect(c.listBanners, isFalse);
      expect(find.byType(CircleAvatar), findsWidgets);
    });

    screenTest('from the other phone the list has no banner choice', (tester) async {
      await open(tester, owned: false);
      await tap(tester, 'amb-title');
      expect(find.byKey(const Key('amb-list-banners')), findsNothing);
    });

    screenTest('the beats say they need headphones, on the banner and on each sound', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('amb-headphones')), findsNothing);
      await goTo(tester, ambienceBeatCategory);
      expect(find.text('Use headphones'), findsOneWidget);
      expect(find.byKey(const Key('amb-headphones-art')), findsOneWidget);
      expect(find.byKey(const ValueKey('amb-phones-beat-focus')), findsOneWidget);
      await tap(tester, 'amb-headphones');
      expect(find.textContaining('stereo headphones'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey('amb-sound-beat-deep-sleep')));
      await tester.pumpAndSettle();
      expect(find.text('Left ear 199.75 Hz · Right ear 200.25 Hz'), findsOneWidget);
      expect(find.byKey(const Key('amb-replace')), findsNothing);
      expect(find.byKey(const Key('amb-rename')), findsNothing);
    });

    screenTest('your own sound is renamed from its menu', (tester) async {
      await c.addOwnSound('Box', '/d/box.mp3');
      await open(tester, size: const Size(400, 1900));
      final id = c.state.sounds.last.id;
      await tester.longPress(find.byKey(ValueKey('amb-sound-$id')));
      await tester.pumpAndSettle();
      await tap(tester, 'amb-rename');
      await tester.enterText(find.byKey(const Key('amb-name')), 'Music box');
      await tap(tester, 'amb-name-save');
      expect(find.text('Music box'), findsOneWidget);
    });

    screenTest('"Use default" is what takes a chosen picture back', (tester) async {
      await open(tester);
      await tester.longPress(find.byKey(const ValueKey('amb-sound-white-noise')));
      await tester.pumpAndSettle();
      await tap(tester, 'amb-icon');
      expect(find.text('Use default'), findsOneWidget);
    });

    screenTest('all of it fits a narrow, short phone', (tester) async {
      await c.setBanner(ambienceBeatCategory, onePixel, const BannerFraming(aspect: ambienceTallestBanner));
      await c.setBanner('Ready', onePixel, const BannerFraming(aspect: 4.5));
      await open(tester, size: const Size(320, 560));
      expect(tester.takeException(), isNull);
      await goTo(tester, ambienceBeatCategory);
      expect(tester.takeException(), isNull);
      await tap(tester, 'amb-title');
      await tap(tester, 'amb-list-banners');
      expect(tester.takeException(), isNull);
    });
  });
}
