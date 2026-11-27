import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/features/ambience/ambience_backup.dart';
import 'package:remote_tunes/features/ambience/ambience_beats.dart';
import 'package:remote_tunes/features/ambience/ambience_controller.dart';
import 'package:remote_tunes/features/ambience/ambience_import.dart';
import 'package:remote_tunes/features/ambience/ambience_models.dart';
import 'package:remote_tunes/features/ambience/ambience_phone.dart' show PhoneAmbienceFiles;
import 'package:remote_tunes/features/ambience/ambience_view.dart';
import 'package:remote_tunes/features/update/update_service.dart';

import 'ambience_controller_test.dart' show FakeEngine, FakeFiles, MemoryAmbienceStore;

void main() {
  late FakeEngine engine;
  late MemoryAmbienceStore store;
  late AmbienceController c;

  setUp(() {
    engine = FakeEngine();
    store = MemoryAmbienceStore();
    c = AmbienceController(engine: engine, files: FakeFiles(), store: store);
  });

  List<String> inCategory(AmbienceController of, String id) =>
      [for (final s in of.state.sounds) if (s.category == id) s.id];

  Future<AmbienceController> reopened() async {
    final again = AmbienceController(engine: engine, files: FakeFiles(), store: store);
    await again.load();
    return again;
  }

  Future<String> own(String name, {String? category}) async {
    await c.addOwnSound(name, '/d/$name.mp3', category: category);
    return c.state.sounds.firstWhere((s) => s.name == name).id;
  }

  group('categories', () {
    test('are made, renamed, put in order and deleted, and all of it is remembered', () async {
      await c.load();
      final first = c.categories.first.id;
      expect(c.categories.map((x) => x.id), containsAll([ambienceEnvironmentCategory, ambienceOwnCategory, ambienceBeatCategory]));
      final mine = await c.createCategory('  Bedtime  ');
      await expectLater(c.createCategory('bedtime'), throwsA(isA<AmbienceException>()));
      await expectLater(c.createCategory(' '), throwsA(isA<AmbienceException>()));
      await c.renameCategory('Rain', 'Ulan');
      await expectLater(c.renameCategory(mine, 'Ulan'), throwsA(isA<AmbienceException>()));
      await c.renameCategory(mine, 'Antok');
      await c.setCategoryOrder([mine, ...c.categories.map((x) => x.id).where((id) => id != mine)]);
      var again = await reopened();
      expect(again.categories.first.name, 'Antok');
      expect(again.categories.first.custom, isTrue);
      expect(again.categories[1].id, first);
      expect(again.state.categoryName('Rain'), 'Ulan');
      expect(inCategory(again, 'Rain'), contains('rain'), reason: 'the id stays, only the name changes');
      await again.renameCategory('Rain', 'Rain');
      expect(again.state.categoryName('Rain'), 'Rain');
      await again.deleteCategory('Rain');
      expect(again.categories.map((x) => x.id), contains('Rain'), reason: 'the app\'s own stay');
      await again.deleteCategory(mine);
      expect(again.categories.map((x) => x.id), isNot(contains(mine)));
      again.dispose();
      c.dispose();
    });

    test('sounds move between them and keep the order they are put in', () async {
      final mine = await c.createCategory('Bedtime');
      final box = await own('Box');
      final swamp = await own('Swamp', category: mine);
      expect(inCategory(c, mine), [swamp]);
      await c.moveSound('white-noise', mine);
      await c.moveSound(box, 'Rain');
      expect(inCategory(c, mine), ['white-noise', swamp]);
      expect(inCategory(c, 'Rain').last, box);
      expect(c.state.sound(box)!.own, isTrue);
      expect(isOwnAmbienceSound(c.state.sound(box)!), isTrue);
      expect(isOwnAmbienceSound(c.state.sound('white-noise')!), isFalse);
      await c.setSoundOrder(mine, [swamp, 'white-noise']);
      await c.moveSound('pink-noise', mine);
      var again = await reopened();
      expect(inCategory(again, mine), [swamp, 'white-noise', 'pink-noise']);
      await again.moveSound('white-noise', 'Noise');
      expect(inCategory(again, 'Noise'), contains('white-noise'));
      await again.deleteCategory(mine);
      expect(inCategory(again, ambienceOwnCategory), contains(swamp), reason: 'back where it came from');
      expect(inCategory(again, 'Noise'), contains('pink-noise'));
      again.dispose();
      c.dispose();
    });

    test('several move together, in the order given', () async {
      final mine = await c.createCategory('Bedtime');
      await c.moveSounds(['pink-noise', 'white-noise', 'rain', 'nothing'], mine);
      expect(inCategory(c, mine), ['rain', 'white-noise', 'pink-noise'], reason: 'unarranged: as they come');
      await c.setSoundOrder(mine, ['rain']);
      await c.moveSounds(['brown-noise', 'wind'], mine);
      expect(inCategory(c, mine).take(3), ['rain', 'brown-noise', 'wind']);
      await c.moveSounds(['rain', 'wind'], mine);
      expect(inCategory(c, mine).take(3), ['rain', 'brown-noise', 'wind'], reason: 'already there');
      c.dispose();
    });

    test('a moved sound of your own still takes a file of its name on import', () async {
      final box = await own('Box');
      await c.moveSound(box, 'Rain');
      final rows = planImport(['/f/box.mp3'], c.state.sounds);
      expect(rows.single.target, box);
      c.dispose();
    });

    test('deleting a sound of your own forgets where it was and its switches', () async {
      final box = await own('Box');
      await c.moveSound(box, 'Rain');
      await c.setSoundFlag(box, ambienceFlagOnce, true);
      await c.removeFile(box);
      expect(c.state.sound(box), isNull);
      expect(c.soundFlags(box), isEmpty);
      expect(store.value, isNot(contains(box)));
      c.dispose();
    });

    test('travel to the other phone', () async {
      final mine = await c.createCategory('Bedtime');
      await c.setCategoryFlag(mine, ambienceFlagAlone, true);
      await c.moveSound('white-noise', mine);
      final there = AmbienceState.fromJson(c.state.toJson(readyOnly: true));
      expect(there.categoryName(mine), 'Bedtime');
      expect(there.sound('white-noise')!.category, mine);
      expect(there.sound('white-noise')!.alone, isTrue);
      c.dispose();
    });

    test('are carried by the backup, joining one of the same name', () async {
      final root = await Directory.systemTemp.createTemp('rt_org_');
      addTearDown(() => root.delete(recursive: true));
      AmbienceController phone(String name) => AmbienceController(
          engine: FakeEngine(), files: PhoneAmbienceFiles(() async => Directory(p.join(root.path, name))), store: MemoryAmbienceStore());
      final file = File(p.join(root.path, 'box.mp3'))..writeAsBytesSync([1]);
      final old = phone('old');
      final mine = await old.createCategory('Bedtime');
      final other = await old.createCategory('Work');
      await old.addOwnSound('Box', file.path, category: mine);
      await old.moveSound('white-noise', other);
      await old.renameCategory('Rain', 'Ulan');
      await old.setCategoryFlag(mine, ambienceFlagOnce, true);
      await old.setSoundFlag('pink-noise', ambienceFlagAlone, true);
      await old.setCategoryOrder([other, mine]);
      final backup = await writeAmbienceBackup(old, root.path);

      final fresh = phone('new');
      final theirs = await fresh.createCategory('bedtime');
      await restoreAmbienceBackup(fresh, backup.path);
      expect(fresh.categories.where((x) => x.name.toLowerCase() == 'bedtime'), hasLength(1));
      final box = fresh.state.sounds.firstWhere((s) => s.name == 'Box');
      expect(box.category, theirs);
      expect(box.once, isTrue);
      expect(fresh.state.categoryName('Rain'), 'Ulan');
      expect(fresh.state.categoryName(fresh.state.sound('white-noise')!.category), 'Work');
      expect(fresh.state.sound('pink-noise')!.alone, isTrue);
      expect(fresh.categories.take(2).map((x) => x.name), ['Work', 'bedtime']);
      old.dispose();
      fresh.dispose();
    });
  });

  group('Play once and Play alone', () {
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    test('alone: it puts the others out, and any other puts it out', () async {
      await c.setSoundFlag('beat-focus', ambienceFlagAlone, true);
      await c.setActive('white-noise', true);
      await c.setActive('pink-noise', true);
      await c.setActive('beat-focus', true);
      expect(c.state.active.keys, ['beat-focus']);
      expect(engine.voices.keys, ['beat-focus']);
      await c.setActive('white-noise', true);
      expect(c.state.active.keys, ['white-noise']);
      expect(engine.voices.keys, ['white-noise']);
      c.dispose();
    });

    test('switching it on while sounds play leaves only the one chosen; a mix with it plays only it', () async {
      await c.setActive('white-noise', true);
      await c.setActive('pink-noise', true);
      await c.setActive('brown-noise', true);
      await c.saveMix('Three');
      await c.setSoundFlag('pink-noise', ambienceFlagAlone, true);
      expect(c.state.active.keys, ['pink-noise']);
      expect(engine.voices.keys, ['pink-noise']);
      await c.setActive('pink-noise', false);
      await c.startMix(c.state.mixes.last.id);
      expect(engine.voices.keys, ['pink-noise']);
      c.dispose();
    });

    test('a whole category can be set, and a sound moved into it follows', () async {
      final mine = await c.createCategory('Beats');
      await c.setCategoryFlag(mine, ambienceFlagAlone, true);
      await c.setCategoryFlag(mine, ambienceFlagOnce, true);
      await c.setCategoryFlag(mine, ambienceFlagHeadphones, true);
      await c.setActive('white-noise', true);
      await c.setActive('pink-noise', true);
      await c.moveSound('pink-noise', mine);
      expect(c.state.active.keys, ['pink-noise']);
      expect(engine.onceOnly, {'pink-noise'}, reason: 'the voice stops looping');
      final s = c.state.sound('pink-noise')!;
      expect((s.once, s.alone, s.headphones), (true, true, true));
      expect(c.soundFlags('pink-noise'), isEmpty, reason: 'set on the category, not the sound');
      await c.moveSound('pink-noise', 'Noise');
      expect(engine.onceOnly, isEmpty);
      c.dispose();
    });

    test('once: it plays without looping, shows what is left, and switches itself off at the end', () async {
      await c.setSoundFlag('beat-focus', ambienceFlagOnce, true);
      await c.setActive('white-noise', true);
      await c.setActive('beat-focus', true);
      expect(engine.onceOnly, {'beat-focus'});
      expect(c.state.onceLeft, 90);
      engine.ended!('beat-focus');
      await settle();
      expect(c.state.active.keys, ['white-noise']);
      expect(c.state.onceLeft, isNull);
      expect(c.state.playing, isTrue);
      engine.ended!('white-noise');
      await settle();
      expect(c.state.playing, isFalse, reason: 'nothing left on');
      expect((await reopened()).state.active, isEmpty);
      c.dispose();
    });

    test('an end told twice, or for a sound already off, does nothing', () async {
      await c.setActive('white-noise', true);
      engine.ended!('beat-focus');
      await settle();
      expect(c.state.active.keys, ['white-noise']);
      c.dispose();
    });

    test('the beats keep their headphones mark wherever they are', () async {
      await c.moveSound('beat-focus', 'Noise');
      expect(c.state.sound('beat-focus')!.headphones, isTrue);
      expect(c.state.sound('white-noise')!.headphones, isFalse);
      c.dispose();
    });
  });

  group('on the screen', () {
    AmbienceOwner owner() => AmbienceOwner(
          pickFile: () async => '/d/music box.mp3',
          addFile: c.addFile,
          addOwnSound: c.addOwnSound,
          removeFile: c.removeFile,
          setMaxVolume: c.setMaxVolume,
          setIcon: c.setIcon,
          rename: c.renameSound,
          organizer: c,
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
      await tester.pumpWidget(MaterialApp(home: AmbienceView(controls: c, owner: owned ? owner() : null)));
      await tester.pump();
    }

    Future<void> tap(WidgetTester tester, Object key) async {
      final finder = find.byKey(key is Key ? key : Key(key as String));
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> manage(WidgetTester tester) async {
      await tap(tester, 'amb-menu');
      await tap(tester, 'amb-manage');
    }

    Future<void> goTo(WidgetTester tester, String page) async {
      await tap(tester, 'amb-title');
      await tester.ensureVisible(find.byKey(ValueKey('amb-cat-$page')));
      await tester.pumpAndSettle();
      await tap(tester, ValueKey('amb-cat-$page'));
    }

    Future<void> hold(WidgetTester tester, String id) async {
      await tester.longPress(find.byKey(ValueKey('amb-sound-$id')));
      await tester.pumpAndSettle();
    }

    screenTest('a category is made, gets a sound, and has its own page', (tester) async {
      await open(tester);
      await manage(tester);
      await tap(tester, 'amb-new-category');
      await tester.enterText(find.byKey(const Key('amb-category-name')), 'Bedtime');
      await tap(tester, 'amb-category-save');
      final id = c.categories.last.id;
      await tester.scrollUntilVisible(find.byKey(ValueKey('amb-manage-$id')), 300);
      expect(find.text('0 sounds'), findsWidgets);
      await tap(tester, ValueKey('amb-manage-$id'));
      expect(find.textContaining('Nothing here yet'), findsOneWidget);
      await tap(tester, 'amb-manage-add');
      await tap(tester, 'amb-name-save');
      expect(find.text('music box'), findsOneWidget);
      expect(find.textContaining('Custom'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await goTo(tester, id);
      expect(tester.widget<Text>(find.byKey(const Key('amb-title-text'))).data, 'Bedtime');
      expect(find.text('music box'), findsOneWidget);
      expect(find.byKey(const Key('amb-add-own')), findsOneWidget);
    });

    screenTest('categories are renamed, dragged and deleted', (tester) async {
      await c.createCategory('Bedtime');
      final id = c.categories.last.id;
      await c.setCategoryOrder([id]);
      await open(tester);
      await manage(tester);
      final first = c.categories[1].id;
      // Drag the first below the second.
      final drag = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('amb-drag-$id'))));
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 7; i++) {
        await drag.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.categories.first.id, first);
      expect(c.categories[1].id, id);
      await tap(tester, ValueKey('amb-manage-menu-$id'));
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('amb-category-name')), 'Antok');
      await tap(tester, 'amb-category-save');
      expect(find.text('Antok'), findsOneWidget);
      await tap(tester, ValueKey('amb-manage-menu-$id'));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tap(tester, 'amb-category-delete-yes');
      expect(find.text('Antok'), findsNothing);
      await tap(tester, ValueKey('amb-manage-menu-$first'));
      expect(find.text('Delete'), findsNothing, reason: 'the app\'s own cannot be deleted');
    });

    screenTest('sounds are dragged within a category', (tester) async {
      await open(tester);
      await manage(tester);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('amb-manage-Noise')), 300);
      await tap(tester, const ValueKey('amb-manage-Noise'));
      final drag = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('amb-drag-white-noise'))));
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 8; i++) {
        await drag.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(inCategory(c, 'Noise').take(2), ['pink-noise', 'white-noise']);
    });

    screenTest('several sounds are selected and moved to another category', (tester) async {
      final mine = await c.createCategory('Bedtime');
      await open(tester);
      await manage(tester);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('amb-manage-Noise')), 300);
      await tap(tester, const ValueKey('amb-manage-Noise'));
      await tester.longPress(find.byKey(const ValueKey('amb-manage-sound-white-noise')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('amb-drag-pink-noise')), findsNothing);
      expect(find.byKey(const Key('amb-manage-add')), findsNothing);
      await tap(tester, const ValueKey('amb-manage-sound-pink-noise'));
      await tap(tester, const ValueKey('amb-check-brown-noise'));
      expect(find.text('3 selected'), findsOneWidget);
      await tap(tester, const ValueKey('amb-check-brown-noise'));
      await tap(tester, 'amb-select-move');
      await tester.scrollUntilVisible(find.byKey(ValueKey('amb-move-to-$mine')), 200, scrollable: find.byType(Scrollable).last);
      await tap(tester, ValueKey('amb-move-to-$mine'));
      expect(inCategory(c, mine), ['white-noise', 'pink-noise']);
      expect(find.text('Moved 2 sounds to Bedtime'), findsOneWidget);
      expect(find.byKey(const Key('amb-select')), findsOneWidget, reason: 'selecting is over');
      expect(find.byKey(const ValueKey('amb-manage-sound-white-noise')), findsNothing);
    });

    screenTest('select all, and back leaves selecting before leaving the page', (tester) async {
      await open(tester);
      await manage(tester);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('amb-manage-Noise')), 300);
      await tap(tester, const ValueKey('amb-manage-Noise'));
      await tap(tester, 'amb-select');
      expect(tester.widget<IconButton>(find.byKey(const Key('amb-select-move'))).onPressed, isNull);
      await tap(tester, 'amb-select-all');
      expect(find.text('6 selected'), findsOneWidget);
      await tap(tester, 'amb-select-all');
      expect(find.text('0 selected'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Noise'), findsOneWidget);
      expect(find.byKey(const Key('amb-select')), findsOneWidget);
    });

    screenTest('holding a sound moves it and sets its switches, with marks on the tile', (tester) async {
      final box = await own('Box');
      await open(tester, size: const Size(400, 1900));
      await hold(tester, box);
      await tap(tester, 'amb-flag-once');
      await tap(tester, 'amb-flag-alone');
      await tester.ensureVisible(find.byKey(const Key('amb-move')));
      await tester.pumpAndSettle();
      await tap(tester, 'amb-move');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('amb-move-to-Rain')), 200,
          scrollable: find.byType(Scrollable).last);
      await tap(tester, const ValueKey('amb-move-to-Rain'));
      expect(c.state.sound(box)!.category, 'Rain');
      await goTo(tester, 'Rain');
      expect(find.byKey(ValueKey('amb-own-$box')), findsOneWidget);
      expect(find.byKey(ValueKey('amb-once-$box')), findsOneWidget);
      expect(find.byKey(ValueKey('amb-alone-$box')), findsOneWidget);
      expect(find.byKey(ValueKey('amb-phones-$box')), findsNothing);
      await tester.tap(find.byKey(ValueKey('amb-sound-$box')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('amb-status'))).data, contains('1:30 of the sound left'));
    });

    screenTest('switches set for the category cannot be changed on the sound', (tester) async {
      await c.setCategoryFlag('Noise', ambienceFlagHeadphones, true);
      await open(tester);
      await goTo(tester, 'Noise');
      expect(find.byKey(const Key('amb-headphones')), findsOneWidget, reason: 'the reminder on the banner');
      await hold(tester, 'white-noise');
      final locked = tester.widget<SwitchListTile>(find.byKey(const Key('amb-flag-phones')));
      expect((locked.value, locked.onChanged), (true, null));
      expect(find.text('Set for the whole category'), findsOneWidget);
    });

    screenTest('the other phone sees the categories but cannot arrange them', (tester) async {
      final mine = await c.createCategory('Bedtime');
      await c.createCategory('Empty');
      await c.moveSound('white-noise', mine);
      await open(tester, owned: false);
      expect(find.byKey(const Key('amb-menu')), findsNothing);
      await tap(tester, 'amb-title');
      expect(find.text('Bedtime'), findsWidgets);
      expect(find.text('Empty'), findsNothing);
    });

    screenTest('the screens fit a narrow phone', (tester) async {
      await c.createCategory('A very long category name 1234');
      await open(tester, size: const Size(320, 560));
      await manage(tester);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('amb-manage-Noise')), 300);
      await tap(tester, const ValueKey('amb-manage-Noise'));
      await tap(tester, const ValueKey('amb-manage-sound-white-noise'));
      expect(tester.takeException(), isNull);
    });
  });

  group('checking for updates when GitHub\'s allowance is used up', () {
    UpdateChecker checker({int api = 403, String? location, int file = 200, List<String>? asked}) => UpdateChecker(
          client: MockClient((r) async {
            asked?.add('${r.method} ${r.url}');
            if (r.url.host == 'api.github.com') return http.Response('rate limited', api);
            if (r.url.path.endsWith('/releases/latest')) {
              return http.Response('', location == null ? 200 : 302, headers: {if (location != null) 'location': location});
            }
            return http.Response('x' * 123, file);
          }),
        );
    const page = 'https://github.com/dbsuarez/remote-tunes/releases/tag/v1.2.0';

    test('the releases page gives the version, and the download for this phone', () async {
      final asked = <String>[];
      final info = (await checker(location: page, asked: asked).latest(currentVersion: '1.1.0', abi: 'arm64-v8a'))!;
      expect(info.version, '1.2.0');
      expect(info.apkUrl, 'https://github.com/dbsuarez/remote-tunes/releases/download/v1.2.0/app-arm64-v8a-release.apk');
      expect(info.apkName, 'app-arm64-v8a-release.apk');
      expect(info.size, 123);
      expect(info.sha256, isNull);
      expect(asked.last, startsWith('HEAD '));
      expect((await checker(api: 429, location: page).latest(currentVersion: '1.1.0', abi: 'arm64-v8a'))!.version, '1.2.0');
    });

    test('says up to date, or says plainly what to do', () async {
      expect(await checker(location: page).latest(currentVersion: '1.2.0', abi: 'arm64-v8a'), isNull);
      Matcher says(String words) => throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains(words)));
      await expectLater(checker().latest(currentVersion: '1.1.0', abi: 'arm64-v8a'), says('use mobile data'));
      await expectLater(checker(location: 'https://github.com/login').latest(currentVersion: '1.1.0', abi: 'arm64-v8a'), says('mobile data'));
      await expectLater(checker(location: page, file: 404).latest(currentVersion: '1.1.0', abi: 'arm64-v8a'), says('no download'));
      await expectLater(checker().recentReleases(), says('mobile data'));
    });
  });
}
