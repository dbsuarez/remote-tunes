import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/ambience/ambience_controller.dart';
import 'package:remote_tunes/features/ambience/ambience_models.dart';
import 'package:remote_tunes/features/ambience/ambience_view.dart';

import 'ambience_controller_test.dart' show FakeEngine, FakeFiles, MemoryAmbienceStore;

void main() {
  late FakeEngine engine;
  late AmbienceController c;
  String? picked;

  setUp(() {
    engine = FakeEngine();
    c = AmbienceController(engine: engine, files: FakeFiles(), store: MemoryAmbienceStore());
    picked = '/down/rain-loop.mp3';
  });

  AmbienceOwner owner() => AmbienceOwner(
        pickFile: () async => picked,
        addFile: c.addFile,
        addOwnSound: c.addOwnSound,
        removeFile: c.removeFile,
        setMaxVolume: c.setMaxVolume,
      );

  Future<void> open(WidgetTester tester, {bool owned = true, Size size = const Size(400, 1900), bool enabled = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await c.load();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AmbienceView(controls: c, owner: owned ? owner() : null, enabled: enabled))));
    await tester.pump();
  }

  void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await c.stop();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      c.dispose();
    });
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> sound(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('amb-sound-$id')));
    await tester.pumpAndSettle();
  }

  String status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('amb-status'))).data!;

  screenTest('shows the sounds by category, with a plus on those with no file', (tester) async {
    await open(tester);
    for (final heading in ['Rain', 'Water', 'Night', 'Wind and Fire', 'Nature', 'Noise', ambienceOwnCategory]) {
      expect(find.text(heading), findsWidgets);
    }
    expect(find.byKey(const ValueKey('amb-add-rain')), findsOneWidget);
    expect(find.byKey(const ValueKey('amb-add-white-noise')), findsNothing);
    expect(status(tester), 'Tap a sound to begin');
    expect(tester.widget<IconButton>(find.byKey(const Key('amb-play'))).onPressed, isNull);
  });

  screenTest('a tap switches a sound on, with its volume slider; again switches it off', (tester) async {
    await open(tester);
    await sound(tester, 'white-noise');
    await sound(tester, 'brown-noise');
    expect(engine.voices.keys, {'white-noise', 'brown-noise'});
    expect(status(tester), '2 sounds on');
    expect(find.byKey(const ValueKey('amb-volume-white-noise')), findsOneWidget);
    final before = engine.voices['white-noise']!;
    await tester.drag(find.byKey(const ValueKey('amb-volume-white-noise')), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(engine.voices['white-noise']!, greaterThan(before));
    await sound(tester, 'white-noise');
    expect(find.byKey(const ValueKey('amb-volume-white-noise')), findsNothing);
    expect(engine.voices.keys, {'brown-noise'});
  });

  screenTest('tapping a sound with no file picks one, and it plays', (tester) async {
    await open(tester);
    await sound(tester, 'rain');
    expect(engine.paths['rain'], '/kept/rain.mp3');
    expect(find.byKey(const ValueKey('amb-add-rain')), findsNothing);
  });

  screenTest('a file of the wrong kind is explained', (tester) async {
    picked = '/down/rain.m4a';
    await open(tester);
    await sound(tester, 'rain');
    expect(find.textContaining('MP3, OGG, WAV or FLAC'), findsOneWidget);
    expect(engine.voices, isEmpty);
  });

  screenTest('a sound of your own is added with a name, and deleted by holding it', (tester) async {
    picked = '/down/music box.wav';
    await open(tester);
    await tap(tester, 'amb-add-own');
    expect(tester.widget<TextField>(find.byKey(const Key('amb-name'))).controller!.text, 'music box');
    await tap(tester, 'amb-name-save');
    expect(find.text('music box'), findsOneWidget);
    final id = c.state.sounds.last.id;
    await tester.longPress(find.byKey(ValueKey('amb-sound-$id')));
    await tester.pumpAndSettle();
    await tap(tester, 'amb-remove');
    expect(find.text('music box'), findsNothing);
  });

  screenTest('pause, play and stop', (tester) async {
    await open(tester);
    await sound(tester, 'pink-noise');
    await tap(tester, 'amb-play');
    expect(engine.paused, isTrue);
    await tap(tester, 'amb-play');
    expect(engine.paused, isFalse);
    await tap(tester, 'amb-stop');
    expect(engine.voices, isEmpty);
    await tap(tester, 'amb-play');
    expect(engine.voices.keys, {'pink-noise'});
  });

  screenTest('the sleep timer shows what is left', (tester) async {
    await open(tester);
    await sound(tester, 'pink-noise');
    await tap(tester, 'amb-timer');
    await tap(tester, 'amb-timer-45');
    expect(status(tester), contains('45:00 left'));
    await tap(tester, 'amb-timer');
    await tap(tester, 'amb-timer-0');
    expect(status(tester), isNot(contains('left')));
  });

  screenTest('a mix is saved, found, played and deleted', (tester) async {
    await open(tester);
    await sound(tester, 'pink-noise');
    await sound(tester, 'brown-noise');
    await tap(tester, 'amb-mixes');
    await tap(tester, 'amb-mix-save');
    await tester.enterText(find.byKey(const Key('amb-name')), 'Pampatulog');
    await tap(tester, 'amb-name-save');
    expect(status(tester), 'Pampatulog · 2 sounds');
    await sound(tester, 'brown-noise');
    final id = c.state.mixes.last.id;
    await tap(tester, 'amb-mixes');
    await tester.tap(find.byKey(ValueKey('amb-mix-$id')));
    await tester.pumpAndSettle();
    expect(engine.voices.keys, {'pink-noise', 'brown-noise'});
    await tap(tester, 'amb-mixes');
    await tester.tap(find.byKey(ValueKey('amb-mix-delete-$id')));
    await tester.pumpAndSettle();
    expect(c.state.mixes, hasLength(ambiencePresets.length));
  });

  screenTest('a ready-made mix says what it plays without', (tester) async {
    await open(tester);
    await tap(tester, 'amb-mixes');
    await tester.tap(find.byKey(const ValueKey('amb-mix-sleep')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing without Rain'), findsOneWidget);
    expect(engine.voices.keys, {'white-noise'});
  });

  screenTest('the maximum volume stops the volume slider there', (tester) async {
    await open(tester);
    await sound(tester, 'white-noise');
    await c.setMaxVolume(0.3);
    await tester.pump();
    await tester.drag(find.byKey(const Key('amb-master')), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(c.state.master, closeTo(0.3, 0.001));
    await tap(tester, 'amb-max');
    await tester.drag(find.byKey(const Key('amb-max-slider')), const Offset(400, 0));
    await tap(tester, 'amb-max-save');
    expect(c.state.maxVolume, closeTo(1, 0.001));
  });

  screenTest('from the other phone: no files or maximum, and it says where to add them', (tester) async {
    await open(tester, owned: false);
    expect(find.byKey(const Key('amb-max')), findsNothing);
    expect(find.byKey(const Key('amb-add-own')), findsNothing);
    await sound(tester, 'rain');
    expect(find.textContaining('on the phone that plays'), findsOneWidget);
    await sound(tester, 'white-noise');
    expect(engine.voices.keys, {'white-noise'});
  });

  screenTest('nothing can be done while reconnecting', (tester) async {
    await open(tester, enabled: false);
    await sound(tester, 'white-noise');
    expect(engine.voices, isEmpty);
  });

  screenTest('fits a narrow phone', (tester) async {
    await open(tester, size: const Size(320, 600));
    await c.setActive('white-noise', true);
    await c.setTimer(120);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
