import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/core/screen_awake.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/features/ambience/ambience_backup.dart';
import 'package:remote_tunes/features/ambience/ambience_banner.dart';
import 'package:remote_tunes/features/ambience/ambience_controller.dart';
import 'package:remote_tunes/features/ambience/ambience_models.dart';
import 'package:remote_tunes/features/ambience/ambience_night.dart';
import 'package:remote_tunes/features/ambience/ambience_phone.dart' show PhoneAmbienceFiles;
import 'package:remote_tunes/features/ambience/ambience_view.dart';
import 'package:remote_tunes/features/backup/backup_screen.dart';
import 'package:remote_tunes/providers/providers.dart';

import 'ambience_controller_test.dart' show FakeEngine, FakeFiles, MemoryAmbienceStore;

/// A folder picker that always answers the same folder.
class _Folder implements BackupPicker {
  _Folder(this.folder);
  final String folder;

  @override
  Future<String?> pickFolder(BuildContext context) async => folder;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('backup', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('rt_amb_test_'));
    tearDown(() => root.delete(recursive: true));

    /// A phone with real files in its own folder.
    AmbienceController phone(String name, [MemoryAmbienceStore? store]) => AmbienceController(
          engine: FakeEngine(),
          files: PhoneAmbienceFiles(() async => Directory(p.join(root.path, name))),
          store: store ?? MemoryAmbienceStore(),
        );

    Future<String> file(String name, List<int> bytes) async {
      final f = File(p.join(root.path, 'down', name));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
      return f.path;
    }

    Future<AmbienceController> setUpOld() async {
      final old = phone('old');
      await old.addFile('rain', await file('rain.mp3', [1, 1, 1]));
      await old.addOwnSound('Music Box', await file('box.wav', [2, 2]));
      await old.addOwnSound('Swamp', await file('swamp.ogg', [3]), environment: true);
      final box = old.state.sounds.firstWhere((s) => s.name == 'Music Box').id;
      await old.setIcon(box, 'emoji:🎁');
      await old.setBoost('rain', 2);
      await old.setActive('rain', true);
      await old.setActive(box, true);
      await old.setVolume(box, 0.8);
      await old.saveMix('Pampatulog');
      await old.setTimer(45);
      await old.setMaxVolume(0.6);
      await old.setSchedule(const AmbienceSchedule(enabled: true, hour: 19, minute: 30, mixId: 'sleep'));
      await old.setBanner('Rain', Uint8List.fromList([9, 9]), const BannerFraming(zoom: 2, aspect: 2), newSource: await file('photo.jpg', [8]));
      return old;
    }

    Future<List<int>> soundBytes(AmbienceController c, String name) async {
      final id = c.state.sounds.firstWhere((s) => s.name == name).id;
      final json = (await c.exportData()).data['files'] as Map;
      final files = (await c.exportData()).files;
      return File(files[json[id]]!).readAsBytes();
    }

    test('one file carries everything to a new phone', () async {
      final old = await setUpOld();
      final backup = await writeAmbienceBackup(old, root.path, now: DateTime(2026, 11, 27));
      expect(p.basename(backup.path), 'RemoteTunes-Ambience-2026-11-27.rtambience');

      final store = MemoryAmbienceStore();
      final fresh = phone('new', store);
      final r = await restoreAmbienceBackup(fresh, backup.path);
      expect((r.sounds, r.mixes, r.banners), (3, 1, 1));
      final s = fresh.state;
      expect(s.sound('rain')!.available, isTrue);
      expect(s.sound('rain')!.boost, 2);
      final box = s.sounds.firstWhere((x) => x.name == 'Music Box');
      expect((box.icon, box.category), ('emoji:🎁', ambienceOwnCategory));
      expect(s.sounds.firstWhere((x) => x.name == 'Swamp').category, ambienceEnvironmentCategory);
      expect(await soundBytes(fresh, 'Music Box'), [2, 2]);
      expect(s.mixes.last.name, 'Pampatulog');
      expect(s.mixes.last.layers[box.id], 0.8);
      expect(s.active.keys, containsAll(['rain', box.id]));
      expect((s.maxVolume, s.timerMinutes), (0.6, 45));
      expect(s.playing, isFalse, reason: 'restoring plays nothing');
      expect((fresh.schedule.enabled, fresh.schedule.hour, fresh.schedule.minute), (true, 19, 30));
      final banner = fresh.banner('Rain')!;
      expect(File(banner.imagePath).readAsBytesSync(), [9, 9]);
      expect(File(banner.sourcePath!).readAsBytesSync(), [8]);
      expect((banner.framing.zoom, banner.framing.aspect), (2, 2));
      // Still all there after a restart.
      final again = phone('new', store);
      await again.load();
      expect(again.state.sound('rain')!.available, isTrue);
      expect(again.banner('Rain'), isNotNull);
      fresh.dispose();
      again.dispose();
      old.dispose();
    });

