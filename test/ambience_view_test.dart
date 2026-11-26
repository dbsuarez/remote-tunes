import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/ambience/ambience_controller.dart';
import 'package:remote_tunes/features/ambience/ambience_icons.dart';
import 'package:remote_tunes/features/ambience/ambience_models.dart';
import 'package:remote_tunes/features/ambience/ambience_view.dart';

import 'ambience_controller_test.dart' show FakeEngine, FakeFiles, MemoryAmbienceStore;

void main() {
  late FakeEngine engine;
  late AmbienceController c;
  String? picked;
  List<String>? folder;
  var inFolder = <String>[];

  setUp(() {
    engine = FakeEngine();
    c = AmbienceController(engine: engine, files: FakeFiles(), store: MemoryAmbienceStore());
    picked = '/down/rain-loop.mp3';
    inFolder = [];
  });

  AmbienceOwner owner() => AmbienceOwner(
        pickFolder: () async => folder,
        setIcon: c.setIcon,
        watchedFolder: () => c.watchedFolder,
        watchFolder: c.setWatchedFolder,
        checkFolder: () async => c.watchedFolder == null ? const [] : c.connectNew(inFolder),
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

  group('importing a folder', () {
    setUp(() => folder = ['/f/Rain.wav', '/f/Campfire.mp3', '/f/Peaceful Lake.mp3', '/f/notes.txt']);

    Future<void> choose(WidgetTester tester, String file, String target) async {
      await tester.tap(find.byKey(ValueKey('amb-import-to-$file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('amb-target-$target')));
      await tester.pumpAndSettle();
    }

    screenTest('fills the matching sounds and makes the rest your own', (tester) async {
      await open(tester);
      await tap(tester, 'amb-import');
      expect(find.text('Import 3 sounds'), findsOneWidget);
      expect(find.text('notes.txt'), findsNothing);
      await tap(tester, 'amb-import-go');
      expect(c.state.sound('rain')!.available, isTrue);
      expect(c.state.sound('campfire')!.available, isTrue);
      expect(c.state.sounds.last.name, 'Peaceful Lake');
      expect(engine.voices, isEmpty, reason: 'importing plays nothing');
      expect(find.textContaining('Added 3 sounds'), findsOneWidget);
    });

    screenTest('a file can be sent elsewhere or left out; a sound takes one file', (tester) async {
      await open(tester);
      await tap(tester, 'amb-import');
      await choose(tester, 'Peaceful Lake.mp3', 'rain');
      await choose(tester, 'Campfire.mp3', '+skip');
      expect(find.text('Import 2 sounds'), findsOneWidget);
      await tap(tester, 'amb-import-go');
      expect(c.state.sound('campfire')!.available, isFalse);
      expect(c.state.sound('rain')!.available, isTrue);
      expect(c.state.sounds.last.name, 'Rain', reason: 'the file that had Rain became a new sound');
    });

    screenTest('says which would replace a file, and Cancel changes nothing', (tester) async {
      await open(tester);
      await c.addFile('rain', '/old/rain.mp3');
      await tester.pump();
      await tap(tester, 'amb-import');
      expect(find.text('Replaces the file it has now'), findsOneWidget);
      await tap(tester, 'amb-import-cancel');
      expect(c.state.sound('campfire')!.available, isFalse);
    });

    screenTest('a folder with no sound files says so; choosing none does nothing', (tester) async {
      folder = ['/f/song.m4a'];
      await open(tester);
      await tap(tester, 'amb-import');
      expect(find.textContaining('No MP3, OGG, WAV or FLAC files'), findsOneWidget);
      folder = null;
      await tap(tester, 'amb-import');
      expect(find.byKey(const Key('amb-import-go')), findsNothing);
    });

    screenTest('environments get their own group, above My sounds, and can be deleted', (tester) async {
      folder = ['/f/water_env_swamp.mp3', '/f/Music Box.mp3'];
      await open(tester);
      expect(find.byKey(const ValueKey('amb-group-$ambienceEnvironmentCategory')), findsNothing);
      await tap(tester, 'amb-import');
      expect(find.text('Environment "Swamp"'), findsOneWidget);
      await tap(tester, 'amb-import-go');
      expect(find.byKey(const ValueKey('amb-group-$ambienceEnvironmentCategory')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('amb-group-$ambienceEnvironmentCategory'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const ValueKey('amb-group-$ambienceOwnCategory'))).dy));
      final swamp = c.state.sounds.firstWhere((s) => s.name == 'Swamp');
      expect(swamp.category, ambienceEnvironmentCategory);
      final again = AmbienceController(engine: engine, files: FakeFiles(), store: c.store);
      await again.load();
      expect(again.state.sound(swamp.id)!.category, ambienceEnvironmentCategory);
      again.dispose();
      await tester.longPress(find.byKey(ValueKey('amb-sound-${swamp.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this sound'), findsOneWidget);
      await tap(tester, 'amb-remove');
      expect(find.byKey(const ValueKey('amb-group-$ambienceEnvironmentCategory')), findsNothing);
    });

    screenTest('is not offered from the other phone', (tester) async {
      await open(tester, owned: false);
      expect(find.byKey(const Key('amb-import')), findsNothing);
    });
  });

  group('the watched folder', () {
    setUp(() => folder = ['/f/Whale.mp3']);

    Future<void> importOnce(WidgetTester tester) async {
      await open(tester);
      await tap(tester, 'amb-import');
      await tap(tester, 'amb-import-go');
    }

    screenTest('is remembered after an import, and new matching files connect on coming back', (tester) async {
      await importOnce(tester);
      expect(c.watchedFolder, '/f');
      expect(find.textContaining('New files in "f"'), findsOneWidget);
      inFolder = ['/f/Whale.mp3', '/f/Dolphins.mp3', '/f/random take.mp3'];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(c.state.sound('dolphins')!.available, isTrue);
      expect(find.textContaining('Added from your folder: Dolphins'), findsOneWidget);
      expect(c.state.sounds.where((s) => s.name == 'random take'), isEmpty);
      expect(engine.voices, isEmpty, reason: 'connecting plays nothing');
    });

    screenTest('connects when the screen opens', (tester) async {
      await c.setWatchedFolder('/f');
      inFolder = ['/f/Harp.mp3'];
      await open(tester);
      await tester.pumpAndSettle();
      expect(c.state.sound('harp')!.available, isTrue);
    });

    screenTest('a file taken away is not put back, until the folder is chosen again', (tester) async {
      await importOnce(tester);
      inFolder = ['/f/Whale.mp3'];
      await c.removeFile('whale');
      await tester.pumpAndSettle();
      await tap(tester, 'amb-check');
      expect(c.state.sound('whale')!.available, isFalse);
      expect(find.textContaining('No new files'), findsOneWidget);
      await tap(tester, 'amb-import');
      await tap(tester, 'amb-import-go');
      expect(c.state.sound('whale')!.available, isTrue);
    });

    screenTest('Import and Rescan are icons; Rescan with no folder says what to do', (tester) async {
      await open(tester);
      expect(find.text('Import a folder'), findsNothing);
      expect(find.byTooltip('Import a folder'), findsOneWidget);
      expect(find.byTooltip('Rescan the folder'), findsOneWidget);
      await tap(tester, 'amb-check');
      expect(find.textContaining('Import a folder first'), findsOneWidget);
    });

    screenTest('can be let go', (tester) async {
      await importOnce(tester);
      await tap(tester, 'amb-unwatch');
      expect(c.watchedFolder, isNull);
      expect(find.byKey(const Key('amb-watching')), findsNothing);
    });
  });

  group('icons', () {
    Future<void> hold(WidgetTester tester, String id) async {
      await tester.longPress(find.byKey(ValueKey('amb-sound-$id')));
      await tester.pumpAndSettle();
    }

    Finder onTile(String id, IconData icon) => find.descendant(of: find.byKey(ValueKey('amb-sound-$id')), matching: find.byIcon(icon));

    screenTest('a sound of your own can be given any icon, and it is remembered', (tester) async {
      await open(tester);
      await c.addOwnSound('Box', '/d/box.wav');
      await tester.pumpAndSettle();
      final id = c.state.sounds.last.id;
      expect(onTile(id, Icons.music_note_rounded), findsOneWidget);
      expect(find.text('Hold a sound to change its picture.'), findsOneWidget);
      await hold(tester, id);
      await tap(tester, 'amb-icon');
      await tap(tester, 'amb-icon-tab-icons');
      await tester.enterText(find.byKey(const Key('amb-icon-search')), 'toy');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('amb-icon-toy')));
      await tester.pumpAndSettle();
      expect(onTile(id, Icons.toys_rounded), findsOneWidget);
      final again = AmbienceController(engine: engine, files: FakeFiles(), store: c.store);
      await again.load();
      expect(again.state.sound(id)!.icon, 'toy');
      expect(AmbienceState.fromJson(again.state.toJson()).sound(id)!.icon, 'toy', reason: 'the other phone sees it');
      again.dispose();
      await hold(tester, id);
      await tap(tester, 'amb-icon');
      await tap(tester, 'amb-icon-usual');
      expect(onTile(id, Icons.music_note_rounded), findsOneWidget);
    });

    screenTest('an emoji can be found by a word and used', (tester) async {
      await open(tester);
      await hold(tester, 'white-noise');
      await tap(tester, 'amb-icon');
      await tester.enterText(find.byKey(const Key('amb-icon-search')), 'frog');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('amb-icon-emoji:🐸')));
      await tester.pumpAndSettle();
      expect(c.state.sound('white-noise')!.icon, 'emoji:🐸');
      expect(find.descendant(of: find.byKey(const ValueKey('amb-sound-white-noise')), matching: find.text('🐸')), findsOneWidget);
    });

    screenTest('any emoji typed into the search can be used; nonsense finds nothing', (tester) async {
      await open(tester);
      await hold(tester, 'white-noise');
      await tap(tester, 'amb-icon');
      await tester.enterText(find.byKey(const Key('amb-icon-search')), 'qqqq');
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing found'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('amb-icon-search')), '🦥');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('amb-icon-emoji:🦥')));
      await tester.pumpAndSettle();
      expect(c.state.sound('white-noise')!.icon, 'emoji:🦥');
    });

    test('every emoji entry has a picture and words, and there are plenty', () {
      final all = [for (final g in ambienceEmoji.values) ...g];
      expect(all.every((e) => e.indexOf(' ') > 0 && e.substring(e.indexOf(' ') + 1).trim().isNotEmpty), isTrue);
      expect(all.length, greaterThan(250));
      expect(ambienceIconLibrary.length, greaterThan(130));
    });

    screenTest('a built-in noise offers only the picture', (tester) async {
      await open(tester);
      await hold(tester, 'white-noise');
      expect(find.byKey(const Key('amb-icon')), findsOneWidget);
      expect(find.byKey(const Key('amb-replace')), findsNothing);
      expect(find.byKey(const Key('amb-remove')), findsNothing);
    });

    screenTest('the library fits a narrow phone', (tester) async {
      await open(tester, size: const Size(320, 600));
      await c.addFile('rain', '/d/rain.mp3');
      await tester.pumpAndSettle();
      await hold(tester, 'rain');
      await tap(tester, 'amb-icon');
      expect(tester.takeException(), isNull);
    });
  });

  Future<void> category(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.byKey(ValueKey('amb-cat-$name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('amb-cat-$name')));
    await tester.pumpAndSettle();
  }

  screenTest('Ready shows what can be played; a category shows all its places', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('amb-sound-white-noise')), findsOneWidget);
    expect(find.byKey(const ValueKey('amb-sound-gray-noise')), findsOneWidget);
    expect(find.byKey(const ValueKey('amb-sound-rain')), findsNothing, reason: 'no file yet');
    expect(find.byKey(const Key('amb-add-own')), findsOneWidget);
    expect(status(tester), 'Tap a sound to begin');
    expect(tester.widget<IconButton>(find.byKey(const Key('amb-play'))).onPressed, isNull);
    await category(tester, 'Rain');
    expect(find.byKey(const ValueKey('amb-add-rain')), findsOneWidget);
    expect(find.byKey(const ValueKey('amb-sound-umbrella')), findsOneWidget);
    expect(find.byKey(const ValueKey('amb-sound-white-noise')), findsNothing);
    await c.addFile('umbrella', '/d/u.mp3');
    await tester.pumpAndSettle();
    await category(tester, 'ready');
    expect(find.byKey(const ValueKey('amb-sound-umbrella')), findsOneWidget);
    expect(find.text('Rain'), findsWidgets);
  });

  screenTest('swiping goes from group to group, and the chip follows', (tester) async {
    await open(tester);
    bool selected(String name) => tester.widget<ChoiceChip>(find.byKey(ValueKey('amb-cat-$name'))).selected;
    expect(selected('ready'), isTrue);
    await tester.fling(find.byKey(const Key('amb-pages')), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(selected('Rain'), isTrue);
    expect(find.byKey(const ValueKey('amb-sound-umbrella')), findsOneWidget);
    await tester.fling(find.byKey(const Key('amb-pages')), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(selected('Ocean'), isTrue);
    expect(find.byKey(const ValueKey('amb-sound-whale')), findsOneWidget);
    await tester.fling(find.byKey(const Key('amb-pages')), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(selected('Rain'), isTrue);
  });

  screenTest('a new group appearing does not move you off the one you are on', (tester) async {
    await open(tester);
    await category(tester, ambienceOwnCategory);
    await c.addOwnSound('Swamp', '/d/s.mp3', environment: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('amb-group-$ambienceOwnCategory')), findsOneWidget);
    expect(find.byKey(const ValueKey('amb-group-$ambienceEnvironmentCategory')), findsNothing);
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
    await category(tester, 'Rain');
    await sound(tester, 'rain');
    expect(engine.paths['rain'], '/kept/rain.mp3');
    expect(find.byKey(const ValueKey('amb-add-rain')), findsNothing);
  });

  screenTest('a file of the wrong kind is explained', (tester) async {
    picked = '/down/rain.m4a';
    await open(tester);
    await category(tester, 'Rain');
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
    expect(find.textContaining('Playing without Morning Rain'), findsOneWidget);
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
    await category(tester, 'Rain');
    await sound(tester, 'rain');
    expect(find.textContaining('on the phone that plays'), findsOneWidget);
    await category(tester, 'ready');
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