    test('restoring twice adds nothing, and what the phone has stays', () async {
      final old = await setUpOld();
      final backup = await writeAmbienceBackup(old, root.path);
      final mine = phone('mine');
      await mine.addFile('rain', await file('mine.mp3', [7, 7, 7, 7]));
      await mine.addOwnSound('music box', await file('my box.wav', [6]));
      await mine.setActive('rain', true);
      await mine.setMaxVolume(0.3);
      final first = await restoreAmbienceBackup(mine, backup.path);
      expect(first.sounds, 1, reason: 'only the swamp is new');
      expect(await soundBytes(mine, 'music box'), [6]);
      expect(mine.state.maxVolume, 0.3, reason: 'never louder because of a backup');
      expect(mine.state.sound('rain')!.boost, 2, reason: 'not set here before');
      final myBox = mine.state.sounds.firstWhere((x) => x.name == 'music box').id;
      expect(mine.state.mixes.last.layers.keys, contains(myBox), reason: 'the mix points at my copy');
      final second = await restoreAmbienceBackup(mine, backup.path);
      expect((second.sounds, second.mixes, second.banners), (0, 0, 0));
      mine.dispose();
      old.dispose();
    });

    test('a second backup the same day does not replace the first', () async {
      final old = await setUpOld();
      final day = DateTime(2026, 11, 27);
      await writeAmbienceBackup(old, root.path, now: day);
      final second = await writeAmbienceBackup(old, root.path, now: day);
      expect(p.basename(second.path), 'RemoteTunes-Ambience-2026-11-27 (2).rtambience');
      old.dispose();
    });

    test('something else is refused in plain words, and names inside cannot leave the folder', () async {
      final c = phone('x');
      await expectLater(restoreAmbienceBackup(c, await file('no.rtambience', [1, 2, 3])),
          throwsA(isA<AmbienceException>().having((e) => e.message, 'message', 'That is not an Ambience backup.')));
      final zip = File(p.join(root.path, 'evil.rtambience'));
      final archive = Archive()
        ..addFile(ArchiveFile.string(
            'ambience.json',
            jsonEncode({
              'kind': 'ambience',
              'format': 1,
              'data': {
                'files': {'rain': '../escape.mp3'}
              }
            })))
        ..addFile(ArchiveFile('files/../escape.mp3', 1, [1]));
      await zip.writeAsBytes(ZipEncoder().encode(archive));
      final r = await restoreAmbienceBackup(c, zip.path);
      expect(r.sounds, 0);
      expect(File(p.join(root.path, 'escape.mp3')).existsSync(), isFalse);
      final newer = File(p.join(root.path, 'newer.rtambience'));
      await newer.writeAsBytes(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile.string('ambience.json', jsonEncode({'kind': 'ambience', 'format': 9, 'data': {}})))));
      await expectLater(restoreAmbienceBackup(c, newer.path),
          throwsA(isA<AmbienceException>().having((e) => e.message, 'message', contains('newer version'))));
      c.dispose();
    });
  });

  group('the bedtime schedule', () {
    late FakeEngine engine;
    late MemoryAmbienceStore store;
    setUp(() {
      engine = FakeEngine();
      store = MemoryAmbienceStore();
    });

    void night(void Function(FakeAsync async, AmbienceController c) body, {DateTime? from}) {
      fakeAsync((async) {
        final start = from ?? DateTime(2026, 11, 27, 19, 0);
        final c = AmbienceController(engine: engine, files: FakeFiles(), store: store, now: () => start.add(async.elapsed));
        c.load();
        async.flushMicrotasks();
        body(async, c);
        c.dispose();
      });
    }

    const eight = AmbienceSchedule(enabled: true, hour: 20, mixId: 'calm-noise', timerMinutes: 30);

    test('starts the mix at its time, with its timer, and again the next day', () {
      night((async, c) {
        c.setSchedule(eight);
        async.elapse(const Duration(minutes: 59));
        expect(engine.voices, isEmpty);
        expect(c.nextStart, DateTime(2026, 11, 27, 20));
        async.elapse(const Duration(minutes: 2));
        expect(engine.voices.keys, {'pink-noise', 'green-noise'});
        expect(c.state.timerMinutes, 30);
        expect(c.nextStart, DateTime(2026, 11, 28, 20));
        async.elapse(const Duration(minutes: 31));
        expect(engine.voices, isEmpty, reason: 'the timer ended it');
        async.elapse(const Duration(hours: 23, minutes: 30)); // 20:02 the next day
        expect(engine.voices, isNotEmpty);
      });
    });

    test('stopped by hand, it does not start again the same evening', () {
      night((async, c) {
        c.setSchedule(eight);
        async.elapse(const Duration(minutes: 61));
        c.stop();
        async.elapse(const Duration(minutes: 5));
        expect(engine.voices, isEmpty);
      });
    });

    test('a time already past today waits for tomorrow', () {
      night((async, c) {
        c.setSchedule(const AmbienceSchedule(enabled: true, hour: 18, minute: 55, mixId: 'calm-noise'));
        async.elapse(const Duration(minutes: 5));
        expect(engine.voices, isEmpty);
        expect(c.nextStart, DateTime(2026, 11, 28, 18, 55));
      });
    });

    test('a few minutes late still starts; much later does not', () {
      store.value = jsonEncode({'schedule': eight.toJson()});
      night((async, c) {
        expect(engine.voices, isNotEmpty);
      }, from: DateTime(2026, 11, 27, 20, 6));
      engine.voices.clear();
      store.value = jsonEncode({'schedule': eight.toJson()});
      night((async, c) {
        expect(engine.voices, isEmpty);
        expect(c.nextStart, DateTime(2026, 11, 28, 20));
      }, from: DateTime(2026, 11, 27, 20, 30));
    });

    test('off does nothing, and a mix that cannot play says why', () {
      night((async, c) {
        c.setSchedule(eight.copyWith(enabled: false));
        async.elapse(const Duration(hours: 2));
        expect(engine.voices, isEmpty);
        expect(c.nextStart, isNull);
      });
      night((async, c) {
        c.setSchedule(eight.copyWith(mixId: 'campfire'));
        async.elapse(const Duration(minutes: 61));
        expect(c.state.error, contains('bedtime mix could not start'));
      });
    });

    test('is read back as it was kept', () {
      final s = AmbienceSchedule.fromJson(eight.toJson());
      expect((s.enabled, s.hour, s.minute, s.mixId, s.timerMinutes), (true, 20, 0, 'calm-noise', 30));
      expect(AmbienceSchedule.fromJson('x').enabled, isFalse);
      expect(AmbienceSchedule.fromJson({'on': true, 'hour': 99}).hour, 23);
    });
  });

  group('the Backup screen', () {
    testWidgets('saves a backup to the chosen folder and restores a chosen file', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final dir = Directory.systemTemp.createTempSync('rt_amb_ui_');
      addTearDown(() => dir.deleteSync(recursive: true));
      AmbienceController at(String name) => AmbienceController(
            engine: FakeEngine(),
            files: PhoneAmbienceFiles(() async => Directory(p.join(dir.path, name))),
            store: MemoryAmbienceStore(),
          );
      final old = at('old');
      final fresh = at('new');
      addTearDown(old.dispose);
      addTearDown(fresh.dispose);
      final sound = File(p.join(dir.path, 'box.mp3'))..writeAsBytesSync([1, 2]);
      await tester.runAsync(() => old.addOwnSound('Music Box', sound.path));
      var current = old;
      String? chosen;
      tester.view.physicalSize = const Size(500, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          backupPickerProvider.overrideWithValue(_Folder(dir.path)),
          ambienceForBackupProvider.overrideWithValue(() async => current),
          ambienceBackupPickerProvider.overrideWithValue((_) async => chosen),
        ],
        child: const MaterialApp(home: BackupScreen()),
      ));

      Future<void> press(String key, Finder done) async {
        await tester.tap(find.byKey(Key(key)));
        for (var i = 0; i < 100 && done.evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(done, findsWidgets);
      }

      await press('ambience-backup', find.textContaining('.rtambience'));
      final backup = dir.listSync().whereType<File>().singleWhere((f) => f.path.endsWith('.rtambience'));
      // Let the first message go before the next one.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      current = fresh;
      chosen = backup.path;
      await press('ambience-restore', find.textContaining('1 sound'));
      expect(fresh.state.sounds.map((s) => s.name), contains('Music Box'));
    });
  });

  group('on the screen', () {
    late AmbienceController c;
    late FakeEngine engine;
    final dims = <double?>[];
    final awake = <bool>[];

    setUp(() {
      engine = FakeEngine();
      c = AmbienceController(engine: engine, files: FakeFiles(), store: MemoryAmbienceStore(), now: () => DateTime(2026, 11, 27, 9));
      dims.clear();
      awake.clear();
      ScreenDim.apply = (v) async => dims.add(v);
      ScreenAwake.setFlag = (v) async => awake.add(v);
    });

    AmbienceOwner owner() => AmbienceOwner(
          pickFile: () async => null,
          addFile: c.addFile,
          addOwnSound: c.addOwnSound,
          removeFile: c.removeFile,
          setMaxVolume: c.setMaxVolume,
          schedule: () => c.schedule,
          setSchedule: c.setSchedule,
          nextStart: () => c.nextStart,
          night: true,
        );

    void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
      testWidgets(name, (tester) async {
        await body(tester);
        await c.stop();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 8));
        c.dispose();
      });
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
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    screenTest('the schedule is set from its button', (tester) async {
      await open(tester);
      await tap(tester, 'amb-schedule');
      expect(find.textContaining('only start while RemoteTunes is running'), findsOneWidget);
      await tap(tester, 'sch-on');
      await tap(tester, 'sch-save');
      expect(c.schedule.enabled, isTrue);
      expect(c.state.mixes.map((m) => m.id), contains(c.schedule.mixId));
      await tap(tester, 'amb-schedule');
      await tap(tester, 'sch-on');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.schedule.enabled, isTrue, reason: 'cancel keeps it');
    });

    screenTest('night mode is dark, keeps the screen on, and lets go when left', (tester) async {
      await open(tester);
      await c.setActive('white-noise', true);
      await tester.pump();
      await tester.tap(find.byKey(const Key('amb-night')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('night-time')), findsOneWidget);
      expect(awake, [true]);
      expect(dims, [0.01]);
      expect(find.byKey(const Key('night-stop')), findsNothing, reason: 'nothing bright until tapped');
      await tester.tap(find.byKey(const Key('night-screen')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('night-play')));
      await tester.pump();
      expect(c.state.playing, isFalse);
      await tester.pump(const Duration(seconds: 7));
      expect(find.byKey(const Key('night-play')), findsNothing, reason: 'they hide again');
      await tester.tap(find.byKey(const Key('night-screen')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('night-leave')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('night-time')), findsNothing);
      expect(awake, [true, false]);
      expect(dims, [0.01, null]);
    });

    testWidgets('night mode says when it will start', (tester) async {
      final quiet = AmbienceController(engine: engine, files: FakeFiles(), store: MemoryAmbienceStore());
      await quiet.load();
      await tester.pumpWidget(MaterialApp(
        home: AmbienceNightScreen(controls: quiet, nextStart: () => DateTime(2026, 11, 27, 20, 15), now: () => DateTime(2026, 11, 27, 19)),
      ));
      expect(find.textContaining('Starts at'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      quiet.dispose();
    });

    screenTest('all the round buttons fit a narrow phone; the other phone has neither', (tester) async {
      await open(tester, size: const Size(320, 600));
      expect(tester.takeException(), isNull);
      await open(tester, owned: false);
      expect(find.byKey(const Key('amb-night')), findsNothing);
      expect(find.byKey(const Key('amb-schedule')), findsNothing);
    });
  });
}
